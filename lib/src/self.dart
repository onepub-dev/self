// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:path/path.dart';

import 'cron_manager.dart' show CronManager;
import 'self_logger.dart';

class Self {
  /// Pass in the directory [installPath] where you want the executable
  /// to be installed.
  /// The [executableName] defines the name the executable is to
  /// be called when we install it.
  factory Self({
    required SelfLogger logger,
    required String installPath,
    required String executableName,
    required Map<String, PackedResource> resources,
  }) {
    _self ??= Self._internal(
      logger: logger,
      executableName: executableName,
      installPath: installPath,
      resources: resources,
    );

    return _self!;
  }

  Self._internal({
    required this.logger,
    required this.executableName,
    required this.installPath,
    required this.resources,
  }) : basename = basenameWithoutExtension(executableName);
  static Self? _self;

  final String executableName;
  final String basename;
  final SelfLogger logger;
  final String installPath;
  final Map<String, PackedResource> resources;

  /// Launches the application as a sub process.
  /// If the sub-process exits with anything other
  /// than exit code 0, we restart it.
  void launch({required List<String> args}) {
    logger.info('Launching $basename from $executableName');

    // start the server and relaunch it if it fails.
    for (;;) {
      final result = startFromArgs(
        _pathToExecutable,
        args,
        nothrow: true,
        progress: Progress(logger.info, stderr: logger.severe),
      );
      logger
        ..severe('$basename failed with exitCode: ${result.exitCode}')
        ..info('restarting $basename in 10 seconds');
      sleep(10);
    }
  }

  String get _pathToExecutable => join(installPath, executableName);

  /// Adds a cron job to restart the application when the system
  /// boots.
  /// The [args] parameters are passed
  /// to the application when it is started as command line
  /// arguments.
  void addBootLauncher({
    required List<String> args,
    required String runAsUser,
  }) {
    CronManager(logger).addBoot(_pathToExecutable, args, runAsUser);
  }

  /// Installs the application, unpacking any resources.
  Future<void> install() async {
    /// Installs the application into the [installPath].
    final pathToExe = truepath(installPath, executableName);

    print('Creating install directory');
    if (!exists(installPath)) {
      createDir(installPath);
    }

    print('Unpacking resources');
    _unpackResources(
      installPath: installPath,
      logger: logger,
      resources: resources,
    );

    if (Platform.isWindows) {
      if (exists(pathToExe)) {
        try {
          delete(pathToExe);
        } on DeleteException catch (_) {
          // probably means that the exec is running.
          logger.severe('''
Unable to delete $pathToExe, ensure the process has stopped and try again''');
          rethrow;
        }
      }
    }

    print('Installing the application');
    // move this exe (the installer) over the existing
    // executable renaming it as we go.
    // This should work even if the exe is srunning.
    // When it gets restarted it will then run the new exe.
    final tempName = '${DartScript.self.pathToExe}.tmp';

    // we copy the installer  we get to keep it
    copy(DartScript.self.pathToExe, tempName, overwrite: true);

    move(tempName, join(installPath, executableName), overwrite: true);

    print('Installation complete.');
  }

  void _unpackResources({
    required String installPath,
    required SelfLogger logger,
    required Map<String, PackedResource> resources,
  }) {
    logger.info('unpacking resources to: $installPath');
    for (final resource in resources.values) {
      final localPathTo = truepath(installPath, resource.originalPath);
      final resourceDir = dirname(localPathTo);

      if (!exists(resourceDir)) {
        createDir(resourceDir);
      }

      logger.info('unpacking resources to: $localPathTo');

      resource.unpack(localPathTo);
    }
  }
}
