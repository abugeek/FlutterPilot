/// Tools merged into another (task 04). A step or a call that still names an
/// old tool is translated to the new tool plus the mode it became, so an
/// agent's memory, an old doc or a saved scenario keeps working.
typedef RetiredTool = ({String tool, Map<String, dynamic> set});

/// Old tool -> the tool it became, and the arguments that pick its mode.
///
/// Only tools that were actually merged belong here (a rename buys nothing and
/// costs every user's docs and memory).
const retiredTools = <String, RetiredTool>{
  'swipe_widget': (tool: 'gesture_widget', set: {'gesture': 'swipe'}),
  'drag_widget': (tool: 'gesture_widget', set: {'gesture': 'drag'}),
  'pinch_zoom': (tool: 'gesture_widget', set: {'gesture': 'pinch'}),
  'focus_widget': (tool: 'gesture_widget', set: {'gesture': 'focus'}),
  'set_slider_value': (tool: 'gesture_widget', set: {'gesture': 'slide'}),
};

/// [tool] with [arguments], rewritten when [tool] was merged: the new tool and
/// the mode's arguments, with anything the caller passed taking precedence.
({String tool, Map<String, dynamic> arguments}) translateRetiredStep(
  String tool,
  Map<String, dynamic> arguments,
) {
  final retired = retiredTools[tool];
  if (retired == null) return (tool: tool, arguments: arguments);
  return (tool: retired.tool, arguments: {...retired.set, ...arguments});
}
