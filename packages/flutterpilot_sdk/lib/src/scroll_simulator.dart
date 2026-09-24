import 'package:flutter/widgets.dart';
import 'hit_test_utils.dart';
import 'interaction_manager.dart';
import 'widget_inspector.dart';

/// Simulates scrolling gestures to make widgets visible and hittable,
/// especially in lazily rendered lists (ListView.builder, CustomScrollView).
class ScrollSimulator {
  static const double _minStepDelta = 80.0;
  static const int defaultMaxAttempts = 8;

  /// Scrolls scrollable ancestors or views until the widget matching [target]
  /// is mounted, laid out, and hittable on screen.
  static Future<bool> scrollUntilVisible(
    String target, {
    int maxAttempts = defaultMaxAttempts,
    double scrollRatio = 0.55,
  }) async {
    // 1. If element is already present and hittable, nothing to do
    final existing = PilotWidgetInspector.findElement(target);
    if (existing != null && HitTestUtils.isElementHittable(existing)) {
      return true;
    }

    // 2. If element is mounted in tree, try Scrollable.ensureVisible first
    if (existing != null) {
      try {
        await Scrollable.ensureVisible(
          existing,
          duration: const Duration(milliseconds: 150),
          alignment: 0.5,
        );
        await InteractionManager.pumpAndSettleAdaptive(
          timeout: const Duration(milliseconds: 200),
        );
        if (HitTestUtils.isElementHittable(existing)) {
          return true;
        }
      } catch (_) {}
    }

    // 3. Find scrollable containers currently visible on screen
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return false;

    final scrollables = <Element>[];
    void findScrollables(Element element) {
      if (element.widget is Scrollable &&
          HitTestUtils.isElementHittable(element)) {
        scrollables.add(element);
      }
      element.visitChildren(findScrollables);
    }

    findScrollables(root);
    if (scrollables.isEmpty) {
      // Fallback: search any Scrollable even if hit test fails (e.g. nested)
      void findAllScrollables(Element element) {
        if (element.widget is Scrollable &&
            element.renderObject is RenderBox &&
            (element.renderObject as RenderBox).hasSize) {
          scrollables.add(element);
        }
        element.visitChildren(findAllScrollables);
      }

      findAllScrollables(root);
    }

    if (scrollables.isEmpty) return false;

    // 4. Try dragging candidate scrollables down (and up if needed)
    for (final scrollable in scrollables) {
      ScrollPosition? position;
      if (scrollable is StatefulElement && scrollable.state is ScrollableState) {
        try {
          position = (scrollable.state as ScrollableState).position;
        } catch (_) {}
      }

      // Early short-circuit: if content fits entirely, don't attempt useless swipes
      if (position != null && position.hasContentDimensions) {
        if (position.maxScrollExtent <= position.minScrollExtent) {
          continue;
        }
      }

      final ro = scrollable.renderObject as RenderBox;
      final center = ro.localToGlobal(ro.size.center(Offset.zero));
      final widget = scrollable.widget as Scrollable;
      final axis = widget.axisDirection;

      final isVertical =
          axis == AxisDirection.down || axis == AxisDirection.up;
      final dragDistance = isVertical
          ? (ro.size.height * scrollRatio).clamp(_minStepDelta, 500.0)
          : (ro.size.width * scrollRatio).clamp(_minStepDelta, 500.0);

      final dragDelta = isVertical
          ? Offset(0, -dragDistance)
          : Offset(-dragDistance, 0);

      // Drag forward up to max attempts with edge-detection
      double lastPixels = position?.hasContentDimensions == true ? position!.pixels : double.negativeInfinity;
      for (int i = 0; i < maxAttempts; i++) {
        await InteractionManager.swipeFromTo(
          center,
          center + dragDelta,
          duration: const Duration(milliseconds: 100),
          steps: 8,
        );
        await InteractionManager.pumpAndSettleAdaptive(
          timeout: const Duration(milliseconds: 200),
        );
        PilotWidgetInspector.invalidateCache();

        final candidate = PilotWidgetInspector.findElement(target);
        if (candidate != null && HitTestUtils.isElementHittable(candidate)) {
          return true;
        }

        // Abort if scroll position reached physical bounds
        if (position != null && position.hasContentDimensions) {
          if ((position.pixels - lastPixels).abs() < 1.0) {
            break;
          }
          lastPixels = position.pixels;
        }
      }

      // Drag reverse in case target was above/behind with edge-detection
      final reverseDelta = -dragDelta;
      lastPixels = position?.hasContentDimensions == true ? position!.pixels : double.negativeInfinity;
      for (int i = 0; i < maxAttempts; i++) {
        await InteractionManager.swipeFromTo(
          center,
          center + reverseDelta,
          duration: const Duration(milliseconds: 100),
          steps: 8,
        );
        await InteractionManager.pumpAndSettleAdaptive(
          timeout: const Duration(milliseconds: 200),
        );
        PilotWidgetInspector.invalidateCache();

        final candidate = PilotWidgetInspector.findElement(target);
        if (candidate != null && HitTestUtils.isElementHittable(candidate)) {
          return true;
        }

        if (position != null && position.hasContentDimensions) {
          if ((position.pixels - lastPixels).abs() < 1.0) {
            break;
          }
          lastPixels = position.pixels;
        }
      }
    }

    return false;
  }
}
