import 'dart:convert';

/// One call log's lines, with the path they came from. `flutterpilot stats`
/// takes several (`[paths...]`, task 03 §C1); sessions stay apart per log.
class StatsLog {
  StatsLog(this.label, this.lines);

  /// The path, printed when several logs are combined.
  final String label;

  final List<String> lines;
}

/// The report `flutterpilot stats` prints from the server's call log
/// (`.dart_tool/flutterpilot_calls.jsonl`): one JSON object per tool call
/// (`t` time, `s` session, `tool`, `ms`, `chars`, `err` kind of failure) and,
/// since task 03, one per listed-set change (`listed`: the tool names the
/// session was offered, names only).
String callStatsReport(Iterable<String> lines, {int top = 12}) =>
    _Report.parse([StatsLog('', lines.toList())], top: top).toText();

/// [callStatsReport] over several logs. [listBytes] sorts the never-called
/// tools by what they cost to list (task 03 §C2); without it they are sorted
/// by name.
String statsTextFor(
  List<StatsLog> logs, {
  int top = 12,
  Map<String, int>? listBytes,
}) => _Report.parse(logs, top: top, listBytes: listBytes).toText();

/// The same data as JSON (`--json`), for task 04 to attach to its PR. Every
/// tool is included here; the text report shows only the [top] busiest. The
/// raw `listedSets` go with it, so a reader can rebuild a stricter
/// "never called" view than the union of every set ever offered.
String statsJsonFor(
  List<StatsLog> logs, {
  int top = 12,
  Map<String, int>? listBytes,
}) => const JsonEncoder.withIndent(
  '  ',
).convert(_Report.parse(logs, top: top, listBytes: listBytes).toJson());

class _Report {
  _Report._({
    required this.calls,
    required this.sessionCount,
    required this.logLabels,
    required this.byTool,
    required this.failures,
    required this.pairs,
    required this.neverCalled,
    required this.listedSets,
    required this.listBytes,
    required this.top,
  });

  factory _Report.parse(
    List<StatsLog> logs, {
    required int top,
    Map<String, int>? listBytes,
  }) {
    final calls = <_Call>[];
    final listed = <String>{};
    final listedSets = <({String session, List<String> tools})>[];
    final sessions = <String>{};
    // A session id is a pid; the same pid in two logs is two sessions, so the
    // log's index goes in front (task 03 §C1).
    for (var i = 0; i < logs.length; i++) {
      for (final line in logs[i].lines) {
        try {
          final json = jsonDecode(line);
          if (json is! Map) continue;
          final session = '$i:${json['s']}';
          if (json['tool'] is String) {
            calls.add(_Call(json, session));
            sessions.add(session);
          } else if (json['listed'] is List) {
            final tools = (json['listed'] as List).whereType<String>().toList();
            listed.addAll(tools);
            listedSets.add((session: session, tools: tools));
          }
        } catch (_) {
          // A torn last line (the server was killed mid-write).
        }
      }
    }

    final byTool = <String, List<_Call>>{};
    final failures = <String, int>{};
    final pairs = <String, int>{};
    _Call? previous;
    for (final call in calls) {
      byTool.putIfAbsent(call.tool, () => []).add(call);
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

    final neverCalled = listed.difference(byTool.keys.toSet()).toList();
    neverCalled.sort(
      listBytes == null
          ? (a, b) => a.compareTo(b)
          : (a, b) {
              final bySize = (listBytes[b] ?? 0).compareTo(listBytes[a] ?? 0);
              return bySize != 0 ? bySize : a.compareTo(b);
            },
    );

    return _Report._(
      calls: calls,
      sessionCount: sessions.length,
      logLabels: [
        for (final log in logs)
          if (log.label.isNotEmpty) log.label,
      ],
      byTool: byTool,
      failures: failures,
      pairs: pairs,
      neverCalled: neverCalled,
      listedSets: listedSets,
      listBytes: listBytes,
      top: top,
    );
  }

  final List<_Call> calls;
  final int sessionCount;
  final List<String> logLabels;
  final Map<String, List<_Call>> byTool;
  final Map<String, int> failures;
  final Map<String, int> pairs;
  final List<String> neverCalled;

  /// Every listed set as written, in order, so a reader can rebuild a
  /// stricter view than the union (a startup line is the list before an app
  /// connects).
  final List<({String session, List<String> tools})> listedSets;

  final Map<String, int>? listBytes;
  final int top;

  List<MapEntry<String, List<_Call>>> get _tools =>
      byTool.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));

  String toText() {
    if (calls.isEmpty) return 'No tool calls logged yet.';

    final out = StringBuffer()
      ..writeln(
        '${calls.length} tool calls in $sessionCount session(s), '
        '${_day(calls.first.time)} to ${_day(calls.last.time)}.',
      );
    if (logLabels.length > 1) out.writeln('Logs: ${logLabels.join(', ')}.');
    out
      ..writeln()
      ..writeln('Tools (calls, failed, average time, size: avg/p50/p90):');

    final tools = _tools;
    for (final MapEntry(key: tool, value: list) in tools.take(top)) {
      final failed = list.where((c) => c.error != null).length;
      final chars = list.map((c) => c.chars).toList();
      out.writeln(
        '  ${tool.padRight(26)} ${'${list.length}'.padLeft(5)}  '
        '${'$failed'.padLeft(4)} failed  '
        '${_avg(list.map((c) => c.ms)).toString().padLeft(6)} ms  '
        '${_avg(chars).toString().padLeft(6)} chars  '
        'p50 ${_percentile(chars, 0.5).toString().padLeft(6)}  '
        'p90 ${_percentile(chars, 0.9).toString().padLeft(6)}',
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

    if (neverCalled.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Listed but never called (${neverCalled.length}):');
      for (final name in neverCalled) {
        final bytes = listBytes?[name];
        out.writeln(
          bytes == null
              ? '  $name'
              : '  ${name.padRight(28)} ${bytes.toString().padLeft(6)} bytes',
        );
      }
    }
    return out.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
    'calls': calls.length,
    'sessions': sessionCount,
    'logs': logLabels,
    'from': calls.isEmpty ? null : _day(calls.first.time),
    'to': calls.isEmpty ? null : _day(calls.last.time),
    'tools': [
      for (final MapEntry(key: tool, value: list) in _tools)
        {
          'tool': tool,
          'calls': list.length,
          'failed': list.where((c) => c.error != null).length,
          'msAvg': _avg(list.map((c) => c.ms)),
          'charsAvg': _avg(list.map((c) => c.chars)),
          'charsP50': _percentile(list.map((c) => c.chars).toList(), 0.5),
          'charsP90': _percentile(list.map((c) => c.chars).toList(), 0.9),
        },
    ],
    'failures': [
      for (final e in _top(failures, 8)) {'kind': e.key, 'count': e.value},
    ],
    'pairs': [
      for (final e in _top(pairs, 8)) {'pair': e.key, 'count': e.value},
    ],
    'neverCalled': [
      for (final name in neverCalled)
        {
          'tool': name,
          if (listBytes?.containsKey(name) ?? false)
            'listBytes': listBytes![name],
        },
    ],
    'listedSets': [
      for (final set in listedSets)
        {'session': set.session, 'tools': set.tools},
    ],
    'hints': _hints(byTool, pairs),
  };
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

/// The [p] quantile (0..1) of [values], nearest rank. Averages hide the one
/// 40 KB `get_widget_tree` (task 03 §C3).
int _percentile(List<int> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * p).round();
  return sorted[index];
}

String _day(String time) => time.length >= 10 ? time.substring(0, 10) : time;

class _Call {
  _Call(Map json, this.session)
    : tool = json['tool'] as String,
      time = '${json['t'] ?? ''}',
      ms = (json['ms'] as num?)?.toInt() ?? 0,
      chars = (json['chars'] as num?)?.toInt() ?? 0,
      error = json['err'] as String?;

  final String tool;
  final String session;
  final String time;
  final int ms;
  final int chars;
  final String? error;
}
