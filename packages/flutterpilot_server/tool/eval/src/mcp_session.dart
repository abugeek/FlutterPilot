// The MCP side of the eval runner: one stdio session to a FlutterPilot server,
// held the way a client holds it (this mirrors tool/fp_bridge.dart). The runner
// uses the same connection for its own reset calls and for the model's calls,
// so the tool list the model sees is the one the server really has.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// The bytes an agent pays for this tool, the same measure as
  /// `tool_registration_test.listBytes`: the tool's JSON without annotations.
  int get listBytes {
    final withoutAnnotations = Map<String, dynamic>.from(raw)
      ..remove('annotations');
    return jsonEncode(withoutAnnotations).length;
  }
}

/// The result of one `tools/call`.
class McpCallResult {
  McpCallResult(this.content, this.isError, this.milliseconds, this.chars);
  final List<Map<String, dynamic>> content;
  final bool isError;
  final int milliseconds;
  final int chars;

  String get text => content
      .where((c) => c['type'] == 'text')
      .map((c) => '${c['text'] ?? ''}')
      .join('\n')
      .trim();
}

class McpSession implements McpClient {
  McpSession._(this._process, this._closed);

  final Process _process;
  final Completer<void> _closed;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<List<McpTool>> _toolChanges =
      StreamController<List<McpTool>>.broadcast();
  int _nextId = 0;

  @override
  String instructions = '';

  @override
  List<McpTool> tools = const [];

  Map<String, dynamic> serverInfo = const {};

  /// Starts `dart run <entrypoint> <serverArgs>` in [workingDirectory] and
  /// completes the MCP handshake. `runInShell` is required on Windows, where
  /// `dart` is a `.bat` launcher (task 01 pitfalls).
  static Future<McpSession> start({
    required String entrypoint,
    required List<String> serverArgs,
    required String workingDirectory,
    void Function(String line)? onStderr,
  }) async {
    final process = await Process.start(
      'dart',
      ['run', entrypoint, ...serverArgs],
      workingDirectory: workingDirectory,
      runInShell: true,
    );
    final closed = Completer<void>();
    process.exitCode.then((_) {
      if (!closed.isCompleted) closed.complete();
    });
    final session = McpSession._(process, closed);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onStderr ?? (_) {});
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(session._onLine);

    final init = await session._rpc('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'flutterpilot-eval', 'version': '1'},
    });
    if (init['error'] != null) {
      throw McpException('initialize failed: ${jsonEncode(init['error'])}');
    }
    final result =
        (init['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    session.instructions = '${result['instructions'] ?? ''}';
    session.serverInfo =
        (result['serverInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
    process.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
    await session.refreshTools();
    return session;
  }

  @override
  Stream<List<McpTool>> get toolListChanges => _toolChanges.stream;

  /// Total list cost, the same measure the registration test budgets.
  int get toolListBytes => tools.fold(0, (sum, tool) => sum + tool.listBytes);

  void _onLine(String line) {
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return; // Not JSON-RPC. Servers should not write this to stdout.
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

  Future<Map<String, dynamic>> _rpc(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(minutes: 5),
  ]) async {
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
    final content = [
      for (final block in (result['content'] as List? ?? const []))
        (block as Map).cast<String, dynamic>(),
    ];
    final chars = content.fold<int>(0, (sum, c) => sum + jsonEncode(c).length);
    return McpCallResult(
      content,
      result['isError'] == true,
      stopwatch.elapsedMilliseconds,
      chars,
    );
  }

  Future<void> close() async {
    await _process.stdin.close();
    _process.kill();
    await _closed.future;
    await _toolChanges.close();
  }
}
