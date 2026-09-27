// Drive FlutterPilot tools from a shell, the way an MCP client would.
//
// Holds one MCP stdio session to the server and exposes it on localhost:8765:
//   dart run tool/fp_bridge.dart -p /path/to/app [--allow-destructive]
//   curl -s localhost:8765 -d '{"name":"get_app_summary","arguments":{}}'
// Images are saved to tool/.fp/shots/; every call is appended to
// tool/.fp/calls.jsonl (tool, ms, isError, chars) to measure latency/size.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tool = File(Platform.script.toFilePath()).parent.path;
  final here = Directory('$tool/.fp')..createSync(recursive: true);
  final server = await Process.start('dart', [
    'run',
    '$tool/../bin/flutterpilot_server.dart',
    ...args,
  ]);
  final log = File('${here.path}/server.log').openWrite();
  server.stderr.transform(utf8.decoder).listen(log.write);
  final pending = <int, Completer<Map>>{};
  server.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
    l,
  ) {
    try {
      final m = jsonDecode(l) as Map;
      pending.remove(m['id'])?.complete(m);
    } catch (_) {}
  });
  var id = 0;
  Future<Map> rpc(String method, Map params) {
    final c = pending[++id] = Completer<Map>();
    server.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return c.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => {'error': 'timeout'},
    );
  }

  await rpc('initialize', {
    'protocolVersion': '2024-11-05',
    'capabilities': {},
    'clientInfo': {'name': 'fp-bridge', 'version': '1'},
  });
  server.stdin.writeln(
    jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
  );
  Directory('${here.path}/shots').createSync(recursive: true);
  final calls = File('${here.path}/calls.jsonl');
  var shot = 0;

  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
  print('bridge ready on :8765');
  await for (final req in http) {
    final body = jsonDecode(await utf8.decodeStream(req)) as Map;
    final sw = Stopwatch()..start();
    final res = body['name'] == '__list'
        ? await rpc('tools/list', {})
        : await rpc('tools/call', {
            'name': body['name'],
            'arguments': body['arguments'] ?? {},
          });
    sw.stop();
    final out = StringBuffer();
    final result = res['result'] as Map?;
    if (res['error'] != null) out.writeln('RPC ERROR: ${res['error']}');
    if (body['name'] == '__list') {
      out.write(jsonEncode(result));
    } else {
      for (final c in (result?['content'] as List? ?? [])) {
        if (c['type'] == 'image') {
          final f = File('${here.path}/shots/${++shot}.png')
            ..writeAsBytesSync(base64.decode(c['data'] as String));
          out.writeln('[image saved: ${f.path}]');
        } else {
          out.writeln(c['text']);
        }
      }
    }
    final isError = res['error'] != null || result?['isError'] == true;
    calls.writeAsStringSync(
      '${jsonEncode({'tool': body['name'], 'ms': sw.elapsedMilliseconds, 'isError': isError, 'chars': out.length})}\n',
      mode: FileMode.append,
    );
    req.response
      ..write(
        '${isError ? '[isError] ' : ''}(${sw.elapsedMilliseconds}ms)\n$out',
      )
      ..close();
  }
}
