import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Manages user-interaction tracking and programmatic gesture simulation.
///
/// [InteractionManager] installs a global pointer-event listener to
/// detect taps and resolve which widget was tapped. It also provides
/// [tapAt] for simulating touch events programmatically.
///
/// This class is initialized automatically by [FlutterPilot.initialize].
class InteractionManager {
  /// Optional callback invoked on every `PointerDownEvent`.
  ///
  /// The map contains `x`, `y` (screen coordinates), and — when a
  /// meaningful widget is found — `key` and `type`.
  static void Function(Map<String, dynamic> info)? onPointerDown;

  /// Installs a global pointer route that intercepts all
  /// [PointerDownEvent]s and resolves the tapped widget.
  ///
  /// Safe to call multiple times — each call adds an additional listener,
  /// so callers should ensure single initialization.
  static void initialize() {
    GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent event) {
      if (event is PointerDownEvent) {
        final info = _resolveWidgetAt(event.position);
        onPointerDown?.call(info);
      }
    });
  }

  /// Resolves the most meaningful widget at [position] using hit-testing.
  ///
  /// Prefers elements that have a [Key] or are semantically significant
  /// (e.g., `Text`, button-like widgets). Returns a map with `x`, `y`,
  /// and optionally `key` and `type`.
  static Map<String, dynamic> _resolveWidgetAt(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      position,
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    );

    Element? bestElement;
    for (final entry in result.path) {
      final ro = entry.target;
      if (ro is RenderObject) {
        void findElement(Element element) {
          if (bestElement != null) return;
          if (element.renderObject == ro) {
            // Favor elements with keys or specific types for meaningful tracking
            if (element.widget.key != null ||
                element.widget is Text ||
                element.widget.runtimeType.toString().contains('Button')) {
              bestElement = element;
            }
          } else {
            element.visitChildren(findElement);
          }
        }

        final root = WidgetsBinding.instance.rootElement;
        if (root != null) findElement(root);
      }
      if (bestElement != null) break;
    }

    if (bestElement != null) {
      return {
        'x': position.dx,
        'y': position.dy,
        'key': bestElement!.widget.key?.toString(),
        'type': bestElement!.widget.runtimeType.toString(),
      };
    }
    return {'x': position.dx, 'y': position.dy};
  }

  /// Simulates a physical tap (pointer down + 50 ms delay + pointer up) at
  /// the given screen [position].
  ///
  /// Used by the `ext.flutterpilot.tapAt` and `ext.flutterpilot.tapWidget`
  /// service extensions to drive the UI programmatically.
  static Future<void> tapAt(Offset position) async {
    final pointer = TestPointer(1, PointerDeviceKind.touch);
    GestureBinding.instance.handlePointerEvent(pointer.down(position));
    await Future.delayed(const Duration(milliseconds: 50));
    GestureBinding.instance.handlePointerEvent(pointer.up());
  }
}

/// Lightweight helper for constructing [PointerDownEvent] / [PointerUpEvent]
/// pairs used by [InteractionManager.tapAt].
///
/// This is intentionally minimal — it does not track hover, move, or
/// cancel events.
class TestPointer {
  /// Creates a [TestPointer] with an optional [pointer] id and [kind].
  TestPointer([this.pointer = 1, this.kind = PointerDeviceKind.touch]);

  /// The pointer identifier passed to generated events.
  final int pointer;

  /// The input device kind (defaults to [PointerDeviceKind.touch]).
  final PointerDeviceKind kind;
  Offset? _location;

  /// Creates a [PointerDownEvent] at [location].
  PointerEvent down(Offset location, {Duration timeStamp = Duration.zero}) {
    _location = location;
    return PointerDownEvent(
      pointer: pointer,
      kind: kind,
      position: location,
      timeStamp: timeStamp,
    );
  }

  /// Creates a [PointerUpEvent] at the last `down` location.
  ///
  /// Throws if called before [down].
  PointerEvent up({Duration timeStamp = Duration.zero}) {
    final Offset location = _location!;
    _location = null;
    return PointerUpEvent(
      pointer: pointer,
      kind: kind,
      position: location,
      timeStamp: timeStamp,
    );
  }
}
