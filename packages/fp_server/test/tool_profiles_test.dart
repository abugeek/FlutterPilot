import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/plugin_tools.dart';
import 'package:fp_server/src/tool_profiles.dart';
import 'package:fp_server/src/zero_code.dart';
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
      // Re-measured 2026-10-14 (task 12): the only documented number is VS
      // Code's 128 tools per request (code.visualstudio.com/docs/agents/run/
      // tools); Cursor's docs state no limit. 29 core + the Dart MCP server's
      // 4 + a small server's 5 = 38.
      expect(coreTools.length, lessThanOrEqualTo(30));
    });

    test('every place that names the core count names the real one', () {
      // The count is written out by hand in the help text, the server README
      // and two top-level docs, so it can go stale silently when a tool joins
      // or leaves the set. Whitespace is flattened first: the Dart strings are
      // split across lines.
      final packageRoot = Directory.current;
      final repoRoot = packageRoot.parent.parent;
      String flat(File file) =>
          file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      final named = <String, String>{
        'lib/src/cli.dart (--tools help)': flat(
          File('${packageRoot.path}/lib/src/cli.dart'),
        ),
        'packages/fp_server/README.md': flat(
          File('${packageRoot.path}/README.md'),
        ),
        'CLAUDE.md': flat(File('${repoRoot.path}/CLAUDE.md')),
      };
      // isTrue rather than contains: a failure then prints the reason only,
      // not the whole flattened file.
      for (final entry in named.entries) {
        expect(
          entry.value.contains('a short set (${coreTools.length} names)'),
          isTrue,
          reason: '${entry.key} does not name ${coreTools.length} tools',
        );
      }
      // The CLI hint says it in the other order ("lists 29 for the app").
      final hint = flat(
        File(
          '${repoRoot.path}/packages/flutterpilot_cli/lib/src/commands/'
          'mcp_command.dart',
        ),
      );
      expect(
        hint.contains('lists ${coreTools.length} for the app'),
        isTrue,
        reason:
            'the Cursor hint in mcp install does not name '
            '${coreTools.length}',
      );
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
