import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/device_runtime_context.dart';
import 'package:flutterpilot_server/src/web_limits.dart';
import 'package:flutterpilot_server/src/zero_code.dart';
import 'package:test/test.dart';

void main() {
  test('a web app is not offered tools the browser VM lacks', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    server.updateToolVisibility(hasSdk: true);
    final native = server.listedToolNames.toSet();
    expect(native, containsAll(webUnsupportedTools));

    server.updateToolVisibility(hasSdk: true, isWeb: true);
    expect(
      native.difference(server.listedToolNames.toSet()),
      webUnsupportedTools,
    );

    // Zero-code web apps too.
    server.updateToolVisibility(hasSdk: false, isWeb: true);
    expect(
      server.listedToolNames.toSet(),
      zeroCodeTools.difference(webUnsupportedTools),
    );
  });

  test('a web app is told apart by its VM', () {
    final c = DeviceRuntimeContext(deviceId: 'd', uri: 'ws://x/ws');
    expect(c.isWeb, isFalse);
    c.targetCPU = 'Web';
    expect(c.isWeb, isTrue);
    expect(
      notOnWeb('profile_action', 'browsers have no CPU samples'),
      startsWith('profile_action is not available for web apps'),
    );
  });
}
