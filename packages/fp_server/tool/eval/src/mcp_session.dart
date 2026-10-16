// The MCP side of the eval runner: one stdio session to a FlutterPilot server,
// held the way a client holds it (this mirrors tool/fp_bridge.dart). The runner
// uses the same connection for its own reset calls and for the model's calls,
// so the tool list the model sees is the one the server really has.
//
// Hardened for task 04 §8: the negotiated protocol and server identity are
// kept, `structuredContent` is preserved, a non-protocol stdout line fails the
// session instead of being silently dropped, a pending request is rejected when
// the process exits, response bodies are bounded, and close is deterministic
// (stdin, wait, then a process-tree kill).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fp_server/src/tool_list_bytes.dart';

import '../../support/process_tree.dart';
import '../../support/stdio_hygiene.dart';

/// The client surface the agent runner needs. [McpSession] is the real one;
/// tests use a fake.
abstract class McpClient {
  /// The server's `initialize` instructions, or '' when it sent none.
  String get instructions;

  /// The live `tools/list`.
  List<McpTool> get tools;

  /// Fires with the new list after `notifications/tools/list_changed`.
  Stream<List<McpTool>> get toolListChanges;

  Future<McpCallResult> call(String name, [Map<String, dynamic>? arguments]);
}

class McpException implements Exception {
  McpException(this.message);
  final String message;
  @override
  String toString() => 'McpException: $message';
}

/// One tool as `tools/list` reports it.
class McpTool {
  McpTool(this.raw);
  final Map<String, dynamic> raw;

  String get name => '${raw['name']}';
  String get description => '${raw['description'] ?? ''}';
  Map<String, dynamic> get inputSchema =>
      (raw['inputSchema'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// The characters an agent pays for this tool, the same legacy measure the
  /// registration test budgets (`toolListChars`, task 00). Shared with the
  /// server so the two can't drift.
  int get listChars => toolListChars(raw);

  /// The UTF-8 bytes of the same model-facing projection.
  int get listUtf8Bytes => toolListUtf8Bytes(raw);
}

/// The result of one `tools/call`.
class McpCallResult {
  McpCallResult(
    this.content,
    this.isError,
    this.milliseconds,
    this.chars, {
    this.structured,
  });

  final List<Map<String, dynamic>> content;
  final bool isError;
  final int milliseconds;
  final int chars;

  /// The result's `structuredContent`, when the server sent one (task 04 §5).
  final Map<String, dynamic>? structured;

  String get text => content
      .where((c) => c['type'] == 'text')
      .map((c) => '${c['text'] ?? ''}')
      .join('\n')
      .trim();
}

class McpSession implements McpClient {
  McpSession._(this._process, this._closed, this.maxResultChars);

  final Process _process;
  final Completer<void> _closed;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<List<McpTool>> _toolChanges =
      StreamController<List<McpTool>>.broadcast();
  final StdoutHygiene _hygiene = StdoutHygiene();
  int _nextId = 0;

  /// The largest model-facing tool result kept, in characters. A runaway
  /// response is truncated rather than fed on unbounded (task 04 §9).
  final int maxResultChars;

  /// Set when the session can no longer be used: a non-protocol stdout line or
  /// the process exiting.
  String? _failure;

  @override
  String instructions = '';

  @override
  List<McpTool> tools = const [];

  Map<String, dynamic> serverInfo = const {};

  /// The protocol version the server negotiated in `initialize`, or '' when it
  /// sent none.
  String negotiatedProtocol = '';

  /// Why the session failed, or null while it is usable.
  String? get failure => _failure;

  /// A short reason for any protocol-hygiene violation, or null when clean.
  String? get stdoutProblem => _hygiene.problem;

  /// Starts `dart run <entrypoint> <serverArgs>` in [workingDirectory] and
  /// completes the MCP handshake. `runInShell` is required on Windows, where
  /// `dart` is a `.bat` launcher (task 01 pitfalls).
  static Future<McpSession> start({
    required String entrypoint,
    required List<String> serverArgs,
    required String workingDirectory,
    void Function(String line)? onStderr,
    Map<String, String>? environment,
    int maxResultChars = 200000,
  }) async {
    final process = await Process.start(
      'dart',
      ['run', entrypoint, ...serverArgs],
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );
    final closed = Completer<void>();
    final session = McpSession._(process, closed, maxResultChars);
    process.exitCode.then((code) {
      if (!closed.isCompleted) closed.complete();
      session._fail('the server exited (code $code) before answering');
    });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onStderr ?? (_) {});
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(session._onLine);

    try {
      final init = await session._rpc('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'flutterpilot-eval', 'version': '2'},
      });
      if (init['error'] != null) {
        throw McpException('initialize failed: ${jsonEncode(init['error'])}');
      }
      final result =
          (init['result'] as Map?)?.cast<String, dynamic>() ?? const {};
      session.instructions = '${result['instructions'] ?? ''}';
      session.serverInfo =
          (result['serverInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
      session.negotiatedProtocol = '${result['protocolVersion'] ?? ''}';
      process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );
      await session.refreshTools();
      return session;
    } catch (_) {
      // A failed handshake must not leave the child running.
      await killProcessTree(process);
      rethrow;
    }
  }

  @override
  Stream<List<McpTool>> get toolListChanges => _toolChanges.stream;

  /// Total list cost, the same legacy character measure the registration test
  /// budgets ([toolListChars]).
  int get toolListChars => tools.fold(0, (sum, tool) => sum + tool.listChars);

  /// Total list cost in UTF-8 bytes of the model-facing projection.
  int get toolListUtf8Bytes =>
      tools.fold(0, (sum, tool) => sum + tool.listUtf8Bytes);

  void _onLine(String line) {
    final message = _hygiene.add(line);
    if (message == null) {
      if (line.trim().isEmpty) return;
      // A server must write only JSON-RPC to stdout. Fail rather than
      // desynchronise silently (task 04 §8); the reason is redacted.
      _fail(
        'the server wrote non-protocol data to stdout: '
        '${_short(BoundedStderr.redact(line))}',
      );
      return;
    }
    final id = message['id'];
    if (id is int) {
      _pending.remove(id)?.complete(message);
      return;
    }
    if (message['method'] == 'notifications/tools/list_changed') {
      // The list changes after the server finds the app and reads its plugins.
      unawaited(refreshTools().catchError((_) => <McpTool>[]));
    }
  }

  /// Marks the session unusable and rejects every pending request (task 04 §8).
  void _fail(String reason) {
    _failure ??= reason;
    if (_pending.isEmpty) return;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(McpException(reason));
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(minutes: 5),
  ]) async {
    if (_failure != null) throw McpException(_failure!);
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw McpException('$method did not answer within $timeout');
    }
  }

  /// Re-reads `tools/list` and tells listeners about the new list.
  Future<List<McpTool>> refreshTools() async {
    final response = await _rpc('tools/list', const {});
    if (response['error'] != null) {
      throw McpException('tools/list failed: ${jsonEncode(response['error'])}');
    }
    final result =
        (response['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    tools = [
      for (final tool in (result['tools'] as List? ?? const []))
        McpTool((tool as Map).cast<String, dynamic>()),
    ];
    _toolChanges.add(tools);
    return tools;
  }

  @override
  Future<McpCallResult> call(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    final stopwatch = Stopwatch()..start();
    final response = await _rpc('tools/call', {
      'name': name,
      'arguments': arguments ?? const <String, dynamic>{},
    });
    stopwatch.stop();
    final error = response['error'];
    if (error != null) {
      final block = <String, dynamic>{
        'type': 'text',
        'text': 'RPC ERROR: ${jsonEncode(error)}',
      };
      return McpCallResult(
        [block],
        true,
        stopwatch.elapsedMilliseconds,
        '${block['text']}'.length,
      );
    }
    final result =
        (response['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    final content = _bound([
      for (final block in (result['content'] as List? ?? const []))
        (block as Map).cast<String, dynamic>(),
    ]);
    final chars = content.fold<int>(0, (sum, c) => sum + jsonEncode(c).length);
    return McpCallResult(
      content,
      result['isError'] == true,
      stopwatch.elapsedMilliseconds,
      chars,
      structured: (result['structuredContent'] as Map?)
          ?.cast<String, dynamic>(),
    );
  }

  /// Keeps the model-facing content within [maxResultChars]: text blocks are
  /// truncated with a marker, other block kinds are replaced by a note once the
  /// bound is reached.
  List<Map<String, dynamic>> _bound(List<Map<String, dynamic>> content) {
    var remaining = maxResultChars;
    final out = <Map<String, dynamic>>[];
    for (final block in content) {
      final size = jsonEncode(block).length;
      if (size <= remaining) {
        out.add(block);
        remaining -= size;
        continue;
      }
      if (block['type'] == 'text') {
        final text = '${block['text'] ?? ''}';
        final keep = remaining > 40 ? remaining - 20 : 0;
        out.add({
          ...block,
          'text': keep >= text.length
              ? text
              : '${text.substring(0, keep)}\n…[truncated '
                    '${text.length - keep} chars]',
        });
      } else {
        out.add({
          'type': 'text',
          'text': '[${block['type']} omitted: response bound reached]',
        });
      }
      remaining = 0;
    }
    return out;
  }

  /// Closes deterministically: stdin, a bounded wait, then a process-tree kill.
  Future<void> close() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    if (!_closed.isCompleted) {
      await _closed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    }
    if (!_closed.isCompleted) {
      await killProcessTree(_process);
      await _closed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    }
    _fail('session closed');
    await _toolChanges.close();
  }

  String _short(String text) =>
      text.length <= 200 ? text : '${text.substring(0, 200)}…';
}
