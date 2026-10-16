// An intentionally noisy stdio "server" for `test/stdout_hygiene_test.dart`.
//
// It answers a bare `initialize` correctly, prints a banner on stdout that a
// real server must never print, and can also emit a non-JSON reply and a
// malformed JSON-RPC object on demand — so the detector is proven against a
// live subprocess, not only synthesized strings.
//
// Test support, not shipped code.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  // The violation a sloppy server writes before the handshake.
  stdout.writeln('FlutterPilot starting up — not JSON-RPC, but on stdout');

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic>? message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) message = decoded.cast<String, dynamic>();
    } on FormatException {
      continue;
    }
    if (message == null) continue;
    final id = message['id'];
    final method = message['method'];
    switch (method) {
      case 'initialize':
        stdout.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'protocolVersion': '2025-11-25'},
          }),
        );
      case 'noisy/nonJson':
        stdout.writeln('a log line, not JSON');
        stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': {}}));
      case 'noisy/notProtocol':
        stdout.writeln(jsonEncode({'id': id, 'result': {}}));
      default:
        stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': {}}));
    }
  }
}
