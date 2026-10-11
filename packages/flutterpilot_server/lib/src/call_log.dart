import 'dart:convert';
import 'dart:io';

/// One line per tool call an agent made, in the app's `.dart_tool`, for
/// `flutterpilot stats`: which tools are called, how long they take, how
/// they fail and what follows what. The findings that shaped launch_app and
/// wait_for's response came from reading agent transcripts by hand; this
/// keeps the same numbers for any project.
///
/// Only the tool's name, time, size and a failure's kind are kept: no
/// arguments, no result text, nothing the app showed.
class CallLog {
  CallLog(this.file, {this.maxBytes = 2 * 1024 * 1024});

  /// Relative to the app folder.
  static const path = '.dart_tool/flutterpilot_calls.jsonl';

  /// The log in [root], or null when it has no `.dart_tool` (not a Dart
  /// project: nothing is created there).
  static CallLog? inProject(Directory root) =>
      Directory('${root.path}/.dart_tool').existsSync()
      ? CallLog(File('${root.path}/$path'))
      : null;

  final File file;
  final int maxBytes;

  /// One server process is one session: pairs of calls don't span two.
  final int session = pid;

  void record(
    String tool, {
    required int ms,
    required bool isError,
    required int chars,
    String? error,
    DateTime? at,
  }) {
    try {
      if (file.existsSync() && file.lengthSync() > maxBytes) _trim();
      file.writeAsStringSync(
        '${jsonEncode({'t': (at ?? DateTime.now()).toUtc().toIso8601String(), 's': session, 'tool': tool, 'ms': ms, 'chars': chars, if (isError) 'err': failureKind(error ?? '')})}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // A log that can't be written must never fail a tool call.
    }
  }

  /// Keeps the newer half.
  void _trim() {
    final lines = file.readAsLinesSync();
    file.writeAsStringSync('${lines.sublist(lines.length ~/ 2).join('\n')}\n');
  }

  static final _quoted = RegExp('"[^"]*"|(?<![A-Za-z])\'[^\']*\'');
  static final _digits = RegExp(r'\d+');

  /// A failure's message as a kind: its first line, without what the app or
  /// the agent put in it (quoted text, numbers), at most 90 characters.
  /// `Widget not found matching: "Sign Out"` -> `Widget not found matching: "…"`.
  static String failureKind(String message) {
    final line = message
        .split('\n')
        .first
        .replaceAll(_quoted, '"…"')
        .replaceAll(_digits, 'N')
        .trim();
    return line.length > 90 ? '${line.substring(0, 90)}…' : line;
  }
}
