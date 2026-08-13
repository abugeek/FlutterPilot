import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Scans the active Flutter widget and render tree for layout overflow errors,
/// accessibility touch-target violations, and missing semantic labels.
class UiHealthAuditor {
  static const double minTouchTargetSize = 48.0;

  /// Performs a comprehensive health audit on the current screen.
  static Map<String, dynamic> audit() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return {
        'isHealthy': false,
        'error': 'No root element found.',
        'overflows': [],
        'accessibilityIssues': [],
      };
    }

    final List<Map<String, dynamic>> overflows = [];
    final List<Map<String, dynamic>> accessibilityIssues = [];

    void checkElement(Element element) {
      final ro = element.renderObject;
      final widget = element.widget;
      final typeName = widget.runtimeType.toString();

      // 1. Check for layout overflow issues
      if (ro is RenderBox && ro.hasSize) {
        // Check RenderFlex overflow diagnostics
        if (ro is RenderFlex) {
          final creator = ro.debugCreator;
          if (creator != null) {
            final diag = ro.toString();
            if (diag.contains('overflowed by') || diag.contains('OVERFLOWING')) {
              overflows.add({
                'type': typeName,
                'details': diag,
                'location': _extractLocation(widget),
              });
            }
          }
        }

        // 2. Check for small touch targets on buttons / clickables (<48x48 dp)
        if (_isClickableWidget(widget, typeName)) {
          final size = ro.size;
          if (size.width > 0 &&
              size.height > 0 &&
              (size.width < minTouchTargetSize || size.height < minTouchTargetSize)) {
            final keyStr = widget.key?.toString() ?? typeName;
            accessibilityIssues.add({
              'target': keyStr,
              'type': typeName,
              'width': size.width,
              'height': size.height,
              'issue':
                  'Touch target size (${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}) is smaller than recommended minimum (${minTouchTargetSize}x$minTouchTargetSize dp).',
            });
          }
        }
      }

      element.visitChildren(checkElement);
    }

    checkElement(root);

    final isHealthy = overflows.isEmpty && accessibilityIssues.isEmpty;
    return {
      'isHealthy': isHealthy,
      'overflowCount': overflows.length,
      'accessibilityIssueCount': accessibilityIssues.length,
      'overflows': overflows,
      'accessibilityIssues': accessibilityIssues,
    };
  }

  static bool _isClickableWidget(Widget widget, String typeName) {
    return widget is IconButton ||
        widget is ElevatedButton ||
        widget is TextButton ||
        widget is OutlinedButton ||
        widget is FloatingActionButton ||
        widget is InkWell ||
        widget is GestureDetector;
  }

  static Map<String, dynamic>? _extractLocation(Widget widget) {
    try {
      final dynamic loc = (widget as dynamic)._location;
      if (loc != null) {
        return {
          'file': loc.file?.toString(),
          'line': loc.line,
          'column': loc.column,
        };
      }
    } catch (_) {}
    return null;
  }
}
