import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BenchmarkResult {
  final String scenario;
  final String tool;
  final List<double> latenciesMs;
  final String notes;
  final dynamic sampleOutput;

  BenchmarkResult({
    required this.scenario,
    required this.tool,
    required this.latenciesMs,
    required this.notes,
    this.sampleOutput,
  });

  double get min => latenciesMs.isEmpty ? 0 : latenciesMs.reduce((a, b) => a < b ? a : b);
  double get max => latenciesMs.isEmpty ? 0 : latenciesMs.reduce((a, b) => a > b ? a : b);
  double get avg => latenciesMs.isEmpty ? 0 : latenciesMs.reduce((a, b) => a + b) / latenciesMs.length;
  double get median {
    if (latenciesMs.isEmpty) return 0;
    final sorted = List<double>.from(latenciesMs)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}

void main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:60737/NoW6oZ8wAF8=/ws';
  print('================================================================');
  print('🚀 FlutterPilot Comprehensive Real-World Benchmark Suite');
  print('   Target: Android Emulator (emulator-5554, API 37, Impeller)');
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

  Future<Map<String, dynamic>> callMcp(String method, [Map<String, dynamic>? params]) async {
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

  Future<Map<String, dynamic>> tool(String name, [Map<String, dynamic> args = const {}]) {
    return callMcp('tools/call', {'name': name, 'arguments': args});
  }

  // Handshake
  await Future.delayed(const Duration(seconds: 2));
  await callMcp('initialize', {
    'protocolVersion': '2024-11-05',
    'capabilities': {},
    'clientInfo': {'name': 'benchmark-runner', 'version': '1.0.0'},
  });
  serverProcess.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));

  final results = <BenchmarkResult>[];

  Future<BenchmarkResult> measure(
    String scenario,
    String toolName,
    Map<String, dynamic> args, {
    int iterations = 3,
    String notes = '',
  }) async {
    final latencies = <double>[];
    dynamic lastSample;
    for (int i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      final res = await tool(toolName, args);
      sw.stop();
      final elapsed = sw.elapsedMicroseconds / 1000.0;
      latencies.add(elapsed);
      lastSample = (res['result']?['content'] as List?)?.firstOrNull?['text'] ?? res;
      await Future.delayed(const Duration(milliseconds: 30));
    }
    final r = BenchmarkResult(
      scenario: scenario,
      tool: toolName,
      latenciesMs: latencies,
      notes: notes,
      sampleOutput: lastSample,
    );
    results.add(r);
    print('  [$scenario] $toolName -> Avg: ${r.avg.toStringAsFixed(1)}ms (Min: ${r.min.toStringAsFixed(1)}ms, Max: ${r.max.toStringAsFixed(1)}ms)');
    return r;
  }

  // Reset to root route
  await tool('navigate_to', {'route': '/'});
  await Future.delayed(const Duration(milliseconds: 200));

  print('\n📊 Scenario 1: State & UI Discovery');
  await measure('Discovery', 'get_app_snapshot', {}, iterations: 5, notes: 'Single-call consolidated snapshot');
  await measure('Discovery', 'get_interactive_elements', {}, iterations: 5, notes: 'Filtered visible hittable elements');
  await measure('Discovery', 'get_widget_tree', {'max_depth': 6}, iterations: 5, notes: 'Full AST-like tree walk (depth 6)');
  await measure('Discovery', 'get_semantics_tree', {}, iterations: 5, notes: 'Flutter semantics accessibility tree');
  await measure('Discovery', 'get_navigation_stack', {}, iterations: 5, notes: 'Current route and stack depth');
  await measure('Discovery', 'get_perf_metrics', {}, iterations: 5, notes: 'FPS, memory & raster stats');
  await measure('Discovery', 'get_logs', {'limit': 20}, iterations: 5, notes: 'Recent console logs');

  print('\n📊 Scenario 2: UI Interactions (Taps & Real Post-Action Feedback)');
  // Tap State button
  await measure('Interaction', 'tap_widget', {'key': 'nav_state_button'}, iterations: 1, notes: 'Tap Nav Button -> navigate to /state');
  await Future.delayed(const Duration(milliseconds: 200));

  // Verify state on /state screen
  await measure('Interaction', 'get_app_snapshot', {}, iterations: 3, notes: 'Snapshot on /state screen');

  // Tap counter increments on /state
  await measure('Interaction', 'tap_widget', {'key': 'riverpod_increment_button'}, iterations: 3, notes: 'Tap Riverpod increment button');
  await measure('Interaction', 'tap_widget', {'key': 'bloc_increment_button'}, iterations: 3, notes: 'Tap Bloc increment button');

  print('\n📊 Scenario 3: Missing Target Resilience (Optimized Scroll Detection)');
  await measure('Resilience', 'tap_widget', {'key': 'non_existent_button_xyz'}, iterations: 1, notes: 'Fast rejection of non-existent widget');

  print('\n📊 Scenario 4: Programmatic Direct Navigation');
  await measure('Navigation', 'navigate_to', {'route': '/network'}, iterations: 1, notes: 'Direct route navigation to /network');
  await Future.delayed(const Duration(milliseconds: 150));
  await measure('Navigation', 'navigate_to', {'route': '/storage'}, iterations: 1, notes: 'Direct route navigation to /storage');
  await Future.delayed(const Duration(milliseconds: 150));
  await measure('Navigation', 'navigate_to', {'route': '/chaos'}, iterations: 1, notes: 'Direct route navigation to /chaos');
  await Future.delayed(const Duration(milliseconds: 150));
  await measure('Navigation', 'navigate_to', {'route': '/testing'}, iterations: 1, notes: 'Direct route navigation to /testing');
  await Future.delayed(const Duration(milliseconds: 150));
  await measure('Navigation', 'navigate_to', {'route': '/'}, iterations: 1, notes: 'Direct route navigation to /');
  await Future.delayed(const Duration(milliseconds: 150));

  print('\n📊 Scenario 5: Visual Screenshot Capture');
  await measure('Visual', 'capture_screenshot', {}, iterations: 3, notes: 'Full frame Impeller render & base64 transfer');

  print('\n📊 Scenario 6: State Inspection (Riverpod & Bloc)');
  await measure('State', 'get_riverpod_state', {}, iterations: 3, notes: 'Read Riverpod provider tree');
  await measure('State', 'get_bloc_state', {}, iterations: 3, notes: 'Read Bloc cubit state');

  serverProcess.kill();

  print('\n================================================================');
  print('📋 FINAL BENCHMARK SUMMARY REPORT');
  print('================================================================');
  print('| Scenario    | Tool Call                | Min (ms) | Avg (ms) | Max (ms) | Notes |');
  print('| :---------- | :----------------------- | -------: | -------: | -------: | :---- |');
  for (final r in results) {
    print('| ${r.scenario.padRight(11)} | ${r.tool.padRight(24)} | ${r.min.toStringAsFixed(1).padLeft(8)} | ${r.avg.toStringAsFixed(1).padLeft(8)} | ${r.max.toStringAsFixed(1).padLeft(8)} | ${r.notes} |');
  }
  print('================================================================\n');

  final report = {
    'timestamp': DateTime.now().toIso8601String(),
    'device': 'emulator-5554 (Android 17, Impeller)',
    'results': results.map((r) => {
      'scenario': r.scenario,
      'tool': r.tool,
      'min_ms': r.min,
      'avg_ms': r.avg,
      'max_ms': r.max,
      'median_ms': r.median,
      'latencies_ms': r.latenciesMs,
      'notes': r.notes,
      'sample_output_preview': r.sampleOutput.toString().length > 250 
          ? '${r.sampleOutput.toString().substring(0, 250)}...' 
          : r.sampleOutput.toString(),
    }).toList(),
  };

  File('benchmark_report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  print('Saved detailed report to benchmark_report.json');
}
