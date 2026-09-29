import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'hit_test_utils.dart';
import 'widget_inspector.dart';

/// Brings a widget on screen by scrolling the lists around it, including
/// lazy lists (ListView.builder, grids, slivers) where it isn't built yet.
///
/// Scrolls through each list's [ScrollPosition] a page at a time, not with
/// drag gestures: a drag depends on the app's ScrollBehavior and flings past
/// the target. A jump still sends scroll notifications, so "load more"
/// listeners run as for a user.
class ScrollSimulator {
  /// How long a search may take before giving up.
  static const Duration timeLimit = Duration(seconds: 10);

  /// Scrolls until the widget matching [target] is built and hittable.
  /// Lists not holding it are put back where they were.
  ///
  /// First pages through the lists on screen; then, if the target was not
  /// found, through the lists across each one's axis too (a row of
  /// horizontal cards in a vertical feed), each inner list once.
  static Future<bool> scrollUntilVisible(String target) async {
    if (await _reveal(target)) return true;
    final deadline = DateTime.now().add(timeLimit);
    for (final nested in const [false, true]) {
      final searched = <ScrollableState>{};
      for (final list in _lists(WidgetsBinding.instance.rootElement)) {
        if (await _search(list, target, deadline, nested ? searched : null)) {
          return true;
        }
        if (DateTime.now().isAfter(deadline)) return false;
      }
    }
    return false;
  }

  /// True once [target] is on screen; a built but off-screen widget is
  /// scrolled to (through every list around it). Text matches whole only:
  /// the list may not have built the item a partial match stands for.
  static Future<bool> _reveal(String target) async {
    var element = PilotWidgetInspector.findElement(target, partial: false);
    if (element == null) return false;
    if (HitTestUtils.isElementHittable(element)) return true;
    try {
      await Scrollable.ensureVisible(element, alignment: 0.5);
    } catch (_) {
      return false;
    }
    await _frame();
    element = PilotWidgetInspector.findElement(target, partial: false);
    return element != null && HitTestUtils.isElementHittable(element);
  }

  /// Pages through [list] forward, then backward from where it started.
  /// With [searched] (the inner lists already searched), also through the
  /// lists across its axis on each page.
  static Future<bool> _search(
    ScrollableState list,
    String target,
    DateTime deadline,
    Set<ScrollableState>? searched,
  ) async {
    if (!list.mounted) return false;
    final position = list.position;
    final start = position.pixels;
    final step = _pageOf(list);
    for (final direction in const [1, -1]) {
      if (direction == -1) await _jump(list, start);
      while (true) {
        if (await _reveal(target)) return true;
        if (searched != null && list.mounted) {
          for (final inner in _lists(list.context as Element)) {
            if (inner.position.axis == position.axis || !searched.add(inner)) {
              continue;
            }
            if (await _search(inner, target, deadline, null)) return true;
          }
        }
        if (!list.mounted) return false;
        if (DateTime.now().isAfter(deadline)) {
          await _jump(list, start);
          return false;
        }
        final next = (position.pixels + step * direction).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((next - position.pixels).abs() < 1) break;
        await _jump(list, next);
      }
    }
    await _jump(list, start);
    return false;
  }

  /// How far one jump goes: most of a viewport, so consecutive views
  /// overlap and every item is on screen in one of them (the finder sees a
  /// list's visible children, not those built in its cache area).
  static double _pageOf(ScrollableState list) =>
      list.position.viewportDimension * 0.9;

  static Future<void> _jump(ScrollableState list, double pixels) async {
    if (!list.mounted) return;
    list.position.jumpTo(pixels);
    await _frame();
  }

  /// The outermost scrollable lists on screen below [root] (not [root]
  /// itself) that have something to scroll.
  static List<ScrollableState> _lists(Element? root) {
    final found = <ScrollableState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final p = state.position;
        if (p.hasContentDimensions && p.maxScrollExtent > p.minScrollExtent) {
          found.add(state);
        }
        return;
      }
      element.debugVisitOnstageChildren(visit);
    }

    root?.debugVisitOnstageChildren(visit);
    return found;
  }

  /// Builds and lays out what a jump brought in. While the window is
  /// hidden, frames are off and the OS throttles vsync (~70 ms a frame on a
  /// covered macOS window): the search only needs the widgets built and
  /// placed, so that is done at once and painting waits for the next frame.
  static Future<void> _frame() async {
    final binding = WidgetsBinding.instance;
    final root = binding.rootElement;
    if (!binding.framesEnabled &&
        binding.schedulerPhase == SchedulerPhase.idle &&
        root != null) {
      binding.buildOwner!.buildScope(root);
      binding.rootPipelineOwner.flushLayout();
      // As a frame ends: unmount what scrolled out. Left inactive, a row's
      // list still reports mounted, and scrolling it fails.
      binding.buildOwner!.finalizeTree();
      return;
    }
    final done = Completer<void>();
    binding.addPostFrameCallback((_) {
      if (!done.isCompleted) done.complete();
    });
    binding.scheduleForcedFrame();
    await done.future.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {},
    );
  }
}
