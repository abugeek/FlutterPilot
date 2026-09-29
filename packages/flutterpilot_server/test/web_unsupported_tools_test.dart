import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/device_runtime_context.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Web unsupported tools', () {
    late FlutterPilotServer server;
    late DeviceRuntimeContext webContext;

    setUp(() {
      server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      webContext =
          DeviceRuntimeContext(
              deviceId: 'default',
              uri: 'ws://localhost:8888/ws',
            )
            ..operatingSystem = 'web'
            ..targetCPU = 'Web';
      server.setDeviceContextForTesting(webContext);
    });

    test('profile_action reports not available on web', () async {
      final res = await server.callToolForTesting('profile_action', {
        'tool': 'tap_widget',
        'arguments': {'key': 'btn'},
      });
      expect(res.isError, isTrue);
      final text = res.content
          .whereType<TextContent>()
          .map((c) => c.text)
          .join(' ');
      expect(text, contains('profile_action is not available on web'));
    });

    test(
      'get_memory_details leak check reports not available on web',
      () async {
        final res = await server.callToolForTesting('get_memory_details', {
          'times': 3,
          'cycle': [
            {
              'tool': 'tap_widget',
              'arguments': {'key': 'btn'},
            },
          ],
        });
        expect(res.isError, isTrue);
        final text = res.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join(' ');
        expect(text, contains('not available on web'));
      },
    );

    test(
      'get_memory_details with classes reports not available on web',
      () async {
        final res = await server.callToolForTesting('get_memory_details', {
          'classes': true,
        });
        expect(res.isError, isTrue);
        final text = res.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join(' ');
        expect(text, contains('not available on web'));
      },
    );

    test('get_http_profile reports not available on web', () async {
      final res = await server.callToolForTesting('get_http_profile', {});
      expect(res.isError, isTrue);
      final text = res.content
          .whereType<TextContent>()
          .map((c) => c.text)
          .join(' ');
      expect(text, contains('not available on web'));
    });
  });
}
