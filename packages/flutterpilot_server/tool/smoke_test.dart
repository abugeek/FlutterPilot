import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Smoke test script for FlutterPilot.
///
/// Usage:
///   1. Run your Flutter app in debug mode
///   2. Copy the VM Service URI from the console
///   3. Run: `dart run tool/smoke_test.dart <vm-service-uri>`
///
/// This exercises all major MCP tool categories and reports results.
void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/smoke_test.dart <vm-service-uri>');
    stderr.writeln(
      'Example: dart run tool/smoke_test.dart ws://127.0.0.1:12345/abc=/ws',
    );
    exit(1);
  }

  final uri = args[0];
  print('🧪 FlutterPilot Smoke Test');
  print('   VM Service URI: $uri\n');

  final process = await Process.start('dart', [
    'run',
    'bin/flutterpilot_server.dart',
    '--uri',
    uri,
  ]);

  int nextId = 1;
  int passed = 0;
  int failed = 0;
  final failures = <String>[];

  // Read JSON-RPC responses from stdout
  final responses = <int, Completer<Map<String, dynamic>>>{};
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final id = json['id'];
        if (id != null && responses.containsKey(id)) {
          responses[id]!.complete(json);
        }
      } catch (_) {
        // Not JSON — skip
      }
    },
  );

  // Log server stderr
  process.stderr
      .transform(utf8.decoder)
      .listen((data) => stderr.write('[server] $data'));

  Future<Map<String, dynamic>> callTool(
    String name, [
    Map<String, dynamic> toolArgs = const {},
  ]) async {
    final id = nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': toolArgs},
    };
    final completer = Completer<Map<String, dynamic>>();
    responses[id] = completer;
    process.stdin.writeln(jsonEncode(request));
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => {'error': 'Timed out after 15s'},
    );
  }

  Future<void> test(
    String label,
    String toolName, [
    Map<String, dynamic> toolArgs = const {},
  ]) async {
    stdout.write('  $label ... ');
    try {
      final result = await callTool(toolName, toolArgs);
      if (result.containsKey('error')) {
        print('❌ ${result['error']}');
        failed++;
        failures.add('$label: ${result['error']}');
      } else {
        print('✅');
        passed++;
      }
    } catch (e) {
      print('❌ $e');
      failed++;
      failures.add('$label: $e');
    }
  }

  // Wait for server to initialize
  print('⏳ Waiting for server to connect...');
  await Future.delayed(const Duration(seconds: 4));

  // Send MCP initialize handshake
  {
    final id = nextId++;
    final initRequest = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'smoke-test', 'version': '1.0.0'},
      },
    };
    final completer = Completer<Map<String, dynamic>>();
    responses[id] = completer;
    process.stdin.writeln(jsonEncode(initRequest));
    try {
      await completer.future.timeout(const Duration(seconds: 10));
      // Send initialized notification
      process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );
    } catch (_) {
      print('⚠️  MCP initialize handshake timed out');
    }
  }

  print('\n📋 Running smoke tests:\n');

  // Category 1: App Overview
  print('── App Overview ──');
  await test('get_app_summary', 'get_app_summary');

  // Category 2: Widget Inspection
  print('── Widget Inspection ──');
  await test('get_widget_tree', 'get_widget_tree');
  await test('get_widget_properties', 'get_widget_properties', {
    'key': 'test_key_that_may_not_exist',
  });

  // Category 3: Navigation
  print('── Navigation ──');
  await test('get_navigation_stack', 'get_navigation_stack');

  // Category 4: Error Inspection
  print('── Error Inspection ──');
  await test('get_errors', 'get_errors');

  // Category 5: Screenshots
  print('── Screenshots ──');
  await test('capture_screenshot', 'capture_screenshot');

  // Category 6: Event Stream
  print('── Events ──');
  await test('get_recent_events', 'get_recent_events');

  // Category 7: Accessibility
  print('── Accessibility ──');
  await test('get_semantics_tree', 'get_semantics_tree');

  // Category 8: Performance
  print('── Performance ──');
  await test('get_perf_metrics', 'get_perf_metrics');

  // Category 9: Debug Console
  print('── Debug Console ──');
  await test('get_debug_logs', 'get_debug_logs');

  // Category 10: DevTools Deep Inspection
  print('── DevTools ──');
  await test('get_memory_details', 'get_memory_details');
  await test('get_vm_info', 'get_vm_info');

  // Category 11: Self-Heal
  print('── Self-Heal ──');
  await test('get_self_heal_status', 'get_self_heal_status');
  await test('get_latest_crash_report', 'get_latest_crash_report');

  // Category 12: File & Project
  print('── File & Project ──');
  await test('get_build_config', 'get_build_config');

  // Summary
  print('\n${'=' * 50}');
  print('📊 Results: $passed passed, $failed failed');
  if (failures.isNotEmpty) {
    print('\nFailures:');
    for (final f in failures) {
      print('  ❌ $f');
    }
  }
  print('=' * 50);

  process.kill();
  exit(failed > 0 ? 1 : 0);
}
