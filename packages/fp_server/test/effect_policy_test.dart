import 'dart:io';

import 'package:fp_server/src/effect_policy.dart';
import 'package:test/test.dart';

void main() {
  group('extension policy', () {
    test('a pure observation is replay-safe and non-mutating', () {
      final policy = extensionPolicyOf('ext.flutterpilot.getErrors', const {});
      expect(policy.mutating, isFalse);
      expect(policy.replaySafe, isTrue);
      expect(policy.known, isTrue);
    });

    test('an action is mutating and never replay-safe', () {
      final policy = extensionPolicyOf('ext.flutterpilot.tapWidget', const {});
      expect(policy.mutating, isTrue);
      expect(policy.replaySafe, isFalse);
      expect(policy.known, isTrue);
    });

    test('an unknown extension is mutating and never replayed', () {
      final policy = extensionPolicyOf(
        'ext.flutterpilot.someFuturePluginAction',
        const {},
      );
      expect(policy.mutating, isTrue);
      expect(policy.replaySafe, isFalse);
      expect(policy.known, isFalse);
    });

    test(
      'a diagnostic clear is not replay-safe even without an app change',
      () {
        for (final extension in [
          'ext.flutterpilot.clearDebugLogs',
          'ext.dart.io.clearHttpProfile',
        ]) {
          final policy = extensionPolicyOf(extension, const {});
          expect(policy.replaySafe, isFalse, reason: extension);
          expect(policy.mutating, isTrue, reason: extension);
        }
      },
    );

    test(
      'get_state is a read, but clearing the history is not replay-safe',
      () {
        final history = extensionPolicyOf(
          'ext.flutterpilot.getStateHistory',
          const {'clear': 'true'},
        );
        expect(history.replaySafe, isFalse);
        expect(history.mutating, isTrue);

        final read = extensionPolicyOf(
          'ext.flutterpilot.getStateHistory',
          const {},
        );
        expect(read.replaySafe, isTrue);
        expect(read.mutating, isFalse);

        // The boolean form an in-app caller may use is recognised too.
        final historyBool = extensionPolicyOf(
          'ext.flutterpilot.getStateHistory',
          const {'clear': true},
        );
        expect(historyBool.replaySafe, isFalse);
      },
    );
  });

  group('runWithReplay', () {
    test('a replay-safe read is sent again after a lost response', () async {
      var calls = 0;
      var reconnects = 0;
      final outcome = await runWithReplay<int>(
        policy: extensionPolicyOf('ext.flutterpilot.getErrors', const {}),
        callOnce: () async => ++calls,
        lostResponse: (result) => result == 1,
        reconnect: () async => reconnects++,
      );
      expect(calls, 2);
      expect(reconnects, 1);
      expect(outcome.replayed, isTrue);
      expect(outcome.uncertain, isFalse);
      expect(outcome.result, 2);
    });

    test('an action executes exactly once and reports uncertainty', () async {
      var calls = 0;
      var reconnects = 0;
      final outcome = await runWithReplay<int>(
        policy: extensionPolicyOf('ext.flutterpilot.tapWidget', const {}),
        callOnce: () async => ++calls,
        lostResponse: (result) => result == 1,
        reconnect: () async => reconnects++,
      );
      expect(calls, 1, reason: 'an action must never be duplicated');
      expect(reconnects, 1, reason: 'the connection is still re-established');
      expect(outcome.replayed, isFalse);
      expect(outcome.uncertain, isTrue);
    });

    test('an unknown extension executes at most once', () async {
      var calls = 0;
      final outcome = await runWithReplay<int>(
        policy: extensionPolicyOf('ext.flutterpilot.unknownThing', const {}),
        callOnce: () async => ++calls,
        lostResponse: (result) => true,
        reconnect: () async {},
      );
      expect(calls, 1);
      expect(outcome.uncertain, isTrue);
    });

    test('a diagnostic clear is never replayed', () async {
      var calls = 0;
      await runWithReplay<int>(
        policy: extensionPolicyOf('ext.flutterpilot.getStateHistory', const {
          'clear': 'true',
        }),
        callOnce: () async => ++calls,
        lostResponse: (result) => true,
        reconnect: () async {},
      );
      expect(calls, 1);
    });

    test('a response that is not lost is returned as is', () async {
      var calls = 0;
      var reconnects = 0;
      final outcome = await runWithReplay<int>(
        policy: extensionPolicyOf('ext.flutterpilot.getErrors', const {}),
        callOnce: () async => ++calls,
        lostResponse: (result) => false,
        reconnect: () async => reconnects++,
      );
      expect(calls, 1);
      expect(reconnects, 0);
      expect(outcome.replayed, isFalse);
      expect(outcome.uncertain, isFalse);
    });

    test(
      'a replay-safe read is not replayed when reconnection failed',
      () async {
        var calls = 0;
        final outcome = await runWithReplay<int>(
          policy: extensionPolicyOf('ext.flutterpilot.getErrors', const {}),
          callOnce: () async => ++calls,
          lostResponse: (result) => true,
          reconnect: () async {},
          canReplay: () => false,
        );
        expect(calls, 1);
        expect(outcome.uncertain, isTrue);
      },
    );
  });

  group('coverage', () {
    test('every extension the server names is in the reviewed inventory', () {
      // A new extension must be classified here (or the default applies: never
      // replayed). This scan is deliberately the same source-literal scan the
      // other registration tests use; it names the file and extension that is
      // missing instead of silently defaulting.
      final classified = {
        ...readOnlyExtensions,
        ...mutatingExtensions,
        ...diagnosticClearExtensions,
      };
      // Names that are stream event kinds, not service extensions.
      const notExtensions = {
        'ext.flutterpilot.error',
        'ext.flutterpilot.lifecycle',
      };
      final found = <String, String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in RegExp(
          r"'(ext\.[a-z]+(?:\.[A-Za-z0-9]+)+)'",
        ).allMatches(source)) {
          found.putIfAbsent(match.group(1)!, () => entity.path);
        }
      }
      final unclassified = {
        for (final entry in found.entries)
          if (!classified.contains(entry.key) &&
              !notExtensions.contains(entry.key))
            entry.key: entry.value,
      };
      expect(
        unclassified,
        isEmpty,
        reason:
            'These extensions are used by the server but not classified in '
            'effect_policy.dart: $unclassified',
      );
      expect(classified, isNotEmpty);
    });
  });
}
