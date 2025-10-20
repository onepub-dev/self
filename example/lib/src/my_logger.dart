import 'dart:io';

import 'package:date_time_format/date_time_format.dart';
import 'package:dcli/dcli.dart';
import 'package:logging/logging.dart';
import 'package:self/src/self_logger.dart';

/// Example logger that logs uses the logging package from pub.dev
class MyLogger implements SelfLogger {
  final Logger _logger;

  late final IOSink _sink;

  MyLogger._(String logFilePath, {required bool debug})
    : _logger = Logger('MyLogger') {
    _configureLogging(logFilePath, debug: debug);
  }

  @override
  void fine(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _logger.fine(message, error, stackTrace);

  @override
  void info(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _logger.info(message, error, stackTrace);

  @override
  void warning(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _logger.warning(message, error, stackTrace);

  @override
  void severe(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _logger.severe(message, error, stackTrace);

  /// Factory that ensures the log file (and its directory) exist, then
  /// sets up a listener on `Logger.root` to append to that file.
  static Future<MyLogger> create({
    required String logFilePath,
    required bool debug,
  }) async {
    if (!exists(logFilePath)) {
      touch(logFilePath, create: true);
    }

    return MyLogger._(logFilePath, debug: debug);
  }

  void _configureLogging(String logFilePath, {required bool debug}) {
    // Open file in append mode
    _sink = File(logFilePath).openWrite(mode: FileMode.append);

    // Set the root logger's level (adjust as needed)
    // IMFO should be the default
    if (debug) {
      Logger.root.level = Level.FINE;
    } else {
      Logger.root.level = Level.INFO;
    }

    // Listen for all log records on the root logger
    Logger.root.onRecord.listen((record) async {
      final timestamp = record.time;
      final levelName = record.level.name;
      // final name = record.loggerName;
      final message = record.message;
      final error = record.error;
      final stackTrace = record.stackTrace;

      final buffer = StringBuffer()
        ..write('${formatDate(timestamp)} [$levelName] $message');
      if (error != null) {
        buffer.write(' | ERROR: $error');
      }
      if (stackTrace != null) {
        buffer.write('\n$stackTrace');
      }

      final line = buffer.toString();
      _sink.writeln(line);
      await _sink.done;
      // Defer the flush to the next microtask, so we don't
      // call flush while the sink is still in use.
    });
  }

  /// When done, call close() to flush and close the file sink.
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}

String formatDate(DateTime dateTime) => dateTime.format('D, M j, H:i');
