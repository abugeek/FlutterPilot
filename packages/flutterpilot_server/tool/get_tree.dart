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

  final request = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {'name': 'get_widget_tree', 'arguments': {}},
  };

  process.stdin.writeln(jsonEncode(request));

  process.stdout.transform(utf8.decoder).listen((line) {
    if (line.contains('result')) {
      print(line);
    }
  });

  await Future.delayed(Duration(seconds: 3));
  process.kill();
}
