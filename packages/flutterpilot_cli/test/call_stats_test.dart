import 'dart:convert';

import 'package:flutterpilot_cli/src/call_stats.dart';
import 'package:test/test.dart';

void main() {
  String call(
    String tool, {
    int s = 1,
    int ms = 100,
    int chars = 500,
    String? err,
  }) => jsonEncode({
    't': '2026-10-11T08:00:00.000Z',
    's': s,
    'tool': tool,
    'ms': ms,
    'chars': chars,
    'err': ?err,
  });

  String listed(List<String> tools, {int s = 1}) =>
      jsonEncode({'t': '2026-10-11T08:00:00.000Z', 's': s, 'listed': tools});

  test('an empty or torn log is not an error', () {
    expect(callStatsReport(const []), 'No tool calls logged yet.');
    expect(callStatsReport(['{"tool": "tap_wid']), 'No tool calls logged yet.');
  });

  test('tools, failures and what follows what', () {
    final report = callStatsReport([
      call('get_app_summary'),
      call('tap_widget', ms: 200),
      call('tap_widget', ms: 400, err: 'Widget not found matching: "…".'),
      call('capture_screenshot'),
      // Another session: its first call follows nothing.
      call('tap_widget', s: 2),
    ]);
    expect(report, contains('5 tool calls in 2 session(s)'));
    expect(report, matches(RegExp(r'tap_widget\s+3\s+1 failed\s+233 ms')));
    expect(report, contains('1  tap_widget: Widget not found matching: "…".'));
    expect(report, contains('1  tap_widget -> tap_widget'));
    expect(report, isNot(contains('capture_screenshot -> tap_widget')));
  });

  test('single steps in a row are pointed out', () {
    final report = callStatsReport([
      for (var i = 0; i < 12; i++) call('tap_widget'),
      call('execute_action_chain'),
    ]);
    expect(report, contains('Worth a look:'));
    expect(report, contains('11 times one single step followed another'));
  });

  test('relaunching more than reloading is pointed out', () {
    final report = callStatsReport([
      for (var i = 0; i < 4; i++) call('launch_app'),
      call('hot_reload'),
    ]);
    expect(report, contains('4 launch_app calls against 1 hot_reload'));
  });

  test('a log without a listed line shows no never-called section', () {
    final report = callStatsReport([call('tap_widget')]);
    expect(report, isNot(contains('never called')));
  });

  test('listed tools that were never called are named', () {
    final report = callStatsReport([
      listed(['tap_widget', 'generate_test', 'scenario']),
      call('tap_widget'),
    ]);
    expect(report, contains('Listed but never called (2):'));
    final lines = report.split('\n');
    final start = lines.indexWhere(
      (l) => l.startsWith('Listed but never called'),
    );
    expect(lines.sublist(start + 1), ['  generate_test', '  scenario']);
  });

  test('never-called tools sort by list bytes when they are known', () {
    final report = statsTextFor(
      [
        StatsLog('', [
          listed(['hot_reload', 'tap_widget']),
          call('other'),
        ]),
      ],
      listBytes: {'hot_reload': 651, 'tap_widget': 1438},
    );
    final lines = report.split('\n');
    final start = lines.indexWhere(
      (l) => l.startsWith('Listed but never called'),
    );
    expect(lines[start + 1], startsWith('  tap_widget'));
    expect(lines[start + 2], startsWith('  hot_reload'));
  });

  test('several logs combine and keep their sessions apart', () {
    final report = statsTextFor([
      StatsLog('a.jsonl', [call('tap_widget', s: 7)]),
      StatsLog('b.jsonl', [call('tap_widget', s: 7), call('press_key', s: 7)]),
    ]);
    expect(report, contains('3 tool calls in 2 session(s)'));
    expect(report, contains('Logs: a.jsonl, b.jsonl.'));
    // The same pid in two logs is two sessions: no pair spans them.
    expect(report, isNot(contains('tap_widget -> tap_widget')));
    expect(report, contains('1  tap_widget -> press_key'));
  });

  test('median and p90 size are reported next to the average', () {
    final report = callStatsReport([
      for (final chars in [100, 100, 100, 100, 40000])
        call('get_widget_tree', chars: chars),
    ]);
    // The average (8080) is dragged by the one 40 KB response; p50 is 100.
    expect(report, matches(RegExp(r'8080 chars\s+p50\s+100\s+p90\s+40000')));
  });

  test('--json carries the same data', () {
    final json =
        jsonDecode(
              statsJsonFor([
                StatsLog('a.jsonl', [
                  listed(['tap_widget', 'generate_test']),
                  call('tap_widget', ms: 50, chars: 100),
                ]),
              ]),
            )
            as Map<String, dynamic>;
    expect(json['calls'], 1);
    expect(json['sessions'], 1);
    expect(json['logs'], ['a.jsonl']);
    final tool = (json['tools'] as List).single as Map;
    expect(tool, containsPair('tool', 'tap_widget'));
    expect(tool, containsPair('charsP50', 100));
    expect(tool, containsPair('charsP90', 100));
    expect(json['neverCalled'], [
      {'tool': 'generate_test'},
    ]);
    expect(json['listedSets'], [
      {
        'session': '0:1',
        'tools': ['tap_widget', 'generate_test'],
      },
    ]);
  });
}
