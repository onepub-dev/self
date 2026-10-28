import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart' show PackedResource;
import 'package:dcli/posix.dart' show chmod;
import 'package:path/path.dart' as p;
import 'package:self/src/cron_manager.dart';
import 'package:self/src/restart.dart';
import 'package:self/src/safe_files.dart';
import 'package:self/src/self_logger.dart';
import 'package:test/test.dart';
// ignore: avoid_relative_lib_imports
import '../example/lib/src/launch_args.dart';

class QuietLogger implements SelfLogger {
  @override
  void noSuchMethod(Invocation invocation) {}
}

class Fixture extends PackedResource {
  @override
  final String originalPath;
  @override
  final String content;
  Fixture(this.originalPath, {String? encoded})
    : content = encoded ?? base64.encode(utf8.encode('dummy bytes'));
  @override
  String get checksum => '';
}

void main() {
  final throwsFileSystemException = throwsA(isA<FileSystemException>());
  test('both example launcher aliases select run mode', () {
    final parser = ArgParser()
      ..addFlag('launch', abbr: 'l', negatable: false)
      ..addFlag('debug', abbr: 'd');
    for (final alias in ['-l', '--launch']) {
      expect(childArguments(parser.parse([alias])), ['--run']);
      expect(childArguments(parser.parse([alias, '--debug'])), [
        '--run',
        '--debug',
      ]);
    }
  });
  String render({
    List<String> args = const [],
    String user = 'user',
    String exe = '/app/bin',
    String cwd = '/app',
  }) => renderBootEntry(
    pathToExecutable: exe,
    args: args,
    workingDirectory: cwd,
    runAsUser: user,
  );
  test('cron preserves argument boundaries and quotes shell syntax', () {
    expect(
      render(args: ['', 'a b', "a'b", r'$(touch marker); &']),
      "@reboot user cd '/app' && '/app/bin' '' 'a b' 'a'\\''b' '\$(touch marker); &'\n",
    );
  });
  test('cron rejects structural injection in every field', () {
    for (final bad in ['\n', '\r', '\t', '\x00', '\x7f', '%']) {
      expect(() => render(args: ['a${bad}b']), throwsArgumentError);
      expect(() => render(exe: '/a${bad}b'), throwsArgumentError);
      expect(() => render(cwd: '/a${bad}b'), throwsArgumentError);
      expect(() => render(user: 'a${bad}b'), throwsArgumentError);
    }
    for (final bad in ['root other', '-root', 'a;id', '']) {
      expect(() => render(user: bad), throwsArgumentError);
    }
    expect(() => render(exe: 'relative'), throwsArgumentError);
    expect(() => render(cwd: '-P'), throwsArgumentError);
  });
  test('paths reject POSIX and Windows escapes and aliases', () {
    for (final path in [
      '',
      '../x',
      '/x',
      'a/../x',
      'a//x',
      './x',
      r'C:\x',
      'C:x',
      r'\\server\share',
      r'a\..\x',
      'x:stream',
      'NUL.txt',
      'NUL .txt',
      'CON .txt',
      'COM¹.txt',
      'LPT³.txt',
      'nested/COM1 .cfg',
      'a/con',
      'x.',
      'x ',
      'x\n',
    ]) {
      expect(
        () => validateResourcePath(path),
        throwsArgumentError,
        reason: path,
      );
    }
    validateResourcePath('nested/file.txt');
    expect(() => validateExecutableName('nested/app'), throwsArgumentError);
  });
  group('isolated filesystem operations', () {
    late Directory root;
    setUp(() {
      root = Directory('/tmp').createTempSync('self-security-test-');
    });
    tearDown(() {
      root.deleteSync(recursive: true);
    });
    test('cron replacement writes only scratch path and rejects symlink', () {
      final target = File(p.join(root.path, 'job'))..writeAsStringSync('old');
      void write() => CronManager(QuietLogger()).addBoot(
        pathToExecutable: '/app/bin',
        args: ['a b'],
        workingDirectory: '/app',
        runAsUser: 'user',
        altCronPath: target.path,
      );
      write();
      expect(target.readAsStringSync(), render(args: ['a b']));
      if (!Platform.isWindows) {
        expect(target.statSync().mode & 0x1ff, 0x1a4);
        target.deleteSync();
        final sentinel = File(p.join(root.path, 'sentinel'))
          ..writeAsStringSync('KEEP');
        Link(target.path).createSync(sentinel.path);
        expect(write, throwsFileSystemException);
        expect(sentinel.readAsStringSync(), 'KEEP');
      }
    });
    test('substituted staged link is rejected without touching sentinel', () {
      final sentinel = File(p.join(root.path, 'sentinel'))
        ..writeAsStringSync('KEEP');
      final target = File(p.join(root.path, 'app'))..writeAsStringSync('old');
      expect(
        () => stageFile(
          target.path,
          (path) => Link(path).createSync(sentinel.path),
        ),
        throwsFileSystemException,
      );
      expect(sentinel.readAsStringSync(), 'KEEP');
      expect(target.readAsStringSync(), 'old');
      expect(root.listSync().length, 2);
    }, skip: Platform.isWindows ? 'Requires symlink privilege' : false);
    test(
      'extracts nested resources and rejects traversal without outside writes',
      () {
        final install = p.join(root.path, 'install');
        unpackResource(install, Fixture('nested/readme'));
        expect(
          File(p.join(install, 'nested/readme')).readAsStringSync(),
          'dummy bytes',
        );
        expect(
          () => unpackResource(install, Fixture('../outside')),
          throwsArgumentError,
        );
        expect(File(p.join(root.path, 'outside')).existsSync(), isFalse);
      },
    );
    test('symlink destination and ancestor preserve sentinel', () {
      final sentinel = File(p.join(root.path, 'sentinel'))
        ..writeAsStringSync('KEEP');
      final link = Link(p.join(root.path, 'link'))..createSync(sentinel.path);
      expect(
        () =>
            stageFile(link.path, (path) => File(path).writeAsStringSync('bad')),
        throwsFileSystemException,
      );
      final dirLink = Link(p.join(root.path, 'dirlink'))..createSync(root.path);
      expect(
        () => unpackResource(dirLink.path, Fixture('sentinel')),
        throwsFileSystemException,
      );
      expect(sentinel.readAsStringSync(), 'KEEP');
    }, skip: Platform.isWindows ? 'Requires symlink privilege' : false);
    test('private unpredictable staging, atomic replacement and cleanup', () {
      final target = File(p.join(root.path, 'app'))..writeAsStringSync('old');
      final stages = <String>[];
      for (var i = 0; i < 2; i++) {
        stageFile(target.path, (path) {
          stages.add(p.dirname(path));
          expect(p.dirname(p.dirname(path)), root.path);
          if (!Platform.isWindows) {
            expect(Directory(p.dirname(path)).statSync().mode & 0x1ff, 0x1c0);
          }
          expect(target.readAsStringSync(), i == 0 ? 'old' : 'dummy');
          File(path).writeAsStringSync('dummy');
        });
      }
      expect(stages[0], isNot(stages[1]));
      expect(root.listSync().map((entity) => p.basename(entity.path)), ['app']);
      expect(target.readAsStringSync(), 'dummy');
    });
    test('malformed resource preserves old file and cleans staging', () {
      final target = File(p.join(root.path, 'readme'))
        ..writeAsStringSync('KEEP');
      expect(
        () => unpackResource(
          root.path,
          Fixture('readme', encoded: 'not-base64!'),
        ),
        throwsFormatException,
      );
      expect(target.readAsStringSync(), 'KEEP');
      expect(root.listSync().length, 1);
    });
    test('resource replacement preserves private and executable modes', () {
      if (Platform.isWindows) {
        return;
      }
      for (final mode in [0x180, 0x1c0]) {
        final target = File(p.join(root.path, 'resource-$mode'))
          ..writeAsStringSync('old');
        chmod(target.path, permission: mode.toRadixString(8));
        unpackResource(root.path, Fixture(p.basename(target.path)));
        expect(target.statSync().mode & 0x1ff, mode);
      }
    });
  });
  test('zero exit stops without restart or delay', () async {
    var runs = 0;
    await restartOnFailure(
      run: () async {
        runs++;
        return 0;
      },
      delay: () {
        fail('unexpected delay');
      },
    );
    expect(runs, 1);
  });
  test('failure budget is finite and success ends retries', () async {
    var runs = 0;
    var delays = 0;
    await expectLater(
      restartOnFailure(
        maxRestarts: 2,
        run: () async {
          runs++;
          return 1;
        },
        delay: () async {
          delays++;
        },
      ),
      throwsStateError,
    );
    expect(runs, 3);
    expect(delays, 2);
    runs = 0;
    await expectLater(
      restartOnFailure(
        maxRestarts: 0,
        run: () async {
          runs++;
          return 1;
        },
        delay: () {
          fail('no retry delay');
        },
      ),
      throwsStateError,
    );
    expect(runs, 1);
    runs = 0;
    await restartOnFailure(
      run: () async => ++runs == 2 ? 0 : 1,
      delay: () async {},
    );
    expect(runs, 2);
    await expectLater(
      restartOnFailure(
        maxRestarts: -1,
        run: () {
          fail('must not run');
        },
        delay: () async {},
      ),
      throwsArgumentError,
    );
  });
}
