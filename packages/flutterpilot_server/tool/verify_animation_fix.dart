import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:60737/NoW6oZ8wAF8=/ws';
  print('================================================================');
  print('⚡ Step 4 & 5: Autonomous Post-Fix Verification on Android Emulator');
  print('   Target: Android Emulator (emulator-5554)');
  print('   VM Service: $uri');
  print('================================================================\n');

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
      'clientInfo': {'name': 'anim-verify', 'version': '1.0.0'},
    },
  }));
  await initCompleter.future;
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  print('🧭 Ensuring on /animation_lab route...');
  await callTool('navigate_to', {'route': '/animation_lab'});
  await Future.delayed(const Duration(milliseconds: 500));

  print('⏱️  Letting optimized animation run for 2.5 seconds to collect clean frame timings...');
  await Future.delayed(const Duration(milliseconds: 2500));

  print('📊 [POST-FIX TELEMETRY] Gathering Frame Budget Profile:');
  final profileRes = await callTool('get_frame_budget_profile');
  final profileText = (profileRes['result']?['content'] as List?)?.firstOrNull?['text'];
  print(profileText ?? jsonEncode(profileRes));

  print('\n📈 [POST-FIX TELEMETRY] Gathering FPS & Heap Metrics:');
  final perfRes = await callTool('get_perf_metrics');
  print((perfRes['result']?['content'] as List?)?.firstOrNull?['text']);

  serverProcess.kill();
  print('\n✨ Post-fix verification complete!');
}
