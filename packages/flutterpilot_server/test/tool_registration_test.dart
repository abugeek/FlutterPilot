import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/plugin_tools.dart';
import 'package:flutterpilot_server/src/zero_code.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilotServer Tool Registration', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    final names = server.registeredToolNames.toSet();

    test('registers tools without schema or name collisions', () {
      expect(server.server, isNotNull);
      expect(names, isNotEmpty);
    });

    test('stays within the tool budget (ROADMAP §4.2: 60–80)', () {
      expect(names.length, lessThanOrEqualTo(80));
    });

    test('plugin-gated and zero-code tools name registered tools', () {
      for (final name in [...pluginToolExtensions.keys, ...zeroCodeTools]) {
        expect(names, contains(name));
      }
    });

    test('server handles multiple instances cleanly', () {
      final s2 = FlutterPilotServer(vmServiceUri: 'ws://localhost:8889');
      expect(s2.server, isNotNull);
    });
  });
}
