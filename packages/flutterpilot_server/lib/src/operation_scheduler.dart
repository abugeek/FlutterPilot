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
  }) {
    if (!mutating) {
      return _mutationTail.then((_) => operation());
    }

    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
