// A deterministic fake MCP server for `test/startup_benchmark_test.dart`.
//
// The task-09 harness (`tool/benchmarks/startup_benchmark.dart`) speaks MCP over
// a child process's stdio and times the whole handshake on one monotonic clock.
// Proving that harness — ordering, delays, timeouts, death, malformed stdout,
// cleanup, awkward paths — must not require the real FlutterPilot server, a
// Flutter app, or the network. This fixture is a minimal JSON-RPC responder
// whose entire behaviour is driven by environment variables, so one file can
// act like a healthy server, a slow one, a silent one, a dying one or a noisy
// one.
//
// Environment variables:
//   FAKE_BANNER            literal text (with `\n`) written to stdout first.
//   FAKE_INIT_DELAY_MS     delay before replying to `initialize`.
//   FAKE_READ_DELAY_MS     delay before replying to any `tools/call`.
//   FAKE_SLOW_TOOL         tool name that uses FAKE_SLOW_TOOL_MS instead.
//   FAKE_SLOW_TOOL_MS      delay for FAKE_SLOW_TOOL.
//   FAKE_NO_REPLY          comma-separated methods to never answer.
//   FAKE_EXIT_ON_METHOD    method name on which to exit(0) without replying.
//   FAKE_EXIT_BEFORE_REPLY '1' to exit(0) before reading stdin at all.
//   FAKE_EXIT_AFTER_INIT   '1' to exit(0) right after replying to initialize.
//   FAKE_CHILD_PID_FILE    path to record a long-lived grandchild's pid, so a
//                          harness test can prove tree cleanup.
//   FAKE_PROTOCOL_VERSION  protocolVersion echoed in the initialize result.
//   FAKE_TOOL_COUNT        number of fake tools returned by tools/list.
//   FAKE_ERROR_TOOLS       comma-separated tool names whose call is isError.
//   FAKE_STRUCTURED        '1' to add a `structuredContent` to tool replies.
//   FAKE_SERVER_NAME       serverInfo.name.
//   FAKE_RECORD_FILE       path to write `{pid,cwd,args,stderr?}` as JSON.
//   FAKE_STDERR            literal text (with `\n`) written to stderr at start.
//
// This is test support, not shipped code.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final recordFile = env['FAKE_RECORD_FILE'] ?? '';
  if (recordFile.isNotEmpty) {
    File(recordFile).writeAsStringSync(
      jsonEncode({
        'pid': pid,
        'cwd': Directory.current.path,
        'args': args,
        'executable': Platform.resolvedExecutable,
      }),
    );
  }

  final stderrText = env['FAKE_STDERR'] ?? '';
  if (stderrText.isNotEmpty) {
    stderr.write(stderrText.replaceAll(r'\n', '\n'));
  }

  final banner = env['FAKE_BANNER'] ?? '';
  if (banner.isNotEmpty) {
    stdout.write(banner.replaceAll(r'\n', '\n'));
    await stdout.flush();
  }

  final childPidFile = env['FAKE_CHILD_PID_FILE'] ?? '';
  if (childPidFile.isNotEmpty) {
    final child = await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/fixtures/fake_sleeper.dart',
    ]);
    File(childPidFile).writeAsStringSync('${child.pid}');
  }

  if (env['FAKE_EXIT_BEFORE_REPLY'] == '1') {
    exit(0);
  }

  final noReply = (env['FAKE_NO_REPLY'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final errorTools = (env['FAKE_ERROR_TOOLS'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final initDelay = _ms(env['FAKE_INIT_DELAY_MS']);
  final readDelay = _ms(env['FAKE_READ_DELAY_MS']);
  final slowTool = env['FAKE_SLOW_TOOL'] ?? '';
  final slowToolDelay = _ms(env['FAKE_SLOW_TOOL_MS']);
  final toolCount = int.tryParse(env['FAKE_TOOL_COUNT'] ?? '') ?? 3;
  final protocolVersion = env['FAKE_PROTOCOL_VERSION'] ?? '2025-11-25';
  final serverName = env['FAKE_SERVER_NAME'] ?? 'fake-mcp-server';
  final exitAfterInit = env['FAKE_EXIT_AFTER_INIT'] == '1';
  final exitOnMethod = env['FAKE_EXIT_ON_METHOD'] ?? '';

  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    final text = line.trim();
    if (text.isEmpty) continue;
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) continue;
      message = decoded.cast<String, dynamic>();
    } on FormatException {
      // A client that writes junk is simply ignored, like a real server.
      continue;
    }
    final id = message['id'];
    final method = message['method'];
    if (method is! String || id == null) {
      // A notification (`notifications/initialized`) or a response to us.
      continue;
    }
    if (noReply.contains(method)) continue;
    // Die while a request is pending (deterministic "exits before replying").
    if (method == exitOnMethod) exit(0);

    switch (method) {
      case 'initialize':
        if (initDelay > Duration.zero) await Future<void>.delayed(initDelay);
        _reply(id, {
          'protocolVersion': protocolVersion,
          'capabilities': {
            'tools': {'listChanged': true},
            'roots': <String, dynamic>{},
          },
          'serverInfo': {'name': serverName, 'version': '0.0.0'},
        });
        if (exitAfterInit) exit(0);
      case 'tools/list':
        _reply(id, {
          'tools': [
            for (var i = 0; i < toolCount; i++)
              {
                'name': 'fake_tool_$i',
                'description': 'fake tool $i',
                'inputSchema': {
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
              },
          ],
        });
      case 'tools/call':
        final params = (message['params'] as Map?)?.cast<String, dynamic>();
        final name = '${params?['name']}';
        final delay = name == slowTool ? slowToolDelay : readDelay;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        _reply(id, {
          'content': [
            {'type': 'text', 'text': 'ok from $name'},
          ],
          'isError': errorTools.contains(name),
          if (env['FAKE_STRUCTURED'] == '1')
            'structuredContent': {'route': '/home', 'name': name},
        });
      default:
        _replyError(id, -32601, 'Method not found: $method');
    }
  }
}

Duration _ms(String? value) =>
    Duration(milliseconds: int.tryParse(value ?? '') ?? 0);

void _reply(Object id, Map<String, dynamic> result) {
  stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
}

void _replyError(Object id, int code, String message) {
  stdout.writeln(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    }),
  );
}
