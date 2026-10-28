// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:path/path.dart';

import 'cron_manager.dart' show CronManager;
import 'restart.dart';
import 'safe_files.dart';
import 'self_logger.dart';

class Self {
  static Self? _self;

  final String executableName;

  final String basename;

  final SelfLogger logger;

  final String installPath;

  final Map<String, PackedResource> resources;

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
    validateExecutableName(executableName);
    for (final resource in resources.values) {
      validateResourcePath(resource.originalPath);
      if (resource.originalPath.toLowerCase() == executableName.toLowerCase()) {
        throw ArgumentError('Resource collides with executable name');
      }
    }
    _self ??= Self._internal(
      logger: logger,
      executableName: executableName,
      installPath: installPath,
      resources: Map.unmodifiable(resources),
    );

    return _self!;
  }

  Self._internal({
    required this.logger,
    required this.executableName,
    required this.installPath,
    required this.resources,
  }) : basename = basenameWithoutExtension(executableName);

  /// Launches the application as a sub process.
  /// If the sub-process exits with anything other
  /// than exit code 0, we restart it.
  /// Stops after success or at most [maxRestarts] retries (default five).
  /// Exhaustion throws StateError; invalid limits throw ArgumentError.
  Future<void> launch({required List<String> args, int maxRestarts = 5}) async {
    logger.info('Launching $basename from $executableName');

    // start the server and relaunch it if it fails.
    await restartOnFailure(
      maxRestarts: maxRestarts,
      run: () async {
        final result = startFromArgs(
          _pathToExecutable,
          args,
          nothrow: true,
          progress: Progress(logger.info, stderr: logger.severe),
        );
        if (result.exitCode != 0) {
          logger
            ..severe('$basename failed with exitCode: ${result.exitCode}')
            ..info('Retrying if the restart budget permits');
        }
        return result.exitCode!;
      },
      delay: () => sleepAsync(10),
    );
  }

  String get _pathToExecutable => join(installPath, executableName);

  /// Adds a cron job to restart the application when the system
  /// boots.
  /// The application's working directory is set to the
  /// [installPath].
  /// The [args] parameters are passed
  /// to the application when it is started as command line
  /// arguments.
  void addBootLauncher({
    required List<String> args,
    required String runAsUser,
    String? altCronPath,
  }) {
    CronManager(logger).addBoot(
      pathToExecutable: _pathToExecutable,
      workingDirectory: installPath,
      args: args,
      runAsUser: runAsUser,
      altCronPath: altCronPath,
    );
  }

  /// Installs the application, unpacking any resources.
  /// The caller must prevent untrusted writes to the installation directory
  /// and every ancestor throughout installation. Symlink checks cannot close
  /// concurrent pathname races. Windows additionally requires trusted inherited
  /// ACLs and no junctions/reparse points (not verified portably by dart:io).
  Future<void> install() async {
    /// Installs the application into the [installPath].
    final pathToExe = truepath(installPath, executableName);

    print('Creating install directory: $installPath');
    checkDirectory(installPath, create: true);

    print('Unpacking resources');
    _unpackResources(
      installPath: installPath,
      logger: logger,
      resources: resources,
    );

    print('Installing the application');
    // Copy the trusted installer into private destination-side staging, then
    // rename it over the old executable without opening the old file.
    stageFile(
      pathToExe,
      (path) => File(DartScript.self.pathToExe).copySync(path),
    );

    print('Installation complete.');
  }

  void _unpackResources({
    required String installPath,
    required SelfLogger logger,
    required Map<String, PackedResource> resources,
  }) {
    logger.info('unpacking resources to: $installPath');
    for (final resource in resources.values) {
      validateResourcePath(resource.originalPath);
      final localPathTo = truepath(installPath, resource.originalPath);

      logger.info('unpacking resources to: $localPathTo');

      unpackResource(installPath, resource);
    }
  }
}
