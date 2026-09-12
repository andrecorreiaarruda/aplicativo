import 'dart:async';

/// Serializes short local operations. Never hold this lock during network I/O.
class AsyncMutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        done.complete();
      }
    })();
  }
}
