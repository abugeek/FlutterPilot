/// Merges the console lines the SDK buffered before FlutterPilot connected
/// into the server's own capture (field test #329).
///
/// The server starts capturing the app's stdout when it connects; the SDK
/// captures `debugPrint` from app start. So a startup line shows in
/// `get_app_summary` — its "Recent Console Logs" read the SDK's buffer — and
/// not in `get_debug_logs`, which reads the server's, and an agent seeing two
/// tools disagree about the same logs distrusts both.
///
/// [sdkLogs] are the SDK's newest lines (its app snapshot exposes the newest
/// 15; its ring buffer holds 500) and [serverLogs] what the server captured,
/// oldest first. A line the server already has is dropped: the two buffers
/// describe the same line differently — the server sees the app's stdout
/// (logger `stdout`, a `flutter: ` prefix) where the SDK captured the call
/// (logger `debugPrint`) — so equality ignores the logger and that prefix.
/// Everything not older than the server's oldest line came after the
/// connection and is the server's own.
List<Map<String, dynamic>> preConnectionLogs({
  required List<Map<String, dynamic>> sdkLogs,
  required List<Map<String, dynamic>> serverLogs,
}) {
  if (sdkLogs.isEmpty) return const [];
  String key(Object? level, Object? message) =>
      '$level\u0000${withoutStdoutPrefix('$message')}';
  // Against the server's lines only: two identical pre-connection lines stay
  // two lines, which the tool's own repeat compaction reports as
  // "[x2 occurrences]".
  final seen = serverLogs.map((e) => key(e['level'], e['message'])).toSet();
  final oldestServer = serverLogs.isEmpty
      ? null
      : DateTime.tryParse('${serverLogs.first['timestamp']}');
  final preConnection = <Map<String, dynamic>>[];
  for (final raw in sdkLogs) {
    final entry = Map<String, dynamic>.from(raw);
    final at = DateTime.tryParse('${entry['timestamp']}');
    // A line the server cannot have captured: what is older than the oldest
    // line it saw. An entry that cannot be dated is left out rather than
    // guessed at.
    if (oldestServer != null && (at == null || !at.isBefore(oldestServer))) {
      continue;
    }
    if (seen.contains(key(entry['level'], entry['message']))) continue;
    preConnection.add(entry);
  }
  return preConnection;
}

/// `print()` reaches the server as `flutter: <line>`; the SDK buffered the
/// same line without that prefix.
String withoutStdoutPrefix(String message) {
  final text = message.trim();
  return text.startsWith('flutter: ') ? text.substring(9) : text;
}
