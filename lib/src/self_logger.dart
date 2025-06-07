/// Create a class that implements [SelfLogger]
/// to allow the installer and launcher to log to your existing
/// log system.
/// Implement each method passing the details to your existing logger.
abstract interface class SelfLogger {
  void fine(Object? message, {Object? error, StackTrace? stackTrace});
  void info(Object? message, {Object? error, StackTrace? stackTrace});
  void warning(Object? message, {Object? error, StackTrace? stackTrace});
  void severe(Object? message, {Object? error, StackTrace? stackTrace});
}
