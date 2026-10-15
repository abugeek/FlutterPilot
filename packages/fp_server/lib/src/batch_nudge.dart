/// Notices an agent driving the app one call at a time and says once that
/// the steps can go in one call. In field sessions tap_widget was followed
/// by another tap_widget 152 times and by wait_for 57 times, against 100
/// execute_action_chain calls: each pair is a round trip an agent turn long.
class BatchNudge {
  /// Tools execute_action_chain can run as steps.
  static const singleSteps = {
    'tap_widget',
    'enter_text',
    'press_key',
    'toggle_checkbox',
    'scroll_into_view',
    'wait_for',
    'assert_widget',
  };

  /// The run of single steps that gets the tip, and how many more before it
  /// is said again.
  static const first = 3;
  static const again = 12;

  var _streak = 0;

  /// Call for every tool call an agent makes, in order. Returns the tip to
  /// append to this call's response, or null.
  String? after(String tool, {required bool isError}) {
    if (!singleSteps.contains(tool)) {
      _streak = 0;
      return null;
    }
    // A failed step is the agent finding its way, not a known sequence.
    if (isError) {
      _streak = 0;
      return null;
    }
    _streak++;
    if (_streak != first && (_streak - first) % again != 0) return null;
    return 'TIP: $_streak single steps in a row. When the next steps are '
        'already known, send them in one call: execute_action_chain(steps: '
        '[{"tool": "tap_widget", "arguments": {...}}, {"tool": "wait_for", '
        '...}]), fill_form for a form, or tap_widget(waitFor: ...).';
  }
}
