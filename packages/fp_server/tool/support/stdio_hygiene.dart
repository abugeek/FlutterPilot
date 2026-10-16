// Stdout hygiene and bounded stderr for raw stdio clients (task 03, reused by
// the task-09 startup benchmark).
//
// A conforming MCP server writes **only** JSON-RPC objects to stdout, one per
// line; anything else — a banner, a log line, a stray scalar, an object with no
// `jsonrpc`, or one carrying none of `method`/`result`/`error` — desynchronises
// a client that reads stdout as a protocol stream. The old client silently
// discarded such lines, so the requirement "the server never writes non-JSON to
// stdout" was a comment, not an assertion. This records every violation so a
// caller can fail on it.
//
// One nuance: a `-32700 Parse error` / `-32600 Invalid Request` reply may carry
// no `id` member at all. The spec says such a response's `id` is `null`, while
// mcp_dart omits the member rather than emitting `null`. A `jsonrpc`-versioned
// object carrying `error` is still unmistakably a protocol message, so it is
// accepted; the detector exists to catch banners and non-protocol junk, not to
// police every optional-member nuance of the SDK.
//
// Development-tool support, not shipped code. The raw suite imports it through
// `test/support/stdout_hygiene.dart`; the benchmark imports it directly.
library;

import 'dart:convert';

/// Collects protocol-hygiene violations from a server's stdout.
class StdoutHygiene {
  /// Lines that were not JSON at all (the classic "a banner crept onto
  /// stdout").
  final List<String> nonJson = [];

  /// Lines that parsed as JSON but are not a well-formed JSON-RPC 2.0 message
  /// (a scalar/array, a missing `jsonrpc`, or an object carrying none of
  /// `method`/`result`/`error`).
  final List<String> notProtocol = [];

  /// Total non-empty lines seen.
  int get lines => _lines;
  int _lines = 0;

  /// True when every non-empty line was a well-formed JSON-RPC 2.0 message.
  bool get clean => nonJson.isEmpty && notProtocol.isEmpty;

  /// A short reason for a failure, or null when clean.
  String? get problem {
    if (clean) return null;
    return '${nonJson.length} non-JSON stdout line(s), '
        '${notProtocol.length} malformed JSON-RPC line(s)';
  }

  /// Records one raw stdout line and returns the decoded message when it is a
  /// well-formed JSON-RPC 2.0 object, or null when it is a violation.
  Map<String, dynamic>? add(String line) {
    final text = line.trim();
    if (text.isEmpty) return null; // Blank lines are not a violation.
    _lines++;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      nonJson.add(text);
      return null;
    }
    if (decoded is! Map) {
      notProtocol.add(text);
      return null;
    }
    final message = decoded.cast<String, dynamic>();
    if (message['jsonrpc'] != '2.0') {
      notProtocol.add(text);
      return null;
    }
    final hasMethod = message['method'] is String;
    final hasResult = message.containsKey('result');
    final hasError = message.containsKey('error');
    if (!hasMethod && !hasResult && !hasError) {
      notProtocol.add(text);
      return null;
    }
    return message;
  }
}

/// A bounded, redacted copy of a server's stderr.
///
/// The raw suite keeps stderr out of the protocol assertions but must still be
/// able to report *why* a server misbehaved. Long token-shaped runs are
/// replaced so a diagnostic dump cannot leak a credential.
class BoundedStderr {
  BoundedStderr({this.maxLines = 200, this.maxLineLength = 400});
  final int maxLines;
  final int maxLineLength;
  final List<String> lines = [];
  int totalLines = 0;
  bool get truncated => totalLines > lines.length;

  void add(String line) {
    totalLines++;
    if (lines.length >= maxLines) return;
    lines.add(redact(line, maxLineLength: maxLineLength));
  }

  /// Replaces anything that looks like a bearer token, API key or provider
  /// secret with a fixed marker, and bounds the line length.
  static String redact(String line, {int maxLineLength = 400}) {
    var out = line;
    out = out.replaceAll(RegExp(r'sk-[A-Za-z0-9]{16,}'), '[redacted]');
    out = out.replaceAll(RegExp(r'ghp_[A-Za-z0-9]{20,}'), '[redacted]');
    out = out.replaceAll(RegExp(r'AKIA[0-9A-Z]{16}'), '[redacted]');
    out = out.replaceAllMapped(
      RegExp(r'(authorization:\s*bearer\s+)\S+', caseSensitive: false),
      (match) => '${match.group(1)}[redacted]',
    );
    out = out.replaceAllMapped(
      RegExp(
        r'(["\x27]?(?:api[_-]?key|token|secret|password)["\x27]?\s*[:=]\s*)'
        r'["\x27]?[A-Za-z0-9_\-\.]{12,}',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[redacted]',
    );
    if (out.length > maxLineLength) {
      out = '${out.substring(0, maxLineLength - 3)}...';
    }
    return out;
  }
}
