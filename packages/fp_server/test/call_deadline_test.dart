import 'package:fp_server/fp_server.dart';
import 'package:test/test.dart';

void main() {
  test('a call that waits gets its wait plus 5 s', () {
    const base = Duration(seconds: 15);
    expect(FlutterPilotServer.allowingWait(base, {}), base);
    expect(FlutterPilotServer.allowingWait(base, {'timeoutMs': '3000'}), base);
    expect(
      FlutterPilotServer.allowingWait(base, {'timeoutMs': 20000}),
      const Duration(seconds: 25),
    );
    expect(FlutterPilotServer.allowingWait(base, {'timeoutMs': 'x'}), base);
  });
}
