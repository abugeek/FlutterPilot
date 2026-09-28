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

    // Agents pick tools from descriptions (ROADMAP §4.3): say what the tool
    // returns and when to use it, without shouting or selling.
    test('descriptions state what a tool does, briefly', () {
      final selling = RegExp(
        r'CALL THIS|PREREQUISITES|Superpower|360-degree|<\s*\d+\s*ms|'
        r'native speed|autonomous|token-efficient|blazing|seamless|'
        r'\d+% (fewer|less|token)|Macro|[🚀⚡🎉🎯✅❌]',
        caseSensitive: false,
      );
      for (final MapEntry(key: name, value: text)
          in server.toolDescriptions.entries) {
        expect(text, isNotEmpty, reason: name);
        expect(text.length, lessThanOrEqualTo(600), reason: name);
        expect(selling.hasMatch(text), isFalse, reason: '$name: $text');
      }
    });

    test('server handles multiple instances cleanly', () {
      final s2 = FlutterPilotServer(vmServiceUri: 'ws://localhost:8889');
      expect(s2.server, isNotNull);
    });
  });
}
