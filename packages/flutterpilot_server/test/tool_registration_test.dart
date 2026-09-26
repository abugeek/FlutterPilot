import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilotServer Tool Registration', () {
    test('registers all tools including new automation tools without crashing', () {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');

      // Verify the server instance was created and all tools
      // were registered without schema or runtime collision errors.
      expect(server.server, isNotNull);
    });

    test('server handles multiple instances cleanly', () {
      final s1 = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      final s2 = FlutterPilotServer(vmServiceUri: 'ws://localhost:8889');
      expect(s1.server, isNotNull);
      expect(s2.server, isNotNull);
    });
  });
}
