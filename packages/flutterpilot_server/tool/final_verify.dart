import 'dart:convert';
import 'dart:io';

void main() async {
  final process = await Process.start('dart', [
    'run',
    'packages/flutterpilot_server/bin/flutterpilot_server.dart',
    '--uri',
    'ws://127.0.0.1:65395/ejvx8QpmOwc=/ws',
  ]);
  await Future.delayed(Duration(seconds: 5));

  // 1. Call the new Custom Tool
  final customReq = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {
      'name': 'call_custom_tool',
      'arguments': {
        'name': 'submit_feedback',
        'params': {'text': 'Autonomous Test Successful!'},
      },
    },
  };
  process.stdin.writeln(jsonEncode(customReq));

  // 2. Capture a vision-ready screenshot
  final visionReq = {
    'jsonrpc': '2.0',
    'id': 2,
    'method': 'tools/call',
    'params': {'name': 'capture_screenshot', 'arguments': {}},
  };
  process.stdin.writeln(jsonEncode(visionReq));

  process.stdout.transform(utf8.decoder).listen((line) {
    if (line.contains('result')) print('PILOT RESPONSE: $line');
  });

  await Future.delayed(Duration(seconds: 5));
  process.kill();
}
