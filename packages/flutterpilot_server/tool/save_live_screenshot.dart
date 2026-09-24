import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = 'ws://127.0.0.1:59506/OEVucqv9kvI=/ws';
  final outPath = r'C:\Users\abdul\.gemini\antigravity-cli\brain\e88bf794-a1d4-495e-a7dc-6d81b75ccd47\live_emulator_screenshot.png';

  final serverProcess = await Process.start('dart', [
    'run',
    'bin/flutterpilot_server.dart',
    '--uri',
    uri,
  ]);

  int idCounter = 1;
  final completers = <int, Completer<Map<String, dynamic>>>{};

  serverProcess.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final id = json['id'] as int?;
      if (id != null && completers.containsKey(id)) {
        completers[id]!.complete(json);
      }
    } catch (_) {}
  });

  Future<Map<String, dynamic>> callTool(String name, [Map<String, dynamic> args = const {}]) async {
    final id = idCounter++;
    final completer = Completer<Map<String, dynamic>>();
    completers[id] = completer;
    serverProcess.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    }));
    return completer.future.timeout(const Duration(seconds: 15));
  }

  // Handshake
  await Future.delayed(const Duration(seconds: 2));
  final initId = idCounter++;
  final initCompleter = Completer<Map<String, dynamic>>();
  completers[initId] = initCompleter;
  serverProcess.stdin.writeln(jsonEncode({
    'jsonrpc': '2.0',
    'id': initId,
    'method': 'initialize',
    'params': {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'save-screenshot', 'version': '1.0.0'},
    },
  }));
  await initCompleter.future;
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  final res = await callTool('capture_screenshot', {'scale': 1.0});
  final contents = res['result']?['content'] as List?;
  if (contents != null) {
    for (final c in contents) {
      if (c['type'] == 'image' && c['data'] != null) {
        final bytes = base64Decode(c['data'] as String);
        File(outPath).writeAsBytesSync(bytes);
        print('✅ Saved live screenshot (${bytes.length} bytes) to $outPath');
        break;
      }
    }
  }

  serverProcess.kill();
}
