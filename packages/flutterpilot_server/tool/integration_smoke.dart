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

  final vmServiceUri = _normalizeVmServiceUri(args.single);
  final process = await Process.start('dart', [
    'run',
    'packages/flutterpilot_server/bin/flutterpilot_server.dart',
    '--uri',
    vmServiceUri,
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

  Future<String> submitAsync(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final response = await call('tools/call', {
      'name': name,
      'arguments': {...arguments, 'async': true},
    });
    final content = (response['result'] as Map?)?['content'];
    final first = content is List && content.isNotEmpty ? content.first : null;
    final text = first is Map ? first['text']?.toString() ?? '' : '';
    final match = RegExp(r'op-[0-9]+').firstMatch(text);
    if (match == null) {
      throw StateError('No operation ID returned by $name: $text');
    }
    return match.group(0)!;
  }

  Future<void> waitForOperation(String operationId) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final response = await call('tools/call', {
        'name': 'get_operation',
        'arguments': {'operationId': operationId},
      });
      final content = (response['result'] as Map?)?['content'];
      final first = content is List && content.isNotEmpty
          ? content.first
          : null;
      final text = first is Map ? first['text']?.toString() ?? '' : '';
      if (!text.contains('"status":"pending"')) {
        if ((response['result'] as Map?)?['isError'] == true) {
          throw StateError('Async operation failed: $text');
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Timed out waiting for operation $operationId');
  }

  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    await assertTool('get_capabilities', const {});
    await assertTool('get_screen_hash', const {});
    final operationId = await submitAsync('get_app_summary', const {});
    await waitForOperation(operationId);
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

String _normalizeVmServiceUri(String rawUri) {
  final uri = Uri.tryParse(rawUri);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return rawUri;
  }
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri
      .replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: '${path}ws')
      .toString();
}
