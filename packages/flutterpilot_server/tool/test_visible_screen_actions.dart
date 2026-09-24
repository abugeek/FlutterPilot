import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:60737/NoW6oZ8wAF8=/ws';
  print('===============================================================');
  print('👀 Visible Action Demonstration Script');
  print('   Look at your Android emulator right now to watch actions live!');
  print('   VM Service: $uri');
  print('===============================================================\n');

  final serverProcess = await Process.start('dart', [
    'run',
    'bin/flutterpilot_server.dart',
    '--uri',
    uri,
  ]);

  int idCounter = 1;
  final completers = <int, Completer<Map<String, dynamic>>>{};

  serverProcess.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final id = json['id'] as int?;
      if (id != null && completers.containsKey(id)) {
        completers[id]!.complete(json);
      }
    } catch (_) {}
  });

  serverProcess.stderr.transform(utf8.decoder).listen((data) {
    stderr.write(data);
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
      'clientInfo': {'name': 'visual-demo', 'version': '1.0.0'},
    },
  }));
  await initCompleter.future;
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  print('👉 [STEP 1] Tapping "State Injection" button on Dashboard...');
  final tapNav = await callTool('tap_widget', {'key': 'nav_state_button'});
  print('   Response: ${(tapNav['result']?['content'] as List?)?.firstOrNull?['text']}');
  print('   ⏳ Pausing 2 seconds so you can see the State Injection screen...\n');
  await Future.delayed(const Duration(seconds: 2));

  print('👉 [STEP 2] Incrementing Riverpod counter (+1)...');
  await callTool('tap_widget', {'key': 'riverpod_increment_button'});
  await Future.delayed(const Duration(milliseconds: 700));

  print('👉 [STEP 3] Incrementing Riverpod counter (+2)...');
  await callTool('tap_widget', {'key': 'riverpod_increment_button'});
  await Future.delayed(const Duration(milliseconds: 700));

  print('👉 [STEP 4] Incrementing Riverpod counter (+3)...');
  await callTool('tap_widget', {'key': 'riverpod_increment_button'});
  await Future.delayed(const Duration(milliseconds: 700));

  print('👉 [STEP 5] Incrementing Bloc counter (+1)...');
  await callTool('tap_widget', {'key': 'bloc_increment_button'});
  await Future.delayed(const Duration(milliseconds: 700));

  print('👉 [STEP 6] Incrementing Bloc counter (+2)...');
  await callTool('tap_widget', {'key': 'bloc_increment_button'});
  await Future.delayed(const Duration(seconds: 1));

  print('👉 [STEP 7] Tapping Back button to return to Dashboard...');
  final backRes = await callTool('go_back');
  print('   Response: ${(backRes['result']?['content'] as List?)?.firstOrNull?['text']}');
  print('   ⏳ Pausing 2 seconds on Dashboard...\n');
  await Future.delayed(const Duration(seconds: 2));

  print('👉 [STEP 8] Direct navigating to /network screen...');
  final navNetwork = await callTool('navigate_to', {'route': '/network'});
  print('   Response: ${(navNetwork['result']?['content'] as List?)?.firstOrNull?['text']}');
  print('   ⏳ Pausing 2 seconds so you can see the Network screen...\n');
  await Future.delayed(const Duration(seconds: 2));

  print('👉 [STEP 9] Direct navigating back to Dashboard (route: /)...');
  final navHome = await callTool('navigate_to', {'route': '/'});
  print('   Response: ${(navHome['result']?['content'] as List?)?.firstOrNull?['text']}\n');

  serverProcess.kill();
  print('🎉 Visual demonstration completed! Check your emulator screen.');
}
