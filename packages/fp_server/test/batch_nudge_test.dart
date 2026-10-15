import 'package:fp_server/src/batch_nudge.dart';
import 'package:test/test.dart';

void main() {
  test('the third single step in a row gets the tip, once', () {
    final nudge = BatchNudge();
    expect(nudge.after('tap_widget', isError: false), isNull);
    expect(nudge.after('wait_for', isError: false), isNull);
    final tip = nudge.after('tap_widget', isError: false);
    expect(tip, contains('3 single steps in a row'));
    expect(tip, contains('execute_action_chain'));
    expect(nudge.after('tap_widget', isError: false), isNull);
  });

  test('looking at the app or batching ends the run', () {
    final nudge = BatchNudge();
    nudge.after('tap_widget', isError: false);
    nudge.after('tap_widget', isError: false);
    expect(nudge.after('capture_screenshot', isError: false), isNull);
    expect(nudge.after('tap_widget', isError: false), isNull);
    nudge.after('tap_widget', isError: false);
    expect(nudge.after('execute_action_chain', isError: false), isNull);
    expect(nudge.after('tap_widget', isError: false), isNull);
  });

  test('a failed step ends the run', () {
    final nudge = BatchNudge();
    nudge.after('tap_widget', isError: false);
    nudge.after('tap_widget', isError: false);
    expect(nudge.after('tap_widget', isError: true), isNull);
    expect(nudge.after('tap_widget', isError: false), isNull);
  });

  test('a long run is reminded again, not on every call', () {
    final nudge = BatchNudge();
    final tips = [
      for (var i = 1; i <= 30; i++)
        if (nudge.after('tap_widget', isError: false) != null) i,
    ];
    expect(tips, [3, 15, 27]);
  });
}
