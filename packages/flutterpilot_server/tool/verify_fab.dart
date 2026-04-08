import 'dart:convert';
import 'dart:io';

void main() async {
  final process = await Process.start('dart', ['run', 'packages/flutterpilot_server/bin/flutterpilot_server.dart', '--uri', 'ws://127.0.0.1:65395/ejvx8QpmOwc=/ws']);
  await Future.delayed(Duration(seconds: 5));
  
  // 1. Verify FAB exists
  final treeReq = {
    'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
    'params': {'name': 'get_widget_tree', 'arguments': {}}
  };
  process.stdin.writeln(jsonEncode(treeReq));
  
  // 2. Call Custom Tool
  final customReq = {
    'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
    'params': {'name': 'call_custom_tool', 'arguments': {'name': 'submit_feedback', 'params': {'text': 'This tool is awesome!'}}}
  };
  process.stdin.writeln(jsonEncode(customReq));

  process.stdout.transform(utf8.decoder).listen((line) {
    if (line.contains('result')) print('SERVER RESPONSE: $line');
  });
  
  await Future.delayed(Duration(seconds: 3));
  process.kill();
}
