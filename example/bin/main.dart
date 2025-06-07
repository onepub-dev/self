#! /home/bsutton/apps/flutter/bin/dart
// ignore_for_file: avoid_print, avoid_catches_without_on_clauses

import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:dcli/dcli.dart';
import 'package:self/src/dcli/resource/generated/resource_registry.g.dart';
import 'package:self/src/self.dart';

// ignore: avoid_relative_lib_imports
import '../lib/src/my_logger.dart';

late MyLogger logger;
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'launch',
      abbr: 'l',
      negatable: false,
      help: '''
Launches the application as a sub-process and will restart it if it crashes.
''',
    )
    ..addFlag(
      'run',
      abbr: 'r',
      negatable: false,
      help: '''
Run the application.
''',
    )
    ..addFlag(
      'install',
      abbr: 'i',
      negatable: false,
      help: '''
Extracts and installs the application, adding a cronjob so it launches on boot.
''',
    )
    ..addFlag('debug', abbr: 'd', help: 'Enable fine logging')
    ..addFlag('help', help: 'Print the usage message');

  // for the moment we don't want to be running as sudo
  // as it screws up env vars and file permissions.
  Shell.current.releasePrivileges();

  ArgResults? results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print(red(e.message));
    print(parser.usage);
    await exitWithFlush(1);
  }

  final run = results!.flag('run');
  final install = results.flag('install');
  final launch = results.flag('launch');
  final debug = results.flag('debug');
  final help = results.flag('help');

  if (help) {
    print('''A description of what your app does''');
    print(parser.usage);
    await exitWithFlush(0);
  }

  // The user must pass one of the flags.
  if (!_exactlyOne(install: install, launch: launch, run: run)) {
    printerr(red('You must pass one of --install, --launch, --run'));
    print(parser.usage);
    await exitWithFlush(1);
  }

  // MyLogger implements SelfLogger so [Self] can
  // log through your existing logging system.
  logger = await MyLogger.create(logFilePath: './logfile.log', debug: debug);
  final self = Self(
    logger: logger,
    installPath: '$HOME/myapp',
    executableName: 'myapp',
    resources: ResourceRegistry.resources,
  );

  if (install) {
    await _install(self);
  }

  /// we are running in launch mode
  if (launch) {
    await _launch(args, self);
  }

  if (run) {
    await _run(args, logger);
  }

  // Use a 0 exit code to tell the launcher not to restart us as we are shutting
  // down intentionally.
  //
  // technically not required as if we return from main
  // the app exit with a non-zero exit code anyway.
  await exitWithFlush(0);
}

// If we got here you either launched your application directly
// from the command line or it was launched by Self().launch in
// a sub process.
Future<void> _run(List<String> args, MyLogger logger) async {
  try {
    logger.info('Staring My App');
    runMyApp(args);
  } catch (e, st) {
    logger.severe('Unexpected exception, exiting', error: e, stackTrace: st);

    /// Ensure we get re-launched by self.launch by existing with
    /// a non-zero exit code.
    await exitWithFlush(1);
  }
  await exitWithFlush(0);
}

// Launch this application along with any command line arguments you
// want passed to your app
// By using ..args we are taken any args passed from the command
// but we MUST remove the --launch flag otherwise we will get
// into an endless loop.
Future<void> _launch(List<String> args, Self self) async {
  final trimmedArgs = args.toList(growable: true)..remove('--launch');
  self.launch(args: [...trimmedArgs, '--debug']);
  await exitWithFlush(0);
}

// Call install along with any command line arguments you
// want passed to your app when the cron job calls your app.
// We pass in --launch so our app gets launched at boot using
// the below launch mode.
Future<void> _install(Self self) async {
  await self.install();

  if (!io.Platform.isWindows) {
    // add a cron job to restart the app on boot
    // you will need to be running as sudo to do this.
    if (!Shell.current.isPrivilegedProcess) {
      print(
        red('''
Please rerun with sudo to install the cron job via:
sudo env PATH="\$PATH" ./${DartScript.self.basename} --install
  '''),
      );
      await exitWithFlush(0);
    }

    // regain sudo priviliges to install the cron job.
    Shell.current.withPrivileges(() {
      self.addBootLauncher(
        args: ['--launch'],
        runAsUser: Shell.current.loggedInUser!,
      );
    });
  }

  // add any additional installation steps here.
  // ...
  // ...

  await exitWithFlush(0);
}

/// Only one of the args may be true.
bool _exactlyOne({
  required bool install,
  required bool launch,
  required bool run,
}) {
  var count = 0;
  if (install) {
    count++;
  }
  if (launch) {
    count++;
  }
  if (run) {
    count++;
  }

  return count == 1;
}

void runMyApp(List<String> args) {
  print('My App is running');
}

Future<void> exitWithFlush(int code) async {
  // Flush & close your logger(s):
  await logger.close();
  // Then terminate the process:
  io.exit(code);
}
