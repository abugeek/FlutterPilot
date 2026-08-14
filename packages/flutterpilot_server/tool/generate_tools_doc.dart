import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Generates a schema-derived MCP tool reference.
///
/// Run from the repository root:
///   dart run packages/flutterpilot_server/tool/generate_tools_doc.dart
///
/// The generated file is written to `TOOLS.generated.md` in the repository
/// root. It intentionally comes from the registered runtime tools, not a
/// duplicated hand-maintained count.
Future<void> main() async {
  final process = await Process.start('dart', [
    'run',
    'packages/flutterpilot_server/bin/flutterpilot_server.dart',
  ]);
  final responses = <int, Completer<Map<String, dynamic>>>{};
  var nextId = 0;
  final reader = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        try {
          final message = jsonDecode(line);
          if (message is! Map<String, dynamic>) return;
          final id = message['id'];
          if (id is int) responses.remove(id)?.complete(message);
        } catch (_) {}
      });

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = ++nextId;
    final completer = Completer<Map<String, dynamic>>();
    responses[id] = completer;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 15));
  }

  try {
    await request('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'flutterpilot-doc-generator', 'version': '1.0.0'},
    });
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, dynamic>{},
      }),
    );
    final response = await request('tools/list', const {});
    final tools = (response['result'] as Map?)?['tools'];
    if (tools is! List) throw StateError('MCP tools/list returned no tools');

    final output = StringBuffer()
      ..writeln('# FlutterPilot MCP Tools')
      ..writeln()
      ..writeln(
        'Generated from the running server registration. Do not edit manually.',
      )
      ..writeln()
      ..writeln('Tool count: ${tools.length}')
      ..writeln();
    for (final rawTool in tools) {
      if (rawTool is! Map) continue;
      final name = rawTool['name']?.toString() ?? 'unknown';
      output.writeln('## `$name`');
      output.writeln();
      output.writeln(rawTool['description']?.toString() ?? '');
      final schema = rawTool['inputSchema'];
      if (schema is Map && schema['properties'] is Map) {
        output.writeln();
        output.writeln('| Parameter | Type | Required | Description |');
        output.writeln('|---|---|---:|---|');
        final required =
            (schema['required'] as List?)?.map((e) => e.toString()).toSet() ??
            <String>{};
        for (final entry in (schema['properties'] as Map).entries) {
          final property = entry.value is Map ? entry.value as Map : const {};
          output.writeln(
            '| `${entry.key}` | ${property['type'] ?? 'any'} | '
            '${required.contains(entry.key) ? 'yes' : 'no'} | '
            '${(property['description'] ?? '').toString().replaceAll('|', '\\|')} |',
          );
        }
      }
      output.writeln();
    }
    File('TOOLS.generated.md').writeAsStringSync(output.toString());
    stdout.writeln(
      'Generated TOOLS.generated.md from ${tools.length} runtime tools.',
    );
  } finally {
    await reader.cancel();
    process.kill();
    await process.exitCode;
  }
}
