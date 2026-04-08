import 'dart:convert';
import 'dart:io';

void main() async {
  print('--- Starting Server in background ---');
  final process = await Process.start('dart', [
    'run',
    'packages/flutterpilot_server/bin/flutterpilot_server.dart',
    '--uri',
    'ws://127.0.0.1:65395/ejvx8QpmOwc=/ws',
  ]);

  process.stderr.transform(utf8.decoder).listen((line) {
    if (line.contains('SELF-HEAL')) {
      print('>>> CAUGHT PROACTIVE ALERT <<<');
      print('${line.substring(0, 200)}...');
      process.kill();
      exit(0);
    }
  });

  await Future.delayed(Duration(seconds: 5));

  print('--- Triggering App Error ---');
  final request = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {
      'name': 'call_custom_tool',
      'arguments': {'name': 'trigger_error', 'params': {}},
    },
  };

  process.stdin.writeln(jsonEncode(request));

  await Future.delayed(Duration(seconds: 15));
  print('No alert caught.');
  process.kill();
}
