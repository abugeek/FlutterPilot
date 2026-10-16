import 'package:fp_server/fp_server.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Task 02 through the real tool callbacks: every tool that runs other tools
/// validates each step — its shape, family, availability, profile, and the
/// step's own arguments — before any of them runs.
///
/// A malformed step N means **zero** executed steps. That is proven two ways
/// here, without a running app: the tool's own structured verdict (or the
/// refusal text) says no step ran, and the refusal is returned *instead of* the
/// next check the handler would otherwise reach — the device fan-out, the
/// "no running Flutter app" extension error, or the web/VM guard. If a step had
/// executed first, that later error is what would come back.
void main() {
  FlutterPilotServer server() =>
      FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');

  String textOf(CallToolResult result) => [
    for (final part in result.content)
      if (part is TextContent) part.text,
  ].join('\n');

  group('execute_action_chain', () {
    test('an invalid last step is refused before any step runs', () async {
      final result = await server().callToolForTest('execute_action_chain', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'Save'},
          },
          // enter_text needs text.
          {'tool': 'enter_text', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(result.isError, isTrue);
      final text = textOf(result);
      expect(text, contains('steps[1].arguments:'));
      expect(text, contains('text'));
      expect(text, isNot(contains('running Flutter app')));
      expect(result.structuredContent, {
        'passed': false,
        'completedSteps': 0,
        'totalSteps': 2,
        'failedStep': 2,
        'failureReason': text,
        'status': 'refused',
      });
    });

    test('a step outside the family is refused at its path', () async {
      final result = await server().callToolForTest('execute_action_chain', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'Save'},
          },
          {'tool': 'run_on_devices', 'arguments': <String, dynamic>{}},
        ],
      });
      final text = textOf(result);
      expect(text, contains('steps[1]'));
      expect(text, contains('run_on_devices'));
      expect(text, isNot(contains('running Flutter app')));
    });

    test('the step envelope enforces tool, arguments and their coercion', () {
      final s = server();
      // A step with no `tool` names the missing field.
      expect(
        s.checkArgumentsForTest('execute_action_chain', {
          'steps': [
            {'arguments': <String, dynamic>{}},
          ],
        }),
        contains('tool'),
      );
      // `arguments` must be an object, named by its path.
      expect(
        s.checkArgumentsForTest('execute_action_chain', {
          'steps': [
            {'tool': 'tap_widget', 'arguments': 5},
          ],
        }),
        contains('steps[0].arguments'),
      );
      // A stringified array is decoded (the unambiguous coercion).
      expect(
        s.checkArgumentsForTest('execute_action_chain', {
          'steps': '[{"tool": "tap_widget", "arguments": {"key": "Save"}}]',
        }),
        isNull,
      );
      // A stringified nested object is decoded too.
      expect(
        s.checkArgumentsForTest('execute_action_chain', {
          'steps': [
            {'tool': 'enter_text', 'arguments': '{"text": "Milk"}'},
          ],
        }),
        isNull,
      );
    });
  });

  group('run_on_devices', () {
    test('an invalid plan is refused before the device fan-out', () async {
      // No devices are registered, so a *valid* plan reaches the device check.
      // The invalid plan must be refused first: nothing runs on any device.
      final result = await server().callToolForTest('run_on_devices', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'A'},
          },
          {'tool': 'press_key', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(result.isError, isTrue);
      final text = textOf(result);
      expect(text, contains('steps[1].arguments:'));
      expect(text, isNot(contains('at least two registered devices')));
    });

    test('a valid plan reaches the device check', () async {
      final result = await server().callToolForTest('run_on_devices', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'A'},
          },
        ],
      });
      expect(result.isError, isTrue);
      expect(textOf(result), contains('at least two registered devices'));
    });
  });

  group('get_memory_details(cycle:)', () {
    test('an empty cycle keeps its own guidance', () async {
      final result = await server().callToolForTest('get_memory_details', {
        'cycle': const <Object?>[],
      });
      expect(result.isError, isTrue);
      final text = textOf(result);
      expect(text, contains('cycle is empty'));
      expect(text, isNot(contains('Flutter app connection')));
    });

    test('an invalid step is named as a cycle step, before the app', () async {
      final result = await server().callToolForTest('get_memory_details', {
        'cycle': [
          {'tool': 'press_key', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(result.isError, isTrue);
      final text = textOf(result);
      expect(text, startsWith('cycle[0].arguments:'));
      expect(text, isNot(contains('Flutter app connection')));
      expect(text, isNot(contains('not available for web apps')));
    });

    test('a cycle step outside the profiled family is refused', () async {
      final result = await server().callToolForTest('get_memory_details', {
        'cycle': [
          {'tool': 'get_state', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(result.isError, isTrue);
      expect(textOf(result), contains('cycle[0]: "get_state" can\'t'));
    });
  });

  group('profile_action', () {
    test(
      'a tool it cannot profile is refused before anything is sampled',
      () async {
        final result = await server().callToolForTest('profile_action', {
          'tool': 'get_state',
        });
        expect(result.isError, isTrue);
        final text = textOf(result);
        expect(text, contains('tool: "get_state" can\'t be profiled'));
        expect(text, isNot(contains('Flutter app connection')));
      },
    );

    test('the profiled tool\'s own arguments are validated first', () async {
      final result = await server().callToolForTest('profile_action', {
        'tool': 'press_key',
        'arguments': <String, dynamic>{},
      });
      expect(result.isError, isTrue);
      final text = textOf(result);
      expect(text, startsWith('tool.arguments: press_key needs'));
      expect(text, isNot(contains('Flutter app connection')));
    });

    test('a retired tool name is translated before profiling', () async {
      // swipe_widget becomes gesture_widget; a bad gesture argument then fails
      // gesture_widget's own gate, so the call is refused before the app and
      // the refusal names the translated tool.
      final result = await server().callToolForTest('profile_action', {
        'tool': 'swipe_widget',
        'arguments': {'distance': 'abc'},
      });
      expect(result.isError, isTrue);
      final text = textOf(result);
      expect(text, startsWith('tool.arguments:'));
      expect(text, contains('gesture_widget'));
      expect(text, contains('distance'));
      expect(text, isNot(contains('Flutter app connection')));
    });
  });
}
