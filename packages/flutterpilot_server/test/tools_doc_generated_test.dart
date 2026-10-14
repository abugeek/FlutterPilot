import 'dart:io';

import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The generator is imported so the test checks the real thing, not a copy.
import '../tool/generate_tools_doc.dart';

/// `TOOLS.generated.md`, in the repository root, is the agent-facing tool
/// reference, generated from the registered tools. `main` shipped a stale one
/// for days (missing `launch_app(waitSeconds)`), so this fails when the
/// committed file is not what the registration renders.
///
/// The rendering is a function of a `tools/list` result, so no server process
/// is needed: `FlutterPilotServer.toolListJson()` is the same list the
/// generator's `tools/list` returns (it runs with
/// `FLUTTERPILOT_LIST_ALL_TOOLS`, which is every registered tool, the order
/// included).
void main() {
  final packageRoot = Directory.current;
  final repoRoot = packageRoot.parent.parent;
  final file = File(p.join(repoRoot.path, 'TOOLS.generated.md'));

  String normalized(String text) => text.replaceAll('\r\n', '\n');

  test('TOOLS.generated.md is what the registered tools render', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    expect(file.existsSync(), isTrue);
    expect(
      normalized(file.readAsStringSync()),
      normalized(renderToolsDoc(server.toolListJson())),
      reason:
          'Run from the repository root: dart run '
          'packages/flutterpilot_server/tool/generate_tools_doc.dart',
    );
  });

  test('the committed doc has one section per tool, in registration order', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    final names = [for (final tool in server.toolListJson()) tool['name']];
    final sections = RegExp(r'^## `([^`]+)`$', multiLine: true)
        .allMatches(file.readAsStringSync())
        .map((match) => match.group(1))
        .toList();
    expect(sections, names);
  });
}
