import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'error_inspector.dart';
import 'interaction_manager.dart';

/// Autonomous monkey/chaos fuzzing engine for stress testing Flutter apps.
class ChaosFuzzer {
  static final Random _random = Random();
  static bool _isRunning = false;

  /// Runs autonomous chaos testing for [durationSeconds] or [maxEvents].
  static Future<Map<String, dynamic>> run({
    int durationSeconds = 5,
    int eventRatePerSecond = 5,
    int? maxEvents,
    List<String> allowedActions = const ['tap', 'text', 'scroll'],
  }) async {
    if (_isRunning) {
      return {'status': 'error', 'message': 'Chaos fuzzer is already running'};
    }
    _isRunning = true;

    final startTime = DateTime.now();
    final initialErrorCount = ErrorInspector.errors.length;
    int eventsCount = 0;
    final List<String> eventLog = [];

    final targetTotal = maxEvents ?? (durationSeconds * eventRatePerSecond);
    final intervalMs = maxEvents != null ? 0 : (1000 / eventRatePerSecond).round();

    for (int i = 0; i < targetTotal; i++) {
      try {
        final root = WidgetsBinding.instance.rootElement;
        if (root == null) break;

        final interactiveElements = _findInteractiveElements(root);
        if (interactiveElements.isEmpty) {
          if (intervalMs > 0) await Future.delayed(Duration(milliseconds: intervalMs));
          continue;
        }

        final target = interactiveElements[_random.nextInt(interactiveElements.length)];
        final ro = target.renderObject;
        if (ro is RenderBox && ro.hasSize) {
          final pos = ro.localToGlobal(ro.size.center(Offset.zero));
          final action = allowedActions[_random.nextInt(allowedActions.length)];

          if (action == 'tap') {
            final pointer = TestPointer(1, PointerDeviceKind.touch);
            GestureBinding.instance.handlePointerEvent(pointer.down(pos));
            GestureBinding.instance.handlePointerEvent(pointer.up());
            eventLog.add('tap @ ${pos.dx.round()},${pos.dy.round()}');
          } else if (action == 'text' && target is StatefulElement && target.state is EditableTextState) {
            final dummy = _generateRandomString(6);
            (target.state as EditableTextState).updateEditingValue(TextEditingValue(text: dummy));
            eventLog.add('text "$dummy"');
          } else {
            final pointer = TestPointer(1, PointerDeviceKind.touch);
            GestureBinding.instance.handlePointerEvent(pointer.down(pos));
            GestureBinding.instance.handlePointerEvent(pointer.up());
            eventLog.add('action @ ${pos.dx.round()},${pos.dy.round()}');
          }
          eventsCount++;
        }
      } catch (e) {
        eventLog.add('Chaos event error: $e');
      }

      if (intervalMs > 0) {
        await Future.delayed(Duration(milliseconds: intervalMs));
      }
    }

    _isRunning = false;
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final finalErrorCount = ErrorInspector.errors.length;
    final newErrors = finalErrorCount - initialErrorCount;

    return {
      'status': newErrors == 0 ? 'passed' : 'crashes_detected',
      'durationMs': elapsedMs,
      'eventsExecuted': eventsCount,
      'newErrorsCaught': newErrors,
      'recentEvents': eventLog.take(20).toList(),
    };
  }

  static List<Element> _findInteractiveElements(Element root) {
    final List<Element> result = [];
    void search(Element element) {
      final w = element.widget;
      if (w is ButtonStyleButton ||
          w is IconButton ||
          w is FloatingActionButton ||
          w is InkWell ||
          w is GestureDetector ||
          (element is StatefulElement && element.state is EditableTextState)) {
        final ro = element.renderObject;
        if (ro is RenderBox && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
          result.add(element);
        }
      }
      element.visitChildren(search);
    }

    search(root);
    return result;
  }

  static String _generateRandomString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(len, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
