import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/build_mode.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  Flag flag(String name, String value) =>
      Flag(name: name, comment: '', modified: false, valueAsString: value);

  test('profile builds run precompiled code', () {
    expect(
      buildModeFromFlags([
        flag('enable_asserts', 'false'),
        flag('precompiled_mode', 'true'),
      ]),
      BuildMode.profile,
    );
    expect(
      buildModeFromFlags([flag('precompiled_mode', 'false')]),
      BuildMode.debug,
    );
    expect(buildModeFromFlags(const []), BuildMode.debug);
  });

  test('a profile build is not offered hot reload or what needs it', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    server.updateToolVisibility(hasSdk: true);
    final debug = server.listedToolNames.toSet();
    expect(debug, containsAll(debugOnlyTools));

    server.updateToolVisibility(hasSdk: true, buildMode: BuildMode.profile);
    expect(debug.difference(server.listedToolNames.toSet()), debugOnlyTools);

    server.updateToolVisibility(hasSdk: true, buildMode: BuildMode.debug);
    expect(server.listedToolNames.toSet(), debug);
  });
}
