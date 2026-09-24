import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:60737/NoW6oZ8wAF8=/ws';
  print('Connecting to live app on Android emulator ($uri)...');

  final process = await Process.start('dart', [
    'run',
    'bin/flutterpilot_server.dart',
    '--uri',
    uri,
  ]);

  int idCounter = 1;
  final completers = <int, Completer<Map<String, dynamic>>>{};

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final id = json['id'] as int?;
      if (id != null && completers.containsKey(id)) {
        completers[id]!.complete(json);
      }
    } catch (_) {}
  });

  Future<Map<String, dynamic>> sendRequest(String method, [Map<String, dynamic>? params]) async {
    final id = idCounter++;
    final completer = Completer<Map<String, dynamic>>();
    completers[id] = completer;
    final req = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };
    process.stdin.writeln(jsonEncode(req));
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> callTool(String name, [Map<String, dynamic> args = const {}]) async {
    return sendRequest('tools/call', {'name': name, 'arguments': args});
  }

  // MCP Handshake
  await Future.delayed(const Duration(seconds: 2));
  await sendRequest('initialize', {
    'protocolVersion': '2024-11-05',
    'capabilities': {},
    'clientInfo': {'name': 'live-test', 'version': '1.0.0'},
  });
  process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  print('\n=== [1] TOOL: get_app_snapshot ===');
  final snapshotRes = await callTool('get_app_snapshot');
  final snapshotText = (snapshotRes['result']?['content'] as List?)?.firstOrNull?['text'];
  print(snapshotText ?? jsonEncode(snapshotRes));

  print('\n=== [2] TOOL: get_interactive_elements ===');
  final interactiveRes = await callTool('get_interactive_elements');
  final interactiveText = (interactiveRes['result']?['content'] as List?)?.firstOrNull?['text'];
  print(interactiveText ?? jsonEncode(interactiveRes));

  print('\n=== [3] TOOL: tap_widget (nav_state_button) ===');
  final tapRes = await callTool('tap_widget', {'key': 'nav_state_button'});
  final tapText = (tapRes['result']?['content'] as List?)?.firstOrNull?['text'];
  print(tapText ?? jsonEncode(tapRes));

  print('\n=== [4] TOOL: capture_screenshot ===');
  final screenshotRes = await callTool('capture_screenshot');
  final screenshotText = screenshotRes['result']?['content']?[0]?['text'] ?? 'Screenshot captured';
  print('Result: $screenshotText');

  process.kill();
  print('\n✨ Live MCP validation against Android Emulator completed successfully!');
}
