import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilotServer Tool Registration', () {
    test('registers all tools without crashing', () {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      
      // We can't easily inspect the private 'tools' map in McpServer,
      // but we can verify the server instance was created and tools 
      // were registered during construction.
      expect(server.server, isNotNull);
    });
  });
}
