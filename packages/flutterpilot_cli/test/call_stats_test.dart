import 'dart:convert';

import 'package:flutterpilot_cli/src/call_stats.dart';
import 'package:test/test.dart';

void main() {
  String call(String tool, {int s = 1, int ms = 100, String? err}) =>
      jsonEncode({
        't': '2026-10-11T08:00:00.000Z',
        's': s,
        'tool': tool,
        'ms': ms,
        'chars': 500,
        'err': ?err,
      });

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
}
