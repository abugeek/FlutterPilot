import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'ai_overlay_manager.dart';

/// Manages user-interaction tracking and programmatic gesture simulation.
///
/// Dispatches genuine Flutter pointer events with full lifecycle:
/// `PointerAddedEvent` -> `PointerDownEvent` -> (Moves) -> `PointerUpEvent` -> `PointerRemovedEvent`.
///
/// Each gesture uses unique pointer IDs and explicit device channels to prevent
/// Flutter gesture arena corruption.
class InteractionManager {
  /// Optional callback invoked on every `PointerDownEvent`.
  static void Function(Map<String, dynamic> info)? onPointerDown;

  static bool _initialized = false;
  static int _nextPointerId = 1;

  static const int _kTouchDeviceId = 1;
  static const int _kSecondTouchDeviceId = 2;
  static const int _kMouseDeviceId = 3;
  static const Duration _kEventDelay = Duration(milliseconds: 10);

  /// Installs a global pointer route that intercepts all
  /// [PointerDownEvent]s and resolves the tapped widget.
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

  /// Adaptively waits for any active Flutter frame animations or microtasks to settle.
  static Future<void> pumpAndSettleAdaptive({
    Duration timeout = const Duration(milliseconds: 80),
    Duration step = const Duration(milliseconds: 16),
  }) async {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      return;
    }
    // Settle the immediate gesture pipeline and resulting setState/build
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!completer.isCompleted) completer.complete();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
    await completer.future.timeout(timeout, onTimeout: () {});
  }

  /// Dispatches sequenced pointer events with frame scheduling and delays.
  static Future<void> _handlePointerEventRecords(
    List<List<PointerEvent>> records,
  ) async {
    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    for (final record in records) {
      for (final event in record) {
        GestureBinding.instance.handlePointerEvent(event);
      }
      WidgetsBinding.instance.scheduleFrame();
      if (!isTest) {
        await Future<void>.delayed(_kEventDelay);
      }
    }
  }


  /// Simulates a physical tap at the given screen [position] with full pointer lifecycle.
  static Future<void> tapAt(Offset position, {String? label}) async {
    AiOverlayManager.showAction(position, label ?? 'Tap');
    final pointerId = _nextPointerId++;

    final records = [
      [
        PointerAddedEvent(position: position, device: _kTouchDeviceId),
        PointerDownEvent(
          pointer: pointerId,
          position: position,
          device: _kTouchDeviceId,
        ),
      ],
      [
        PointerUpEvent(
          pointer: pointerId,
          position: position,
          device: _kTouchDeviceId,
        ),
        PointerRemovedEvent(position: position, device: _kTouchDeviceId),
      ],
    ];

    await _handlePointerEventRecords(records);
    await pumpAndSettleAdaptive();
  }

  /// Simulates a secondary tap (right-click) at [position].
  static Future<void> secondaryTapAt(Offset position, {String? label}) async {
    AiOverlayManager.showAction(position, label ?? 'Right Click');
    final pointerId = _nextPointerId++;

    final records = [
      [
        PointerAddedEvent(
          position: position,
          device: _kMouseDeviceId,
          kind: PointerDeviceKind.mouse,
        ),
        PointerDownEvent(
          pointer: pointerId,
          position: position,
          buttons: kSecondaryMouseButton,
          device: _kMouseDeviceId,
          kind: PointerDeviceKind.mouse,
        ),
      ],
      [
        PointerUpEvent(
          pointer: pointerId,
          position: position,
          device: _kMouseDeviceId,
          kind: PointerDeviceKind.mouse,
        ),
        PointerRemovedEvent(
          position: position,
          device: _kMouseDeviceId,
          kind: PointerDeviceKind.mouse,
        ),
      ],
    ];

    await _handlePointerEventRecords(records);
    await pumpAndSettleAdaptive();
  }

  /// Simulates a double-tap at [position].
  static Future<void> doubleTapAt(
    Offset position, {
    String? label,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    AiOverlayManager.showAction(position, label ?? 'Double Tap');
    await tapAt(position, label: label);
    await Future.delayed(delay);
    await tapAt(position, label: label);
  }

  /// Simulates a long-press (pointer held for [duration], then released).
  static Future<void> longPressAt(
    Offset position, {
    Duration duration = const Duration(milliseconds: 600),
    String? label,
  }) async {
    AiOverlayManager.showAction(position, label ?? 'Long Press');
    final pointerId = _nextPointerId++;

    await _handlePointerEventRecords([
      [
        PointerAddedEvent(position: position, device: _kTouchDeviceId),
        PointerDownEvent(
          pointer: pointerId,
          position: position,
          device: _kTouchDeviceId,
        ),
      ],
    ]);

    await Future.delayed(duration);

    await _handlePointerEventRecords([
      [
        PointerUpEvent(
          pointer: pointerId,
          position: position,
          device: _kTouchDeviceId,
        ),
        PointerRemovedEvent(position: position, device: _kTouchDeviceId),
      ],
    ]);
    await pumpAndSettleAdaptive();
  }

  /// Simulates a smooth swipe or drag from [start] to [end] over [duration].
  static Future<void> swipeFromTo(
    Offset start,
    Offset end, {
    Duration duration = const Duration(milliseconds: 300),
    int steps = 20,
  }) async {
    final pointerId = _nextPointerId++;
    final moveRecords = <List<PointerEvent>>[];
    final stepDelay = duration ~/ math.max(1, steps);

    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final pos = Offset.lerp(start, end, t)!;
      final prevPos = i == 1 ? start : Offset.lerp(start, end, (i - 1) / steps)!;
      final stepDelta = pos - prevPos;

      moveRecords.add([
        PointerMoveEvent(
          pointer: pointerId,
          position: pos,
          delta: stepDelta,
          device: _kTouchDeviceId,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(position: start, device: _kTouchDeviceId),
        PointerDownEvent(
          pointer: pointerId,
          position: start,
          device: _kTouchDeviceId,
        ),
      ],
      ...moveRecords,
      [
        PointerUpEvent(
          pointer: pointerId,
          position: end,
          device: _kTouchDeviceId,
        ),
        PointerRemovedEvent(position: end, device: _kTouchDeviceId),
      ],
    ];

    for (final record in records) {
      for (final event in record) {
        GestureBinding.instance.handlePointerEvent(event);
      }
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(stepDelay);
    }

    await pumpAndSettleAdaptive();
  }

  /// Drags from [from] to [to].
  static Future<void> dragFromTo(
    Offset from,
    Offset to, {
    Duration duration = const Duration(milliseconds: 400),
    int steps = 30,
  }) =>
      swipeFromTo(from, to, duration: duration, steps: steps);

  /// Simulates a multi-touch pinch / zoom gesture around [center].
  ///
  /// [scale] > 1.0 zooms in (fingers spread apart).
  /// [scale] < 1.0 zooms out (fingers pinch together).
  static Future<void> pinchZoomAt(
    Offset center, {
    required double scale,
    double initialSpan = 100.0,
    Duration duration = const Duration(milliseconds: 300),
    int steps = 20,
  }) async {
    final pointer1Id = _nextPointerId++;
    final pointer2Id = _nextPointerId++;

    final startDistance = initialSpan;
    final endDistance = initialSpan * scale;

    Offset finger1(double dist) => center + Offset(-dist / 2, 0);
    Offset finger2(double dist) => center + Offset(dist / 2, 0);

    final start1 = finger1(startDistance);
    final start2 = finger2(startDistance);

    // Initial touch contact
    final records = <List<PointerEvent>>[
      [
        PointerAddedEvent(position: start1, device: _kTouchDeviceId),
        PointerDownEvent(
          pointer: pointer1Id,
          position: start1,
          device: _kTouchDeviceId,
        ),
      ],
      [
        PointerAddedEvent(position: start2, device: _kSecondTouchDeviceId),
        PointerDownEvent(
          pointer: pointer2Id,
          position: start2,
          device: _kSecondTouchDeviceId,
        ),
      ],
    ];

    // Intermediate motion
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final curDist = startDistance + (endDistance - startDistance) * t;
      records.add([
        PointerMoveEvent(
          pointer: pointer1Id,
          position: finger1(curDist),
          device: _kTouchDeviceId,
        ),
        PointerMoveEvent(
          pointer: pointer2Id,
          position: finger2(curDist),
          device: _kSecondTouchDeviceId,
        ),
      ]);
    }

    // Release
    final end1 = finger1(endDistance);
    final end2 = finger2(endDistance);
    records.addAll([
      [
        PointerUpEvent(
          pointer: pointer1Id,
          position: end1,
          device: _kTouchDeviceId,
        ),
        PointerUpEvent(
          pointer: pointer2Id,
          position: end2,
          device: _kSecondTouchDeviceId,
        ),
      ],
      [
        PointerRemovedEvent(position: end1, device: _kTouchDeviceId),
        PointerRemovedEvent(position: end2, device: _kSecondTouchDeviceId),
      ],
    ]);

    final stepDelay = duration ~/ math.max(1, steps);
    for (final record in records) {
      for (final event in record) {
        GestureBinding.instance.handlePointerEvent(event);
      }
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(stepDelay);
    }

    await pumpAndSettleAdaptive();
  }
}

/// Helper for constructing raw pointer events. Maintained for backwards compatibility.
class TestPointer {
  TestPointer([this.pointer = 1, this.kind = PointerDeviceKind.touch]);

  final int pointer;
  final PointerDeviceKind kind;
  Offset? _location;

  PointerEvent down(Offset location, {Duration timeStamp = Duration.zero}) {
    _location = location;
    return PointerDownEvent(
      pointer: pointer,
      kind: kind,
      position: location,
      timeStamp: timeStamp,
    );
  }

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
