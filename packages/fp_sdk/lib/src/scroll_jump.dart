import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'widget_inspector.dart';

/// The scrollable [target] names (the list itself or a widget inside it),
/// or with no target the largest scrollable on screen that can scroll.
ScrollableState? scrollableFor(String? target) {
  if (target != null && target.isNotEmpty) {
    final e = PilotWidgetInspector.findElement(target);
    if (e == null) return null;
    if (e is StatefulElement && e.state is ScrollableState) {
      return e.state as ScrollableState;
    }
    ScrollableState? inside;
    void find(Element c) {
      if (inside != null) return;
      if (c is StatefulElement && c.state is ScrollableState) {
        inside = c.state as ScrollableState;
      } else {
        c.visitChildElements(find);
      }
    }

    e.visitChildElements(find);
    return inside ?? Scrollable.maybeOf(e);
  }
  ScrollableState? best;
  var bestArea = 0.0;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final s = e.state as ScrollableState;
      final box = e.findRenderObject();
      if (s.position.hasContentDimensions &&
          s.position.maxScrollExtent > 0 &&
          box is RenderBox &&
          box.hasSize &&
          box.size.width * box.size.height > bestArea) {
        best = s;
        bestArea = box.size.width * box.size.height;
      }
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return best;
}

/// Jumps [position] to [fraction] of its extent, the way a scrollbar thumb
/// drag does, and times each frame it takes. A list without a fixed extent
/// only estimates its length, so the jump repeats until the end it aims at
/// stops moving (at most 10 frames), as a thumb held at the end would.
Future<Map<String, Object>> jumpToFraction(
  ScrollPosition position,
  double fraction,
) async {
  final frames = <int>[];
  final total = Stopwatch()..start();
  double? aimed;
  for (var i = 0; i < 10; i++) {
    final target =
        position.minScrollExtent +
        fraction * (position.maxScrollExtent - position.minScrollExtent);
    if (aimed != null && (target - aimed).abs() < 0.5) break;
    aimed = target;
    final frame = Stopwatch()..start();
    position.jumpTo(target);
    SchedulerBinding.instance.scheduleFrame();
    await SchedulerBinding.instance.endOfFrame;
    frames.add(frame.elapsedMilliseconds);
  }
  total.stop();
  final worst = frames.isEmpty ? 0 : frames.reduce((a, b) => a > b ? a : b);
  return {
    'fraction': fraction,
    'offset': position.pixels.round(),
    'maxScrollExtent': position.maxScrollExtent.round(),
    'frames': frames.length,
    'frameMs': frames,
    'worstFrameMs': worst,
    'elapsedMs': total.elapsedMilliseconds,
  };
}

/// Whether [scrollable]'s list lays its rows out at one fixed extent
/// (itemExtent, prototypeItem, SliverFixedExtentList...): such a list jumps
/// by arithmetic, so a slow jump there is not the lay-out-every-row cost.
bool hasFixedExtentList(ScrollableState scrollable) {
  var fixed = false;
  void visit(RenderObject ro) {
    if (fixed) return;
    if (ro is RenderSliverFixedExtentBoxAdaptor) {
      fixed = true;
      return;
    }
    ro.visitChildren(visit);
  }

  final root = scrollable.context.findRenderObject();
  if (root != null) visit(root);
  return fixed;
}
