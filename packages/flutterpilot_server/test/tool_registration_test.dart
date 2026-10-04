import 'dart:convert';

import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/plugin_tools.dart';
import 'package:flutterpilot_server/src/tool_annotations.dart';
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
        expect(text.length, lessThanOrEqualTo(560), reason: name);
        expect(selling.hasMatch(text), isFalse, reason: '$name: $text');
      }
    });

    // What an agent pays for before it calls anything: the name,
    // description and schema of each listed tool (annotations go to the
    // client, not the model). Raise a budget only for a tool that earns it.
    int listBytes(bool Function(String name) listed) => server
        .toolListJson(names.where(listed))
        .map((tool) => jsonEncode(tool..remove('annotations')).length)
        .fold(0, (a, b) => a + b);

    test('the tool list stays within its size budget', () {
      // Every tool (--static-tools).
      expect(listBytes((_) => true), lessThanOrEqualTo(40000));
      // An app with the SDK and no plugin, not on an iOS simulator.
      expect(
        listBytes(
          (name) =>
              !pluginToolExtensions.containsKey(name) &&
              !name.startsWith('native_'),
        ),
        lessThanOrEqualTo(28500),
      );
      // An app without the SDK.
      expect(listBytes(zeroCodeTools.contains), lessThanOrEqualTo(8800));
    });

    test('every tool says what it does to the app', () {
      expect(toolEffects.keys.toSet(), names);
      for (final tool in server.toolListJson()) {
        final hints = tool['annotations'] as Map?;
        expect(hints, isNotNull, reason: '${tool['name']}');
        expect(
          hints!['readOnlyHint'] == true && hints['destructiveHint'] == true,
          isFalse,
          reason: '${tool['name']}',
        );
      }
      // The tools the server refuses without --allow-destructive, and the
      // one that runs code it can't see.
      expect(
        {
          for (final MapEntry(key: name, value: effect) in toolEffects.entries)
            if (effect == ToolEffect.destructive) name,
        },
        {
          'set_shared_preference',
          'set_secure_storage_key',
          'supabase_session',
          'scenario',
          'call_custom_tool',
        },
      );
    });

    test('parameters have one name each, in camelCase', () {
      for (final tool in server.toolListJson()) {
        final properties =
            (tool['inputSchema'] as Map)['properties'] as Map? ?? const {};
        for (final param in properties.keys.cast<String>()) {
          expect(param, isNot(contains('_')), reason: '${tool['name']}');
        }
        // `target` still works as an argument; the schema lists `key`.
        expect(
          properties.keys,
          isNot(containsAll(['key', 'target'])),
          reason: '${tool['name']}',
        );
      }
    });

    test('server instructions are short and name tools that exist', () {
      expect(serverInstructions.length, lessThanOrEqualTo(1200));
      final mentioned = RegExp(r'\b[a-z]+(?:_[a-z]+)+\b')
          .allMatches(serverInstructions)
          .map((m) => m[0]!)
          .where((word) => word != 'flutterpilot_sdk');
      expect(mentioned, isNotEmpty);
      for (final tool in mentioned) {
        expect(names, contains(tool));
      }
    });

    test('server handles multiple instances cleanly', () {
      final s2 = FlutterPilotServer(vmServiceUri: 'ws://localhost:8889');
      expect(s2.server, isNotNull);
    });
  });
}
