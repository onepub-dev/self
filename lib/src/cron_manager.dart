import 'dart:io';

import 'package:path/path.dart';

import 'safe_files.dart';
import 'self_logger.dart';

/// Pure serialization. Cron processes percent even inside shell quotes.
String renderBootEntry({
  required String pathToExecutable,
  required List<String> args,
  required String workingDirectory,
  required String runAsUser,
}) {
  if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_-]*\$?$').hasMatch(runAsUser)) {
    throw ArgumentError.value(runAsUser, 'runAsUser', 'Invalid username');
  }
  String quote(String value) {
    if (RegExp(r'[\x00-\x1f\x7f-\x9f%]').hasMatch(value)) {
      throw ArgumentError('Cron fields cannot contain controls or percent');
    }
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  if (!posix.isAbsolute(pathToExecutable) ||
      !posix.isAbsolute(workingDirectory)) {
    throw ArgumentError(
      'Cron executable and working directory must be absolute',
    );
  }
  final command = [pathToExecutable, ...args].map(quote).join(' ');
  return '@reboot $runAsUser cd ${quote(workingDirectory)} && $command\n';
}

class CronManager {
  final SelfLogger logger;
  CronManager(this.logger);

  /// Replaces the selected file atomically. Callers must protect its parent and
  /// all ancestors against untrusted changes throughout; checks cannot prevent
  /// pathname races. Use a unique altCronPath for colliding executable names.
  /// Existing regular files are replaced; symlinks are rejected.
  void addBoot({
    required String pathToExecutable,
    required List<String> args,
    required String workingDirectory,
    required String runAsUser,
    String? altCronPath,
  }) {
    final entry = renderBootEntry(
      pathToExecutable: pathToExecutable,
      args: args,
      workingDirectory: workingDirectory,
      runAsUser: runAsUser,
    );
    final name = basenameWithoutExtension(pathToExecutable);
    if (altCronPath == null && !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
      throw ArgumentError('Invalid cron filename');
    }
    final destination = altCronPath ?? join('/etc/cron.d', name);
    stageFile(
      destination,
      (path) => File(path).writeAsStringSync(entry),
      permission: '644',
    );
    logger.info('Installed boot launcher at $destination');
  }
}
