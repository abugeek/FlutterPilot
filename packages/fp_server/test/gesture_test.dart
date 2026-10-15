import 'package:fp_server/src/gesture.dart';
import 'package:test/test.dart';

/// `gesture_widget` merged five single-gesture tools (task 04). These are the
/// reasons a merged tool is only as easy to use as the separate ones: the mode
/// has to be named, and its arguments must not be ignored in another mode.
void main() {
  group('gesture_widget request', () {
    test('each mode needs its own arguments', () {
      expect(gestureRequestError({'gesture': 'swipe'}), contains('direction'));
      expect(
        gestureRequestError({'gesture': 'drag', 'fromKey': 'a'}),
        contains('toKey'),
      );
      expect(gestureRequestError({'gesture': 'pinch'}), contains('scale'));
      expect(gestureRequestError({'gesture': 'slide'}), contains('value'));
      // focus works on the focused field, or unfocuses everything.
      expect(gestureRequestError({'gesture': 'focus'}), isNull);
    });

    test('a valid call for every mode passes', () {
      expect(
        gestureRequestError({'gesture': 'swipe', 'direction': 'down'}),
        isNull,
      );
      expect(
        gestureRequestError({'gesture': 'drag', 'fromKey': 'a', 'toKey': 'b'}),
        isNull,
      );
      expect(gestureRequestError({'gesture': 'pinch', 'scale': 2.0}), isNull);
      expect(gestureRequestError({'gesture': 'slide', 'value': 5}), isNull);
      expect(gestureRequestError({'gesture': 'focus', 'key': 'field'}), isNull);
    });

    test('a mode-only argument passed with another mode is refused', () {
      expect(
        gestureRequestError({
          'gesture': 'pinch',
          'scale': 2.0,
          'direction': 'up',
        }),
        allOf(contains('direction'), contains('swipe'), contains('pinch')),
      );
      expect(
        gestureRequestError({
          'gesture': 'swipe',
          'direction': 'down',
          'value': 5,
        }),
        allOf(contains('value'), contains('slide')),
      );
    });

    test('an unknown or missing gesture names the modes', () {
      expect(gestureRequestError(const {}), contains('gesture must be one of'));
      expect(
        gestureRequestError({'gesture': 'tap'}),
        allOf(contains('got "tap"'), contains('swipe')),
      );
    });
  });
}
