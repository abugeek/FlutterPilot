import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Small, deterministic VM-service integration smoke test.
///
/// Usage from the repository root:
///   dart run packages/flutterpilot_server/tool/integration_smoke.dart `<uri>`
///
/// The target Flutter app must be running in debug/profile mode with the SDK
/// initialized. The script exits non-zero on any failed MCP request.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run packages/flutterpilot_server/tool/integration_smoke.dart <vm-service-uri>',
    );
    exitCode = 64;
    return;
  }

  final process = await Process.start('dart', [
    'run',
    'packages/flutterpilot_server/bin/flutterpilot_server.dart',
    '--uri',
    args.single,
  ]);
  final responses = <int, Completer<Map<String, dynamic>>>{};
  var nextId = 0;
  final reader = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        try {
          final message = jsonDecode(line);
          if (message is! Map<String, dynamic>) return;
          final id = message['id'];
          if (id is int) responses.remove(id)?.complete(message);
        } catch (_) {
          // Startup logs and notifications are ignored; request failures are
          // reported by the matching response or timeout below.
        }
      });

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = ++nextId;
    final completer = Completer<Map<String, dynamic>>();
    responses[id] = completer;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<void> assertTool(String name, Map<String, dynamic> arguments) async {
    final response = await call('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    if (response['error'] != null || response['result'] == null) {
      throw StateError('$name failed: ${jsonEncode(response)}');
    }
    final result = response['result'];
    if (result is Map && result['isError'] == true) {
      throw StateError('$name returned an MCP error: ${jsonEncode(response)}');
    }
  }

  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    await assertTool('get_capabilities', const {});
    await assertTool('get_screen_hash', const {});
    await assertTool('get_widget_tree', const {'async': true});
    stdout.writeln('FlutterPilot integration smoke test passed.');
  } catch (error) {
    stderr.writeln('FlutterPilot integration smoke test failed: $error');
    exitCode = 1;
  } finally {
    await reader.cancel();
    process.kill();
    await process.exitCode;
  }
}
