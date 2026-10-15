import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/retired_tools.dart';
import 'package:test/test.dart';

/// A merged tool (task 04) keeps its old name working inside the step runners
/// (`execute_action_chain`, `run_on_devices`, `profile_action`, a leak
/// `cycle`): an agent's memory or a saved scenario shouldn't stop meaning
/// something.
void main() {
  test('a step naming a merged tool runs the new tool with its mode', () {
    final swipe = translateRetiredStep('swipe_widget', {
      'key': 'Row 0',
      'direction': 'down',
    });
    expect(swipe.tool, 'gesture_widget');
    expect(swipe.arguments, {
      'gesture': 'swipe',
      'key': 'Row 0',
      'direction': 'down',
    });
    final slide = translateRetiredStep('set_slider_value', {'value': 5});
    expect(slide.tool, 'gesture_widget');
    expect(slide.arguments, {'gesture': 'slide', 'value': 5});
  });

  test('an argument the caller passed wins over the mode', () {
    final step = translateRetiredStep('focus_widget', {
      'key': 'field',
      'gesture': 'pinch',
    });
    expect(step.arguments['gesture'], 'pinch');
    expect(step.arguments['key'], 'field');
  });

  test('a tool that was not merged is left alone', () {
    final step = translateRetiredStep('tap_widget', {'key': 'x'});
    expect(step.tool, 'tap_widget');
    expect(step.arguments, {'key': 'x'});
  });

  test('every retired tool became a registered tool, and is gone itself', () {
    final names = FlutterPilotServer(
      vmServiceUri: 'ws://localhost:8888',
    ).registeredToolNames.toSet();
    expect(retiredTools, isNotEmpty);
    for (final entry in retiredTools.entries) {
      expect(names, contains(entry.value.tool), reason: entry.key);
      expect(names, isNot(contains(entry.key)), reason: entry.key);
    }
  });
}
