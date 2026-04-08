import 'package:flutterpilot_server/src/self_heal_manager.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockMcpServer extends Mock implements McpServer {}

void main() {
  late MockMcpServer mockServer;
  late SelfHealManager manager;

  setUp(() {
    mockServer = MockMcpServer();
    manager = SelfHealManager(server: mockServer);
  });

  group('SelfHealManager', () {
    test('transitions to unstable on crash and gathers data', () async {
      expect(manager.isUnstable, isFalse);

      final extensionResults = {
        'ext.flutterpilot.getErrors': {'errors': []},
        'ext.flutterpilot.getRiverpodStates': {'states': {}},
        'ext.flutterpilot.getBlocStates': {'states': {}},
        'ext.flutterpilot.getNetworkLogs': {'logs': []},
        'ext.flutterpilot.getNavigationStack': {'stack': []},
        'ext.flutterpilot.getWidgetTree': {'tree': {}},
      };

      await manager.handleCrash(
        exception: 'TestException',
        callExtension: (ext) async => extensionResults[ext],
      );

      expect(manager.isUnstable, isTrue);
      expect(manager.lastCrashReport, isNotNull);
      expect(manager.lastCrashReport!.exception, 'TestException');

      // Verify alert was "sent" (though we commented out the actual call in the implementation for safety)
      // If we uncomment it later, we can verify it here.
    });

    test('resets to stable', () {
      manager.isUnstable = true;
      manager.reset();
      expect(manager.isUnstable, isFalse);
    });
  });
}
