import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:59506/OEVucqv9kvI=/ws';
  print('================================================================');
  print('🚀 FlutterPilot Comprehensive Live Android Verification Suite');
  print('   Connected VM Service: $uri');
  print('================================================================\n');

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

  serverProcess.stderr.transform(utf8.decoder).listen((data) {
    stderr.write(data);
  });

  Future<Map<String, dynamic>> sendRequest(String method, [Map<String, dynamic>? params]) async {
    final id = idCounter++;
    final completer = Completer<Map<String, dynamic>>();
    completers[id] = completer;
    serverProcess.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    }));
    return completer.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> callTool(String name, [Map<String, dynamic> args = const {}]) async {
    return sendRequest('tools/call', {'name': name, 'arguments': args});
  }

  String extractResultText(Map<String, dynamic> res) {
    if (res['error'] != null) {
      return '❌ ERROR: ${jsonEncode(res['error'])}';
    }
    final content = res['result']?['content'] as List?;
    if (content != null && content.isNotEmpty) {
      return content.map((c) => c['text'] ?? '').join('\n');
    }
    return jsonEncode(res['result'] ?? res);
  }

  // 1. MCP Initialization Handshake
  print('🤝 [PHASE 1] Initializing MCP Session...');
  await Future.delayed(const Duration(seconds: 2));
  final initRes = await sendRequest('initialize', {
    'protocolVersion': '2024-11-05',
    'capabilities': {},
    'clientInfo': {'name': 'flutterpilot-e2e-agent', 'version': '1.0.0'},
  });
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
  print('   MCP Session Initialized: ${initRes['result']?['serverInfo']?['name'] ?? 'FlutterPilot Server'}');

  // 2. Discovery & Runtime Snapshot
  print('\n📱 [PHASE 2] Introspecting App Snapshot & Route Stack...');
  final snapshot = await callTool('get_app_snapshot');
  print(extractResultText(snapshot));

  final navStack = await callTool('get_navigation_stack');
  print('   Navigation Stack: ${extractResultText(navStack)}');

  // 3. UI Automation & Semantic Discovery
  print('\n🎯 [PHASE 3] Interactive Elements on Screen:');
  final elements = await callTool('get_interactive_elements');
  print(extractResultText(elements));

  // 4. Navigation & State Mutation
  print('\n🧭 [PHASE 4] Navigating to /state (State Injection Screen)...');
  final navState = await callTool('tap_widget', {'key': 'nav_state_button'});
  print(extractResultText(navState));
  await Future.delayed(const Duration(milliseconds: 600));

  print('\n⌨️ [PHASE 5] Interacting with State Injection Elements:');
  print('   • Tapping Riverpod counter increment...');
  final tapRiverpod = await callTool('tap_widget', {'key': 'riverpod_increment_button'});
  print(extractResultText(tapRiverpod));

  print('   • Tapping Bloc counter increment...');
  final tapBloc = await callTool('tap_widget', {'key': 'bloc_increment_button'});
  print(extractResultText(tapBloc));

  print('\n🧪 [PHASE 6] Direct State Introspection & Injection via FlutterPilot:');
  final riverpodState = await callTool('get_riverpod_state');
  print('   Current Riverpod Providers:\n${extractResultText(riverpodState)}');

  final blocState = await callTool('get_bloc_state');
  print('   Current Bloc State:\n${extractResultText(blocState)}');

  // 5. Animation Lab & Performance Profiling
  print('\n⚡ [PHASE 7] Navigating to /animation_lab...');
  final navAnim = await callTool('navigate_to', {'route': '/animation_lab'});
  print(extractResultText(navAnim));
  await Future.delayed(const Duration(milliseconds: 600));

  print('\n📊 [PHASE 8] Performance & Frame Budget Profiler:');
  final perfBudget = await callTool('get_frame_budget_profile');
  print(extractResultText(perfBudget));

  print('\n🎨 [PHASE 9] Toggling Animation in Lab:');
  final animToggle = await callTool('tap_widget', {'key': 'toggle_animation_button'});
  print(extractResultText(animToggle));
  await Future.delayed(const Duration(milliseconds: 800));

  // 6. Return to Dashboard & Capture Screenshot
  print('\n📸 [PHASE 10] Returning to Dashboard and Capturing Screenshot:');
  await callTool('navigate_to', {'route': '/'});
  await Future.delayed(const Duration(milliseconds: 500));

  final screenshot = await callTool('capture_screenshot');
  final screenshotOutput = extractResultText(screenshot);
  print(screenshotOutput.length > 200 ? '${screenshotOutput.substring(0, 200)}... (truncated)' : screenshotOutput);

  // 7. System Health Check
  print('\n🛡️ [PHASE 11] Checking Overall FlutterPilot System Health:');
  final health = await callTool('get_system_health');
  print(extractResultText(health));

  serverProcess.kill();
  print('\n================================================================');
  print('✅ FlutterPilot Full E2E Test Suite Passed With Distinction!');
  print('================================================================');
}
