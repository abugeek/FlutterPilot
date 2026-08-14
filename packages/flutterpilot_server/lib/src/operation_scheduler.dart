import 'dart:async';

/// Coordinates operations sent to one running Flutter application.
///
/// Read operations may run concurrently when the device is idle. Mutating
/// operations form a FIFO chain and create a barrier for reads submitted after
/// them, preventing an observation from racing a UI/state mutation.
class OperationScheduler {
  Future<void> _mutationTail = Future<void>.value();

  Future<T> schedule<T>({
    required bool mutating,
    required Future<T> Function() operation,
  }) => scheduleCancellable<T>(mutating: mutating, operation: operation).future;

  ScheduledOperation<T> scheduleCancellable<T>({
    required bool mutating,
    required Future<T> Function() operation,
  }) {
    final completer = Completer<T>();
    var cancelled = false;
    var started = false;

    Future<T> run() async {
      if (cancelled) throw const OperationCancelledException();
      started = true;
      return operation();
    }

    final result = _mutationTail.then((_) => run());
    if (mutating) {
      _mutationTail = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
    }

    result.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );

    return ScheduledOperation<T>._(completer.future, () {
      if (started || cancelled) return false;
      cancelled = true;
      if (!completer.isCompleted) {
        completer.completeError(const OperationCancelledException());
      }
      return true;
    });
  }
}

/// A queued operation that can be cancelled before it starts running.
class ScheduledOperation<T> {
  final Future<T> future;
  final bool Function() _cancelCallback;

  ScheduledOperation._(this.future, this._cancelCallback);

  /// Returns false when the operation has already started or finished.
  bool cancel() => _cancelCallback();
}

class OperationCancelledException implements Exception {
  const OperationCancelledException();

  @override
  String toString() => 'Operation was cancelled before it started';
}
