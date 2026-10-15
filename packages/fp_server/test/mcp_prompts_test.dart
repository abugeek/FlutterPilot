import 'package:fp_server/fp_server.dart';
import 'package:mcp_dart/mcp_dart.dart'
    show ErrorCode, GetPromptResult, McpError, PromptMessageRole, TextContent;
import 'package:test/test.dart';

/// Task 17: curated workflow prompts. `prompts/list` must advertise the guide
/// and the four workflows with titles and descriptions, and `prompts/get` must
/// return one actionable user message for each — with an error for an unknown
/// name.
void main() {
  late FlutterPilotServer server;
  setUp(() => server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888'));

  String textOf(GetPromptResult result) =>
      (result.messages.single.content as TextContent).text;

  const workflowNames = [
    'debug_layout_overflow',
    'diagnose_exception',
    'create_integration_test',
    'audit_screen_health',
  ];

  group('prompts/list', () {
    test('lists the guide and the four workflow prompts', () {
      expect(server.promptListJson().map((p) => p['name']), [
        'flutterpilot_guide',
        ...workflowNames,
      ]);
    });

    test('every prompt has a title and a description', () {
      for (final prompt in server.promptListJson()) {
        expect(prompt['title'], isA<String>(), reason: '${prompt['name']}');
        expect((prompt['title'] as String), isNotEmpty);
        expect((prompt['description'] as String), isNotEmpty);
      }
    });

    test('the workflows declare their optional argument', () {
      final byName = {for (final p in server.promptListJson()) p['name']: p};
      const expected = {
        'debug_layout_overflow': 'widgetKey',
        'diagnose_exception': 'errorIndex',
        'create_integration_test': 'name',
        'audit_screen_health': 'route',
      };
      for (final entry in expected.entries) {
        final arguments = byName[entry.key]!['arguments'] as List;
        expect(arguments, hasLength(1), reason: entry.key);
        final argument = arguments.single as Map;
        expect(argument['name'], entry.value);
        expect(argument['required'], isFalse, reason: entry.key);
        expect(argument['description'], isNotEmpty);
      }
      expect(byName['flutterpilot_guide']!['arguments'], isEmpty);
    });
  });

  group('prompts/get', () {
    test('the guide returns its full text as a user message', () {
      final result = server.getPromptForTest('flutterpilot_guide');
      expect(result.messages, hasLength(1));
      expect(result.messages.single.role, PromptMessageRole.user);
      expect(textOf(result), contains('FlutterPilot'));
    });

    test('each workflow returns actionable steps naming its tool', () {
      const primaryTool = {
        'debug_layout_overflow': 'inspect_widget',
        'diagnose_exception': 'get_errors',
        'create_integration_test': 'generate_test',
        'audit_screen_health': 'audit_screen_health',
      };
      for (final entry in primaryTool.entries) {
        final result = server.getPromptForTest(entry.key);
        expect(result.messages, hasLength(1), reason: entry.key);
        expect(result.messages.single.role, PromptMessageRole.user);
        final text = textOf(result);
        expect(text, contains('Workflow:'), reason: entry.key);
        expect(text, contains('1.'), reason: entry.key);
        expect(text, contains(entry.value), reason: entry.key);
      }
    });

    test('an optional argument is folded into the body', () {
      final result = server.getPromptForTest(
        'debug_layout_overflow',
        args: {'widgetKey': 'TotalRow'},
      );
      expect(textOf(result), contains('TotalRow'));
    });

    test('an unknown prompt is a methodNotFound error', () {
      expect(
        () => server.getPromptForTest('no_such_prompt'),
        throwsA(
          isA<McpError>()
              .having((e) => e.code, 'code', ErrorCode.methodNotFound.value)
              .having((e) => e.message, 'message', contains('not found')),
        ),
      );
    });
  });
}
