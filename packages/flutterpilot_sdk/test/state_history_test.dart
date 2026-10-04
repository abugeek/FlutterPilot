import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_sdk/src/state_history.dart';

void main() {
  setUp(StateHistory.reset);

  test('a value is recorded with the one it replaced', () {
    FlutterPilot.logStateChange('riverpod', 'cart', 0);
    FlutterPilot.logStateChange('riverpod', 'cart', 3);
    FlutterPilot.logStateChange('navigation', 'push', '/cart');
    FlutterPilot.logStateDisposed('riverpod', 'cart');
    FlutterPilot.logStateChange('riverpod', 'cart', 0);

    final e = StateHistory.entries;
    expect(e.map((c) => '${c['name']} ${c['from']} ${c['to']}'), [
      'cart null 0',
      'cart 0 3',
      'push null /cart',
      'cart 3 null',
      // Recreated after the dispose: it does not continue from 3.
      'cart null 0',
    ]);
    expect(e[3]['disposed'], isTrue);
    expect(e.every((c) => c['at'] is String), isTrue);
  });

  test('credentials stay out; long values are cut', () {
    FlutterPilot.logStateChange('riverpod', 'authTokenProvider', 'eyJabc');
    FlutterPilot.logStateChange('bloc', 'Session', 'user password=hunter2');
    FlutterPilot.logStateChange('bloc', 'Feed', 'x' * 500);
    final e = StateHistory.entries;
    expect(e[0]['to'], '<redacted>');
    expect(e[1]['to'], isNot(contains('hunter2')));
    expect((e[2]['to'] as String).length, lessThan(170));
  });

  test('only the newest changes are kept, the rest counted', () {
    for (var i = 0; i < StateHistory.maxEntries + 7; i++) {
      FlutterPilot.logStateChange('riverpod', 'counter', i);
    }
    expect(StateHistory.entries.length, StateHistory.maxEntries);
    expect(StateHistory.dropped, 7);
    expect(StateHistory.entries.last['to'], '${StateHistory.maxEntries + 6}');

    StateHistory.clear();
    expect(StateHistory.entries, isEmpty);
    // The next change still knows what it replaces.
    FlutterPilot.logStateChange('riverpod', 'counter', 99);
    expect(
      StateHistory.entries.single['from'],
      '${StateHistory.maxEntries + 6}',
    );
  });
}
