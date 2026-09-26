import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:60737/NoW6oZ8wAF8=/ws';
  print('================================================================');
  print('🔍 Step 1 & 2: Autonomous Performance Diagnosis Simulation');
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
      'clientInfo': {'name': 'anim-diag', 'version': '1.0.0'},
    },
  }));
  await initCompleter.future;
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  print('🧭 [EXPLORATION] Navigating from Dashboard to Animation Lab...');
  final tapNav = await callTool('tap_widget', {'key': 'nav_animation_lab_button'});
  print('   ${(tapNav['result']?['content'] as List?)?.firstOrNull?['text']}\n');

  await Future.delayed(const Duration(milliseconds: 500));

  print('🎬 [INTERACTION] Starting the Particle Wave Galaxy Animation...');
  final startAnim = await callTool('tap_widget', {'key': 'start_animation_button'});
  print('   ${(startAnim['result']?['content'] as List?)?.firstOrNull?['text']}\n');

  print('⏱️  Letting animation run for 2.0 seconds to collect real frame timings...');
  await Future.delayed(const Duration(seconds: 2));

  print('📊 [TELEMETRY 1] Gathering Frame Budget Profile from FlutterPilot:');
  final profile1Res = await callTool('get_frame_budget_profile');
  final profile1Text = (profile1Res['result']?['content'] as List?)?.firstOrNull?['text'];
  print(profile1Text ?? jsonEncode(profile1Res));

  print('\n📈 [TELEMETRY 1] Gathering FPS & Heap Metrics:');
  final perf1Res = await callTool('get_perf_metrics');
  print((perf1Res['result']?['content'] as List?)?.firstOrNull?['text']);

  print('\n🔁 [REPRODUCTION] Simulating user observing and testing again...');
  await Future.delayed(const Duration(seconds: 2));

  print('📊 [TELEMETRY 2] Sustained Frame Budget Profile:');
  final profile2Res = await callTool('get_frame_budget_profile');
  final profile2Text = (profile2Res['result']?['content'] as List?)?.firstOrNull?['text'];
  print(profile2Text ?? jsonEncode(profile2Res));

  serverProcess.kill();

  // Save telemetry to file for diagnosis
  File('anim_telemetry_before.json').writeAsStringSync(profile2Text ?? '');
  print('\n✅ Telemetry successfully gathered! Ready for root-cause analysis.');
}
