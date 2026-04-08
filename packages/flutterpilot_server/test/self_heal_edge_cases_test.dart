import 'dart:async';

import 'package:flutterpilot_server/src/self_heal_manager.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockMcpServer extends Mock implements McpServer {}

class FakeLoggingMessageNotification extends Fake
    implements LoggingMessageNotification {}

void main() {
  late MockMcpServer mockServer;
  late SelfHealManager manager;

  setUpAll(() {
    registerFallbackValue(FakeLoggingMessageNotification());
  });

  setUp(() {
    mockServer = MockMcpServer();
    manager = SelfHealManager(server: mockServer);
  });

  group('SelfHealManager edge cases', () {
    test('handles partial extension failures gracefully', () async {
      // Simulate some extensions failing and some succeeding
      await manager.handleCrash(
        exception: 'PartialFailure',
        callExtension: (ext) {
          if (ext == 'ext.flutterpilot.getErrors') {
            return Future<dynamic>.value({
              'errors': ['real error'],
            });
          }
          if (ext == 'ext.flutterpilot.getRiverpodStates') {
            return Future<dynamic>.error(Exception('Riverpod not available'));
          }
          if (ext == 'ext.flutterpilot.getWidgetTree') {
            return Future<dynamic>.error(TimeoutException('Timed out'));
          }
          return Future<dynamic>.value({'data': 'ok'});
        },
      );

      expect(manager.isUnstable, isTrue);
      expect(manager.lastCrashReport, isNotNull);
      // Failed extensions should produce 'N/A' in the report
      expect(manager.lastCrashReport!.errorData, {
        'errors': ['real error'],
      });
      expect(manager.lastCrashReport!.riverpodData, 'N/A');
      expect(manager.lastCrashReport!.widgetTreeData, 'N/A');
    });

    test('handles all extensions failing', () async {
      await manager.handleCrash(
        exception: 'TotalFailure',
        callExtension: (ext) {
          return Future<dynamic>.error(Exception('VM Service disconnected'));
        },
      );

      expect(manager.isUnstable, isTrue);
      expect(manager.lastCrashReport, isNotNull);
      expect(manager.lastCrashReport!.errorData, 'N/A');
      expect(manager.lastCrashReport!.riverpodData, 'N/A');
      expect(manager.lastCrashReport!.blocData, 'N/A');
      expect(manager.lastCrashReport!.networkData, 'N/A');
      expect(manager.lastCrashReport!.navigationData, 'N/A');
      expect(manager.lastCrashReport!.widgetTreeData, 'N/A');
    });

    test('multiple crashes overwrite lastCrashReport', () async {
      await manager.handleCrash(
        exception: 'FirstCrash',
        callExtension: (ext) => Future<dynamic>.value('N/A'),
      );
      expect(manager.lastCrashReport!.exception, 'FirstCrash');

      await manager.handleCrash(
        exception: 'SecondCrash',
        callExtension: (ext) => Future<dynamic>.value('N/A'),
      );
      expect(manager.lastCrashReport!.exception, 'SecondCrash');
    });

    test('reset does not clear lastCrashReport', () async {
      await manager.handleCrash(
        exception: 'Error',
        callExtension: (ext) => Future<dynamic>.value('N/A'),
      );

      manager.reset();

      expect(manager.isUnstable, isFalse);
      // Report is still available for review after reset
      expect(manager.lastCrashReport, isNotNull);
      expect(manager.lastCrashReport!.exception, 'Error');
    });

    test('crash report timestamp is captured at call time', () async {
      final before = DateTime.now();

      await manager.handleCrash(
        exception: 'TimedError',
        callExtension: (ext) async {
          // Simulate slow extension
          await Future.delayed(const Duration(milliseconds: 10));
          return 'data';
        },
      );

      final after = DateTime.now();
      final reportTime = DateTime.parse(manager.lastCrashReport!.timestamp);
      expect(
        reportTime.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        reportTime.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('crash report markdown includes exception text', () async {
      await manager.handleCrash(
        exception: 'RangeError: index out of range',
        callExtension: (ext) => Future<dynamic>.value('N/A'),
      );

      final md = manager.lastCrashReport!.toMarkdown();
      expect(md, contains('RangeError: index out of range'));
    });

    test('sendProactiveAlert catches notification errors', () async {
      // If sendLoggingMessage throws, handleCrash should still complete
      when(
        () => mockServer.sendLoggingMessage(any()),
      ).thenThrow(StateError('Not connected'));

      await manager.handleCrash(
        exception: 'CrashDuringNotification',
        callExtension: (ext) => Future<dynamic>.value('data'),
      );

      // Should complete without throwing
      expect(manager.isUnstable, isTrue);
      expect(manager.lastCrashReport!.exception, 'CrashDuringNotification');
    });
  });
}
