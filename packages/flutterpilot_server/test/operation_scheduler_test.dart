import 'dart:async';

import 'package:flutterpilot_server/src/operation_scheduler.dart';
import 'package:test/test.dart';

void main() {
  test('serializes mutations in FIFO order', () async {
    final scheduler = OperationScheduler();
    final events = <String>[];
    final first = Completer<void>();

    final a = scheduler.schedule<void>(
      mutating: true,
      operation: () async {
        events.add('a:start');
        await first.future;
        events.add('a:end');
      },
    );
    final b = scheduler.schedule<void>(
      mutating: true,
      operation: () async => events.add('b'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, ['a:start']);
    first.complete();
    await Future.wait([a, b]);
    expect(events, ['a:start', 'a:end', 'b']);
  });

  test('reads submitted before a mutation can run concurrently', () async {
    final scheduler = OperationScheduler();
    final first = Completer<void>();
    var activeReads = 0;
    var maxActiveReads = 0;

    Future<void> read() => scheduler.schedule<void>(
      mutating: false,
      operation: () async {
        activeReads++;
        maxActiveReads = activeReads > maxActiveReads
            ? activeReads
            : maxActiveReads;
        await first.future;
        activeReads--;
      },
    );

    final a = read();
    final b = read();
    await Future<void>.delayed(Duration.zero);
    expect(maxActiveReads, 2);
    first.complete();
    await Future.wait([a, b]);
  });

  test('a queued mutation creates a barrier for later reads', () async {
    final scheduler = OperationScheduler();
    final mutationStarted = Completer<void>();
    final releaseMutation = Completer<void>();
    var readRan = false;

    final mutation = scheduler.schedule<void>(
      mutating: true,
      operation: () async {
        mutationStarted.complete();
        await releaseMutation.future;
      },
    );
    await mutationStarted.future;
    final read = scheduler.schedule<void>(
      mutating: false,
      operation: () async => readRan = true,
    );

    await Future<void>.delayed(Duration.zero);
    expect(readRan, isFalse);
    releaseMutation.complete();
    await Future.wait([mutation, read]);
    expect(readRan, isTrue);
  });
}
