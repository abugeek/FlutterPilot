import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/plugin_tools.dart';
import 'package:flutterpilot_server/src/tool_profiles.dart';
import 'package:flutterpilot_server/src/zero_code.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// `--tools core` (task 08): a client that counts tools across every server
/// it runs asks for the short set. It is a subset request, never an addition:
/// a tool still has to work for the connected app.
void main() {
  FlutterPilotServer server({ToolProfile profile = ToolProfile.all}) =>
      FlutterPilotServer(
        vmServiceUri: 'ws://localhost:8888',
        staticTools: true,
        toolProfile: profile,
      );

  group('ToolProfile', () {
    test('every core name is a registered tool', () {
      final all = server();
      for (final name in coreTools) {
        expect(all.registeredToolNames, contains(name), reason: name);
      }
    });

    test('the core set stays small enough for a client tool limit', () {
      // Cursor has historically counted ~40 across every server it runs; the
      // Dart MCP server adds a handful of code tools beside FlutterPilot.
      expect(coreTools.length, lessThanOrEqualTo(30));
    });

    test('all is the default and lists more than core', () {
      expect(server().toolProfile, ToolProfile.all);
      expect(
        server().listedToolNames.length,
        greaterThan(server(profile: ToolProfile.core).listedToolNames.length),
      );
    });

    test('--static-tools --tools core lists exactly the core set', () {
      expect(
        server(profile: ToolProfile.core).listedToolNames.toSet(),
        coreTools,
      );
    });

    test('core is intersected with what works, never added to it', () {
      // A zero-code app: the core tools that answer without the SDK.
      final noSdk = FlutterPilotServer(
        vmServiceUri: 'ws://localhost:8888',
        toolProfile: ToolProfile.core,
      )..updateToolVisibility(hasSdk: false);
      expect(
        noSdk.listedToolNames.toSet(),
        coreTools.intersection(zeroCodeTools),
      );
      expect(noSdk.listedToolNames, isNotEmpty);
      expect(noSdk.listedToolNames.toSet(), isNot(coreTools));

      // An app with the SDK and no plugin: plugin-gated core tools stay out.
      final sdk = FlutterPilotServer(
        vmServiceUri: 'ws://localhost:8888',
        toolProfile: ToolProfile.core,
      )..updateToolVisibility(hasSdk: true);
      expect(sdk.listedToolNames.toSet(), {
        for (final name in coreTools)
          if (pluginToolExtensions[name] == null) name,
      });
      expect(sdk.listedToolNames, isNotEmpty);
    });

    test('a step naming a tool the profile hides is refused', () {
      final core = server(profile: ToolProfile.core);
      expect(core.stepProfileRefusal('tap_widget'), isNull);
      // The merged gesture tool is deliberately not in the short set.
      expect(
        core.stepProfileRefusal('gesture_widget'),
        contains('not listed in the core profile'),
      );
      expect(
        core.stepProfileRefusal('gesture_widget'),
        contains('--tools all'),
      );
      // Under `all` the same step is allowed.
      expect(server().stepProfileRefusal('gesture_widget'), isNull);
    });

    test(
      'a retired step name is translated before the profile sees it',
      () async {
        // Task 09 B: translate the retired name, then check the profile. A step
        // that still says swipe_widget runs as gesture_widget, so under
        // --tools core the refusal names gesture_widget, the tool it became.
        final result = await server(profile: ToolProfile.core).callToolForTest(
          'execute_action_chain',
          const {
            'steps': [
              {
                'tool': 'swipe_widget',
                'arguments': {'key': 'todo_1', 'direction': 'down'},
              },
            ],
          },
        );
        expect(result.isError, isTrue);
        expect(_textOf(result), contains('not listed in the core profile'));
        expect(_textOf(result), contains('gesture_widget'));
        expect(_textOf(result), isNot(contains('swipe_widget')));
      },
    );

    test('an unknown profile name is rejected', () {
      expect(ToolProfile.byName('all'), ToolProfile.all);
      expect(ToolProfile.byName('core'), ToolProfile.core);
      expect(() => ToolProfile.byName('short'), throwsStateError);
    });
  });
}

/// The text of a tool result.
String _textOf(CallToolResult result) => result.content
    .whereType<TextContent>()
    .map((content) => content.text)
    .join('\n');
