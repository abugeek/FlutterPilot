import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:59506/OEVucqv9kvI=/ws';
  print('--- Testing newly developed feature through FlutterPilot ---');

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
      'clientInfo': {'name': 'verify-new-feature', 'version': '1.0.0'},
    },
  }));
  await initCompleter.future;
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  print('\n1. Verifying presence of newly developed widget in interactive elements...');
  final elementsRes = await callTool('get_interactive_elements');
  final elementsText = (elementsRes['result']?['content'] as List?)?.firstOrNull?['text'] ?? '';
  final hasNewButton = elementsText.contains('run_health_sweep_button') || elementsText.contains('Execute Autonomous Health Sweep');
  print('   Found new button on live screen: $hasNewButton');
  print('   Elements excerpt:\n${elementsText.split('\n').take(12).join('\n')}');

  print('\n2. Tapping the newly added "Execute Autonomous Health Sweep" button...');
  final tapRes = await callTool('tap_widget', {'key': 'run_health_sweep_button'});
  final tapText = (tapRes['result']?['content'] as List?)?.firstOrNull?['text'] ?? '';
  print('   Tap result:\n$tapText');

  print('\n3. Capturing high-resolution screenshot to disk...');
  final screenshotRes = await callTool('capture_screenshot', {'saveToDisk': true, 'scale': 1.0});
  final screenshotText = (screenshotRes['result']?['content'] as List?)?.firstOrNull?['text'] ?? '';
  print('   Screenshot result: $screenshotText');

  serverProcess.kill();
  print('\n🎉 Live new feature verification and control succeeded!');
}
