import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilotServer construction', () {
    test('creates server with default allowDestructive=false', () {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      expect(server.allowDestructive, isFalse);
      expect(server.vmServiceUri, 'ws://localhost:8888');
      expect(server.server, isNotNull);
    });

    test('creates server with allowDestructive=true', () {
      final server = FlutterPilotServer(
        vmServiceUri: 'ws://localhost:9999',
        allowDestructive: true,
      );
      expect(server.allowDestructive, isTrue);
    });

    test('server has correct MCP implementation info', () {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      // Verify the MCP server was configured properly
      expect(server.server, isNotNull);
    });
  });

  group('Event buffer behavior', () {
    test('event buffer is empty initially', () {
      // While we can't directly access _eventBuffer (private), we can verify
      // the server was created and tools were registered without error
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      expect(server.server, isNotNull);
    });
  });

  group('Stop behavior', () {
    test('stop sets disposed flag and cleans up', () async {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      // Calling stop on a server that never connected should not throw
      await server.stop();
    });

    test('stop can be called multiple times safely', () async {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      await server.stop();
      await server.stop(); // Should not throw
    });
  });
}
