import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:test/test.dart';

void main() {
  test('run_on_devices is listed once a second device is registered', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    server.fleet.registerDevice('default', 'ws://127.0.0.1:8001/a=/ws');
    server.updateToolVisibility(hasSdk: true);
    expect(server.listedToolNames, isNot(contains('run_on_devices')));

    server.fleet.registerDevice('iphone', 'ws://127.0.0.1:8002/b=/ws');
    server.updateToolVisibility(hasSdk: true);
    expect(server.listedToolNames, contains('run_on_devices'));
  });

  // For clients that don't refresh the list after tools/list_changed.
  test('--static-tools lists every tool and keeps the list', () {
    final server = FlutterPilotServer(
      vmServiceUri: 'ws://localhost:8888',
      staticTools: true,
    );
    final all = server.listedToolNames.toSet();
    expect(all, containsAll(['run_on_devices', 'native_tap', 'get_state']));
    server.updateToolVisibility(hasSdk: false, isWeb: true);
    expect(server.listedToolNames.toSet(), all);
  });
}
