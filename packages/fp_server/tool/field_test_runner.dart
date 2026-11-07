import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class _McpClient {
  _McpClient(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        final id = msg['id'] as int?;
        if (id != null) {
          _pending.remove(id)?.complete(msg);
        }
      } catch (_) {}
    });
  }

  final Process _process;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = ++_nextId;
    final completer = _pending[id] = Completer();
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 45));
  }

  void notify(String method, [Map<String, dynamic>? params]) {
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': ?params,
      }),
    );
  }

  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) {
    return request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
  }
}

/// Runs live field tests of FlutterPilot tools against a real Flutter app.
///
/// Usage:
///   dart run packages/fp_server/tool/field_test_runner.dart [--app <path>] [-d <device>] [--uri <ws://...>]
Future<void> main(List<String> args) async {
  final dIdx = args.indexOf('-d');
  final device =
      dIdx >= 0 && dIdx + 1 < args.length ? args[dIdx + 1] : 'macos';

  final appIdx = args.indexOf('--app');
  final repo = Directory.fromUri(Platform.script.resolve('../../..')).path;
  final defaultApp = p.join(repo, 'examples', 'flutter_pilot_example');
  final appPath =
      appIdx >= 0 && appIdx + 1 < args.length ? args[appIdx + 1] : defaultApp;

  final uriIdx = args.indexOf('--uri');
  var wsUri =
      uriIdx >= 0 && uriIdx + 1 < args.length ? args[uriIdx + 1] : null;

  final tIdx = args.indexOf('-t');
  String? target = tIdx >= 0 && tIdx + 1 < args.length ? args[tIdx + 1] : null;
  if (target == null &&
      !File(p.join(appPath, 'lib', 'main.dart')).existsSync() &&
      File(p.join(appPath, 'lib', 'main_development.dart')).existsSync()) {
    target = 'lib/main_development.dart';
  }

  print('===============================================================');
  print('FlutterPilot Autonomous Capabilities Field Test Runner');
  print('App:    $appPath');
  print('Device: $device');
  if (target != null) print('Target: $target');
  print('===============================================================');

  Process? flutterProcess;
  Process? serverProcess;

  if (wsUri == null) {
    print('▶ Launching app with flutter run --machine -d $device ...');
    flutterProcess = await Process.start(
      'flutter',
      [
        'run',
        '--machine',
        '--vmservice-out-file=.dart_tool/flutterpilot_vm_uri',
        '-d',
        device,
        if (target != null) ...['-t', target],
      ],
      workingDirectory: appPath,
      runInShell: Platform.isWindows,
    );

    final wsCompleter = Completer<String>();
    final startedCompleter = Completer<void>();

    flutterProcess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (!line.startsWith('[{')) return;
      try {
        for (final item in (jsonDecode(line) as List).cast<Map>()) {
          final event = item['event'] as String?;
          final params = item['params'] as Map?;
          if (event == 'app.debugPort' && !wsCompleter.isCompleted) {
            wsCompleter.complete(params!['wsUri'] as String);
          }
          if (event == 'app.started' && !startedCompleter.isCompleted) {
            startedCompleter.complete();
          }
        }
      } catch (_) {}
    });

    flutterProcess.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((err) {
      if (err.trim().isNotEmpty) print('  [app err] $err');
    });

    try {
      wsUri = await wsCompleter.future.timeout(const Duration(minutes: 3));
      print('✓ Connected to Flutter VM Service at $wsUri');
      await startedCompleter.future
          .timeout(const Duration(seconds: 45), onTimeout: () {});
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (e) {
      print('✗ Failed to obtain VM Service URI: $e');
      flutterProcess.kill(ProcessSignal.sigkill);
      exit(1);
    }
  } else {
    print('✓ Using provided VM Service URI: $wsUri');
  }

  print('▶ Starting FlutterPilot server...');
  serverProcess = await Process.start(
    'dart',
    ['run', 'bin/fp_server.dart', '--uri', wsUri],
    workingDirectory: p.join(repo, 'packages', 'fp_server'),
  );

  final client = _McpClient(serverProcess);
  await client.request('initialize', {
    'protocolVersion': '2024-11-05',
    'capabilities': {},
    'clientInfo': {'name': 'field_test_runner', 'version': '1.0.0'},
  });
  client.notify('notifications/initialized');

  var passedCount = 0;
  var failedCount = 0;

  Future<void> runTest(
    String label,
    String toolName,
    Map<String, dynamic> arguments, {
    bool Function(Map<String, dynamic> res)? verify,
  }) async {
    stdout.write('TEST: $label ... ');
    final stopwatch = Stopwatch()..start();
    try {
      final msg = await client.callTool(toolName, arguments);
      if (msg.containsKey('error')) {
        failedCount++;
        print('FAIL (${stopwatch.elapsedMilliseconds}ms)');
        print('      [rpc error] ${msg['error']}');
        return;
      }
      final res = msg['result'] as Map<String, dynamic>? ?? {};
      final isError = res['isError'] == true;
      final ok = !isError && (verify == null || verify(res));
      stopwatch.stop();
      if (ok) {
        passedCount++;
        print('PASS (${stopwatch.elapsedMilliseconds}ms)');
        final content = res['content'] as List? ?? [];
        final firstText = content.isNotEmpty ? content.first['text']?.toString() ?? '' : '';
        if (firstText.isNotEmpty) {
          if (label == 'get_app_summary') {
            print('--- APP SUMMARY ---\n$firstText\n-------------------');
          } else {
            print('      → ${firstText.split('\n').first}');
          }
        }
      } else {
        failedCount++;
        print('FAIL (${stopwatch.elapsedMilliseconds}ms)');
        print('      [response] $res');
      }
    } catch (e, st) {
      stopwatch.stop();
      failedCount++;
      print('EXCEPTION (${stopwatch.elapsedMilliseconds}ms): $e');
      print(st);
    }
  }

  try {
    // 1. App Summary & Screen Health
    await runTest('get_app_summary', 'get_app_summary', {}, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Route') || text.contains('App');
    });

    await runTest('audit_screen_health', 'audit_screen_health', {}, verify: (r) {
      return (r['content'] as List?)?.isNotEmpty == true;
    });

    // 2. Keyboard Simulation
    await runTest(
      'simulate_keyboard',
      'simulate_keyboard',
      {'height': 300, 'restore': true},
      verify: (r) {
        final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
        return text.contains('Simulated on-screen keyboard (300dp)');
      },
    );

    // 3. Screenshot Capture & Previous Comparison
    await runTest('capture_screenshot', 'capture_screenshot', {'scale': 0.5}, verify: (r) {
      return (r['content'] as List?)?.isNotEmpty == true;
    });

    await runTest(
      'compare_screenshot (comparePrevious)',
      'compare_screenshot',
      {'comparePrevious': true},
      verify: (r) {
        final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
        return text.contains('Visual comparison');
      },
    );

    // 4. AST Source Locator & Surgical Patching (on initial screen)
    final isHn = appPath.contains('hn_reader');
    final isBloc = appPath.contains('flutter_todos');
    final isProviderApp = appPath.contains('provider_testing_app') || appPath.contains('testing_app');
    final isM3 = appPath.contains('material_3_demo');
    final targetKey = isHn
        ? 'Hacker News'
        : (isBloc
            ? 'homeView_addTodo_floatingActionButton'
            : (isProviderApp
                ? 'icon_0'
                : (isM3 ? 'Elevated' : 'add_todo')));
    final targetExpectedFile = isHn
        ? 'feed_screen.dart'
        : (isBloc
            ? 'home_page.dart'
            : (isProviderApp
                ? 'home.dart'
                : (isM3 ? 'component_screen.dart' : 'screens.dart')));

    await runTest('locate_source_ast', 'locate_source_ast', {'key': targetKey}, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains(targetExpectedFile);
    });

    await runTest('apply_patch_and_verify (wrap)', 'apply_patch_and_verify', {
      'key': targetKey,
      'wrapWith': 'Center',
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Patched lib/') && text.contains(targetExpectedFile);
    });

    await runTest('apply_patch_and_verify (unwrap to restore)', 'apply_patch_and_verify', {
      'key': targetKey,
      'unwrap': true,
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Patched lib/') && text.contains(targetExpectedFile);
    });

    // 5. Whole-App Crawler
    await runTest('crawl_app', 'crawl_app', {'maxScreens': 3, 'restore': true}, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Crawled');
    });

    // In-App Action Chain (tap item 0 & 1 favorites)
    if (isProviderApp) {
      await runTest('execute_action_chain', 'execute_action_chain', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'icon_0'},
          },
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'icon_1'},
          },
        ],
      }, verify: (r) {
        final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
        return text.contains('Action chain: 2/2 steps done');
      });

      // GoRouter Navigation test
      await runTest('navigate_to (/favorites_page)', 'navigate_to', {
        'route': '/favorites_page',
      }, verify: (r) {
        final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
        return text.contains('favorites_page');
      });
    }

    // 6. Reactive Rebuild Profiler
    await runTest('get_rebuild_stats (init)', 'get_rebuild_stats', {}, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('counting') || text.contains('rebuilds');
    });

    // 7. Design Token Auditor
    await runTest('audit_design_tokens', 'audit_design_tokens', {}, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains("app's code") || text.contains("theme");
    });

    // Check available tools for plugin-specific tests
    final toolsRes = await client.request('tools/list', {});
    final availableTools = [
      for (final t in (toolsRes['result']?['tools'] as List? ?? const []))
        t['name']?.toString() ?? '',
    ];

    if (availableTools.contains('get_state')) {
      await runTest('get_state', 'get_state', {}, verify: (r) {
        return (r['content'] as List?)?.isNotEmpty == true;
      });
    }

    if (availableTools.contains('export_network_mocks')) {
      await runTest('export_network_mocks', 'export_network_mocks', {}, verify: (r) {
        return (r['content'] as List?)?.isNotEmpty == true;
      });
    }

    // 8. Responsive Viewport Matrix Validation
    await runTest('audit_screen_health (viewports matrix)', 'audit_screen_health', {
      'viewports': ['mobile_portrait', 'mobile_landscape'],
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Responsive Viewport Matrix');
    });

    // 9. Network Chaos & Fuzzing
    await runTest('simulate_network (chaos)', 'simulate_network', {
      'errorRate': 0.5,
      'statusCode': 503,
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('success');
    });

    await runTest('simulate_network (restore)', 'simulate_network', {
      'restore': true,
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('restored');
    });

    // 10. Memory Introspection
    await runTest('get_memory_details (classes: true)', 'get_memory_details', {
      'classes': true,
      'limit': 5,
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Top') || text.contains('Heap') || text.contains('classes');
    });

    // 11. Journey Flow Export to Integration Test
    final chainKey = isHn ? 'Stories Tab 1 of 3' : targetKey;
    await runTest('execute_action_chain (exportAsTest)', 'execute_action_chain', {
      'steps': [
        {
          'tool': 'tap_widget',
          'arguments': {'key': chainKey},
        },
      ],
      'exportAsTest': true,
      'testName': 'field_journey',
    }, verify: (r) {
      final text = (r['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
      return text.contains('Action chain') && text.contains('Exported journey');
    });

  } finally {
    print('===============================================================');
    print('Field Test Results: $passedCount PASSED, $failedCount FAILED');
    print('===============================================================');

    serverProcess.kill(ProcessSignal.sigterm);
    if (flutterProcess != null) {
      print('Stopping Flutter process...');
      flutterProcess.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      flutterProcess.kill(ProcessSignal.sigkill);
    }
  }

  if (failedCount > 0) {
    exit(1);
  }
}
