import 'dart:convert';
import 'dart:io';

void main() async {
  final process = await Process.start('dart', ['run', 'packages/flutterpilot_server/bin/flutterpilot_server.dart', '--uri', 'ws://127.0.0.1:65395/ejvx8QpmOwc=/ws']);
  
  // Wait for connection
  await Future.delayed(Duration(seconds: 5));
  
  // Send listTools request
  final request = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/list',
    'params': {}
  };
  
  process.stdin.writeln(jsonEncode(request));
  
  process.stdout.transform(utf8.decoder).listen((line) {
    print('SERVER RESPONSE: $line');
  });
  
  await Future.delayed(Duration(seconds: 2));
  process.kill();
}
