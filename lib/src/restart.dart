/// Injected callbacks keep policy tests independent of process creation.
Future<void> restartOnFailure({
  required Future<int> Function() run,
  required Future<void> Function() delay,
  int maxRestarts = 5,
}) async {
  if (maxRestarts < 0) {
    throw ArgumentError.value(
      maxRestarts,
      'maxRestarts',
      'Must be nonnegative',
    );
  }
  for (var attempt = 0; ; attempt++) {
    final code = await run();
    if (code == 0) {
      return;
    }
    if (attempt >= maxRestarts) {
      throw StateError('Restart limit exhausted (last exit code: $code)');
    }
    await delay();
  }
}
