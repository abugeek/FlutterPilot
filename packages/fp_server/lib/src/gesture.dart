/// `gesture_widget` (task 04) merged five tools that each did one gesture:
/// `swipe_widget`, `drag_widget`, `pinch_zoom`, `focus_widget` and
/// `set_slider_value`. One tool with a mode argument is only easier for a
/// model to use if a mode's arguments are refused in another mode, instead of
/// quietly doing nothing.
library;

/// The gestures `gesture_widget` performs.
const gestureModes = <String>['swipe', 'drag', 'pinch', 'focus', 'slide'];

/// The arguments only one gesture uses, and which one.
const gestureOwnedArguments = <String, String>{
  'direction': 'swipe',
  'distance': 'swipe',
  'fromKey': 'drag',
  'toKey': 'drag',
  'scale': 'pinch',
  'identifier': 'pinch',
  'x': 'pinch',
  'y': 'pinch',
  'value': 'slide',
};

/// What is wrong with a `gesture_widget` call, or null when it can run.
String? gestureRequestError(Map<String, dynamic> params) {
  final gesture = params['gesture']?.toString();
  if (gesture == null || !gestureModes.contains(gesture)) {
    return 'gesture must be one of ${gestureModes.join(', ')}'
        '${gesture == null ? '' : '; got "$gesture"'}.';
  }
  for (final entry in gestureOwnedArguments.entries) {
    if (params[entry.key] != null && entry.value != gesture) {
      return '"${entry.key}" is for gesture: ${entry.value}; it is not used '
          'by gesture: $gesture.';
    }
  }
  final from = params['fromKey'] ?? params['key'];
  final to = params['toKey'];
  switch (gesture) {
    case 'swipe':
      if (params['direction'] == null) {
        return 'gesture: swipe needs direction (up/down/left/right).';
      }
    case 'drag':
      if (from == null || to == null) {
        return 'gesture: drag needs fromKey (or key) and toKey.';
      }
    case 'pinch':
      if (params['scale'] == null) {
        return 'gesture: pinch needs scale.';
      }
    case 'slide':
      if (params['value'] == null) {
        return 'gesture: slide needs value.';
      }
  }
  return null;
}
