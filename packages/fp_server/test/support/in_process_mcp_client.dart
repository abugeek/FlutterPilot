// A minimal in-process MCP client, shared by the tests that need to drive a
// real [FlutterPilotServer] over a transport without spawning a subprocess
// (task 09 startup ordering, task 07 output schemas).
import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

/// Drives a server over an [IOStreamTransport] pipe: newline-delimited JSON in,
/// the same out. Enough for `initialize`, `tools/list` and `tools/call`.
class InProcessMcpClient {
  final _toServer = StreamController<List<int>>();
  final _fromServer = StreamController<List<int>>();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  late final IOStreamTransport transport;
  StreamSubscription<String>? _subscription;
  int _nextId = 0;

  InProcessMcpClient() {
    transport = IOStreamTransport(
      stream: _toServer.stream,
      sink: _fromServer.sink,
    );
    _subscription = _fromServer.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final decoded = jsonDecode(line) as Map<String, dynamic>;
    final id = decoded['id'];
    if (id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(decoded);
      return;
    }
    // A request from the server (roots/list): answer it so it is not left
    // waiting, exactly as a real client would.
    if (decoded.containsKey('method') && id != null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'roots': <Object>[]},
      });
    }
  }

  void _send(Map<String, dynamic> message) =>
      _toServer.add(utf8.encode('${jsonEncode(message)}\n'));

  /// Sends a notification (no id, no response expected).
  void notify(String method) => _send({'jsonrpc': '2.0', 'method': method});

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return completer.future.timeout(const Duration(seconds: 10));
  }

  /// Completes the `initialize` handshake the way a client must.
  Future<Map<String, dynamic>> initialize() async {
    final response = await request('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': {'roots': <String, dynamic>{}},
      'clientInfo': {'name': 'fp-in-process-test', 'version': '1.0.0'},
    });
    notify('notifications/initialized');
    return response;
  }

  /// Calls [name] and returns the whole `tools/call` response.
  Future<Map<String, dynamic>> callTool(
    String name, [
    Map<String, dynamic>? arguments,
  ]) => request('tools/call', {
    'name': name,
    'arguments': arguments ?? <String, dynamic>{},
  });

  /// The first text block of a `tools/call` response.
  static String textOf(Map<String, dynamic> response) =>
      ((response['result'] as Map)['content'] as List).first['text'] as String;

  /// The structured content of a `tools/call` response, or null.
  static Map<String, dynamic>? structuredOf(Map<String, dynamic> response) {
    final structured = (response['result'] as Map)['structuredContent'];
    return structured is Map ? Map<String, dynamic>.from(structured) : null;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _toServer.close();
    await _fromServer.close();
  }
}
