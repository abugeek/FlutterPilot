import 'dart:convert';

/// The report `flutterpilot stats` prints from the server's call log
/// (`.dart_tool/flutterpilot_calls.jsonl`, one JSON object per tool call:
/// `t` time, `s` session, `tool`, `ms`, `chars`, `err` kind of failure).
String callStatsReport(Iterable<String> lines, {int top = 12}) {
  final calls = <_Call>[];
  for (final line in lines) {
    try {
      final json = jsonDecode(line);
      if (json is Map && json['tool'] is String) calls.add(_Call(json));
    } catch (_) {
      // A torn last line (the server was killed mid-write).
    }
  }
  if (calls.isEmpty) return 'No tool calls logged yet.';

  final byTool = <String, List<_Call>>{};
  final failures = <String, int>{};
  final pairs = <String, int>{};
  final sessions = <Object?>{};
  _Call? previous;
  for (final call in calls) {
    byTool.putIfAbsent(call.tool, () => []).add(call);
    sessions.add(call.session);
    final err = call.error;
    if (err != null) {
      failures.update('${call.tool}: $err', (n) => n + 1, ifAbsent: () => 1);
    }
    if (previous != null && previous.session == call.session) {
      pairs.update(
        '${previous.tool} -> ${call.tool}',
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    previous = call;
  }

  final out = StringBuffer()
    ..writeln(
      '${calls.length} tool calls in ${sessions.length} session(s), '
      '${_day(calls.first.time)} to ${_day(calls.last.time)}.',
    )
    ..writeln()
    ..writeln('Tools (calls, failed, average time, average size):');
  final tools = byTool.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final MapEntry(key: tool, value: list) in tools.take(top)) {
    final failed = list.where((c) => c.error != null).length;
    out.writeln(
      '  ${tool.padRight(26)} ${'${list.length}'.padLeft(5)}  '
      '${'$failed'.padLeft(4)} failed  '
      '${_avg(list.map((c) => c.ms)).toString().padLeft(6)} ms  '
      '${_avg(list.map((c) => c.chars)).toString().padLeft(6)} chars',
    );
  }
  if (tools.length > top) out.writeln('  … ${tools.length - top} more tools');

  if (failures.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Most common failures:');
    for (final e in _top(failures, 8)) {
      out.writeln('  ${'${e.value}'.padLeft(4)}  ${e.key}');
    }
  }

  out
    ..writeln()
    ..writeln('What follows what:');
  for (final e in _top(pairs, 8)) {
    out.writeln('  ${'${e.value}'.padLeft(4)}  ${e.key}');
  }

  final hints = _hints(byTool, pairs);
  if (hints.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Worth a look:');
    for (final hint in hints) {
      out.writeln('  - $hint');
    }
  }
  return out.toString().trimRight();
}

/// Steps execute_action_chain can take in one call.
const _singleSteps = {
  'tap_widget',
  'enter_text',
  'press_key',
  'toggle_checkbox',
  'scroll_into_view',
  'wait_for',
  'assert_widget',
};

List<String> _hints(Map<String, List<_Call>> byTool, Map<String, int> pairs) {
  int count(String tool) => byTool[tool]?.length ?? 0;
  int pair(String a, String b) => pairs['$a -> $b'] ?? 0;
  final hints = <String>[];

  var singlePairs = 0;
  for (final MapEntry(key: name, value: n) in pairs.entries) {
    final parts = name.split(' -> ');
    if (_singleSteps.contains(parts[0]) && _singleSteps.contains(parts[1])) {
      singlePairs += n;
    }
  }
  final batched = count('execute_action_chain') + count('fill_form');
  if (singlePairs >= 10 && singlePairs > batched * 2) {
    hints.add(
      '$singlePairs times one single step followed another, against '
      '$batched batched calls (execute_action_chain, fill_form): known '
      'sequences can go in one call.',
    );
  }
  final shots =
      pair('tap_widget', 'capture_screenshot') +
      pair('enter_text', 'capture_screenshot');
  if (shots >= 5) {
    hints.add(
      '$shots screenshots right after an action: its response already '
      'lists the route, the widget diff and what is tappable.',
    );
  }
  final launches = count('launch_app');
  if (launches >= 3 && launches > count('hot_reload')) {
    hints.add(
      '$launches launch_app calls against ${count('hot_reload')} hot_reload: '
      'a hot restart loads every Dart change in about a second.',
    );
  }
  for (final MapEntry(key: tool, value: list) in byTool.entries) {
    final failed = list.where((c) => c.error != null).length;
    if (list.length >= 10 && failed * 5 >= list.length) {
      hints.add(
        '$tool failed $failed of ${list.length} times: see its failures above.',
      );
    }
  }
  return hints;
}

Iterable<MapEntry<String, int>> _top(Map<String, int> counts, int n) =>
    (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(
      n,
    );

int _avg(Iterable<int> values) => values.isEmpty
    ? 0
    : (values.reduce((a, b) => a + b) / values.length).round();

String _day(String time) => time.length >= 10 ? time.substring(0, 10) : time;

class _Call {
  _Call(Map json)
    : tool = json['tool'] as String,
      session = json['s'],
      time = '${json['t'] ?? ''}',
      ms = (json['ms'] as num?)?.toInt() ?? 0,
      chars = (json['chars'] as num?)?.toInt() ?? 0,
      error = json['err'] as String?;

  final String tool;
  final Object? session;
  final String time;
  final int ms;
  final int chars;
  final String? error;
}
