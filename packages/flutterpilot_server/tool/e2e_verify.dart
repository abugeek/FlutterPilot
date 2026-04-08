import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart e2e_verify.dart <vm-service-uri>');
    exit(1);
  }

  final uri = args[0];
  print('--- Starting E2E Verification for FlutterPilot ---');
  print('Connecting to Server with App URI: $uri');

  final process = await Process.start('dart', [
    'run',
    'packages/flutterpilot_server/bin/flutterpilot_server.dart',
    '--uri',
    uri,
  ]);

  // Helper to call tools
  Future<Map<String, dynamic>> callTool(
    String name, [
    Map<String, dynamic> args = const {},
  ]) async {
    final id = DateTime.now().millisecondsSinceEpoch;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    };
    process.stdin.writeln(jsonEncode(request));

    // We wait for the specific ID in the stream
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription sub;
    sub = process.stdout.transform(utf8.decoder).listen((line) {
      try {
        final resp = jsonDecode(line);
        if (resp['id'] == id) {
          sub.cancel();
          completer.complete(resp);
        }
      } catch (_) {}
    });

    return completer.future.timeout(Duration(seconds: 10));
  }

  try {
    await Future.delayed(Duration(seconds: 5));

    print('\n1. Verifying App Summary...');
    final summary = await callTool('get_app_summary');
    print('Summary Result: ${summary['result']}');

    print('\n2. Navigating to State Injection screen...');
    await callTool('navigate_to', {'route': '/state'});
    await Future.delayed(Duration(seconds: 1));

    print('\n3. Injecting Riverpod State (Setting count to 1337)...');
    final rpRes = await callTool('set_riverpod_state', {
      'name': 'AutoDisposeStateProvider<int>', // Riverpod runtime name
      'value': 1337,
    });
    print('Riverpod Injection: ${rpRes['result']}');

    print('\n4. Injecting Bloc State (Setting count to 42)...');
    final blocRes = await callTool('set_bloc_state', {
      'name': 'CounterCubit',
      'state': 42,
    });
    print('Bloc Injection: ${blocRes['result']}');

    print('\n5. Verifying UI reflects injected state...');
    final tree = await callTool('get_widget_tree');
    final treeString = tree['result'].toString();

    if (treeString.contains('1337') && treeString.contains('42')) {
      print('✅ SUCCESS: UI verified injected states!');
    } else {
      print('❌ FAILURE: UI does not show injected states.');
      print('Tree Content: ${treeString.substring(0, 500)}...');
    }

    print('\n6. Capturing vision screenshot...');
    final screenshot = await callTool('capture_screenshot');
    if (screenshot['result'] != null) {
      print('✅ SUCCESS: Screenshot captured.');
    }

    print('\n--- E2E Verification Complete ---');
  } catch (e) {
    print('❌ ERROR during verification: $e');
  } finally {
    process.kill();
    exit(0);
  }
}
