import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'ai_overlay_manager.dart';

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

  static bool _initialized = false;

  /// Installs a global pointer route that intercepts all
  /// [PointerDownEvent]s and resolves the tapped widget.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
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
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) {
      return {'x': position.dx, 'y': position.dy};
    }
    WidgetsBinding.instance.hitTestInView(result, position, view.viewId);

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
  static Future<void> tapAt(Offset position, {String? label}) async {
    AiOverlayManager.showAction(position, label ?? 'Tap');
    final pointer = TestPointer(1, PointerDeviceKind.touch);
    GestureBinding.instance.handlePointerEvent(pointer.down(position));
    await Future.delayed(const Duration(milliseconds: 50));
    GestureBinding.instance.handlePointerEvent(pointer.up());
  }

  /// Simulates a double-tap at [position].
  static Future<void> doubleTapAt(Offset position, {String? label}) async {
    AiOverlayManager.showAction(position, label ?? 'Double Tap');
    await tapAt(position);
    await Future.delayed(const Duration(milliseconds: 40));
    await tapAt(position);
  }

  /// Simulates a long-press (pointer down held for [duration], then up).
  static Future<void> longPressAt(
    Offset position, {
    Duration duration = const Duration(milliseconds: 600),
    String? label,
  }) async {
    AiOverlayManager.showAction(position, label ?? 'Long Press');
    final pointer = TestPointer(1, PointerDeviceKind.touch);
    GestureBinding.instance.handlePointerEvent(pointer.down(position));
    await Future.delayed(duration);
    GestureBinding.instance.handlePointerEvent(pointer.up());
  }

  /// Simulates a swipe from [start] to [end] over [duration].
  ///
  /// Moves the pointer in [steps] intermediate positions to trigger scroll
  /// and drag gesture recognizers.
  static Future<void> swipeFromTo(
    Offset start,
    Offset end, {
    Duration duration = const Duration(milliseconds: 300),
    int steps = 20,
  }) async {
    final pointer = TestPointer(1, PointerDeviceKind.touch);
    GestureBinding.instance.handlePointerEvent(pointer.down(start));
    final stepDelay = duration ~/ steps;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final pos = Offset.lerp(start, end, t)!;
      await Future.delayed(stepDelay);
      GestureBinding.instance.handlePointerEvent(pointer.move(pos));
    }
    GestureBinding.instance.handlePointerEvent(pointer.up());
  }

  /// Drags the widget at [from] to the position of the widget at [to].
  static Future<void> dragFromTo(
    Offset from,
    Offset to, {
    Duration duration = const Duration(milliseconds: 400),
  }) => swipeFromTo(from, to, duration: duration, steps: 30);
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
  /// Throws [StateError] if called before [down].
  PointerEvent up({Duration timeStamp = Duration.zero}) {
    if (_location == null) {
      throw StateError('TestPointer.up() called before down()');
    }
    final Offset location = _location!;
    _location = null;
    return PointerUpEvent(
      pointer: pointer,
      kind: kind,
      position: location,
      timeStamp: timeStamp,
    );
  }

  /// Creates a [PointerMoveEvent] to [location].
  ///
  /// Throws [StateError] if called before [down].
  PointerEvent move(Offset location, {Duration timeStamp = Duration.zero}) {
    if (_location == null) {
      throw StateError('TestPointer.move() called before down()');
    }
    final delta = location - _location!;
    _location = location;
    return PointerMoveEvent(
      pointer: pointer,
      kind: kind,
      position: location,
      delta: delta,
      timeStamp: timeStamp,
    );
  }
}
