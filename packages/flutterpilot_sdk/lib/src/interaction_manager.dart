import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Manages user interactions and simulated actions for FlutterPilot.
class InteractionManager {
  static void Function(Map<String, dynamic> info)? onPointerDown;

  /// Initializes global pointer interception.
  static void initialize() {
    GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent event) {
      if (event is PointerDownEvent) {
        final info = _resolveWidgetAt(event.position);
        onPointerDown?.call(info);
      }
    });
  }

  /// Resolves the widget and its metadata at the given screen coordinates.
  static Map<String, dynamic> _resolveWidgetAt(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result, 
      position, 
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId
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

  /// Simulates a physical tap at specific (x, y) coordinates.
  static Future<void> tapAt(Offset position) async {
    final pointer = TestPointer(1, PointerDeviceKind.touch);
    GestureBinding.instance.handlePointerEvent(pointer.down(position));
    await Future.delayed(const Duration(milliseconds: 50));
    GestureBinding.instance.handlePointerEvent(pointer.up());
  }
}

/// Helper class for simulating pointer events.
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
      timeStamp: timeStamp
    );
  }

  PointerEvent up({Duration timeStamp = Duration.zero}) {
    final Offset location = _location!;
    _location = null;
    return PointerUpEvent(
      pointer: pointer, 
      kind: kind, 
      position: location, 
      timeStamp: timeStamp
    );
  }
}
