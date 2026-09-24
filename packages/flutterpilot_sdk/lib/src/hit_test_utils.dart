import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Utilities for verifying widget hittability and occlusion.
class HitTestUtils {
  /// Checks if the [element] can receive pointer events.
  ///
  /// Performs a hit test at the center of the element and checks whether its
  /// render object appears in the hit test path. Elements behind modal
  /// barriers, [AbsorbPointer], [IgnorePointer], or offscreen will return false.
  static bool isElementHittable(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    return isElementHittableAt(element, renderObject.size.center(Offset.zero));
  }

  /// Checks if the [element] can receive pointer events at [localPoint].
  ///
  /// [localPoint] is in the element's own coordinate space.
  static bool isElementHittableAt(Element element, Offset localPoint) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    if (!renderObject.attached) {
      return false;
    }

    final view = element.findAncestorWidgetOfExactType<View>();
    final viewId = view?.view.viewId ??
        WidgetsBinding.instance.platformDispatcher.implicitView?.viewId;
    if (viewId == null) {
      return false;
    }

    try {
      final absoluteOffset = renderObject.localToGlobal(localPoint);
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, absoluteOffset, viewId);

      for (final entry in result.path) {
        if (entry.target == renderObject) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }
}
