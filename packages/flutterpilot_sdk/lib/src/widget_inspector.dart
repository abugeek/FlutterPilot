import 'package:flutter/widgets.dart';

/// Provides read-only introspection into the live Flutter widget tree.
///
/// [PilotWidgetInspector] can serialize the entire element tree to JSON,
/// look up individual widgets by key, and count elements — all used by
/// the `ext.flutterpilot.getWidgetTree`, `ext.flutterpilot.tapWidget`,
/// `ext.flutterpilot.enterText`, and `ext.flutterpilot.scrollIntoView`
/// service extensions.
///
/// This class is stateless and exposes only static methods.
class PilotWidgetInspector {
  /// Default maximum depth for widget tree traversal.
  static const int defaultMaxDepth = 50;

  /// Captures the widget tree as a nested JSON-compatible map.
  ///
  /// Returns a recursive structure where each node contains:
  /// - `type` — the widget's `runtimeType`.
  /// - `key` — the widget's key (if any).
  /// - `layout` — bounding box (`x`, `y`, `w`, `h`) when available.
  /// - `location` — source file, line, and column (best-effort; relies
  ///   on a private Flutter API that may not be available in all builds).
  /// - `children` — child nodes.
  ///
  /// [maxDepth] limits recursion depth to prevent stack overflow on very
  /// deep widget trees (default: [defaultMaxDepth]).
  ///
  /// Returns `{'error': 'No root element found'}` if the root element is
  /// not yet available (e.g., before [runApp]).
  static Map<String, dynamic> captureWidgetTree({int? maxDepth}) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return {'error': 'No root element found'};
    return _elementToJson(root, 0, maxDepth ?? defaultMaxDepth);
  }

  /// Finds an [Element] in the tree whose widget key matches [keyString].
  ///
  /// Supports plain string keys, `ValueKey` (`['keyString']`), and
  /// `GlobalKey` (`[<'keyString'>]`) representations. Returns `null` if
  /// no matching element is found.
  ///
  /// This is the lookup mechanism used by `ext.flutterpilot.tapWidget`,
  /// `ext.flutterpilot.enterText`, and `ext.flutterpilot.scrollIntoView`.
  static Element? findElementByKey(String keyString) {
    Element? found;
    void search(Element element) {
      if (found != null) return;
      final widgetKey = element.widget.key?.toString();
      if (widgetKey == keyString ||
          widgetKey == "['$keyString']" ||
          widgetKey == "[<'$keyString'>]") {
        found = element;
        return;
      }
      element.visitChildren(search);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) search(root);
    return found;
  }

  /// Recursively counts all [Element] nodes in the subtree rooted at
  /// [element], including [element] itself.
  static int countElements(Element element) {
    int count = 1;
    element.visitChildren((child) {
      count += countElements(child);
    });
    return count;
  }

  static Map<String, dynamic> _elementToJson(
    Element element,
    int currentDepth,
    int maxDepth,
  ) {
    final List<Map<String, dynamic>> children = [];
    if (currentDepth < maxDepth) {
      element.visitChildren(
        (child) =>
            children.add(_elementToJson(child, currentDepth + 1, maxDepth)),
      );
    }

    Map<String, dynamic>? layout;
    final ro = element.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      final pos = ro.localToGlobal(Offset.zero);
      layout = {
        'x': pos.dx,
        'y': pos.dy,
        'w': ro.size.width,
        'h': ro.size.height,
      };
    }

    Map<String, dynamic>? location;
    try {
      // In debug builds with --track-widget-creation (default), the compiler
      // injects a private _location field on widgets. No public API exists
      // for this, so we access it dynamically with a safety catch.
      final dynamic loc = (element.widget as dynamic)._location;
      if (loc != null) {
        location = {
          'file': loc.file?.toString(),
          'line': loc.line,
          'column': loc.column,
        };
      }
    } catch (_) {
      // Expected in release mode or without --track-widget-creation.
    }

    return {
      'type': element.widget.runtimeType.toString(),
      'key': element.widget.key?.toString(),
      'layout': layout,
      'location': location,
      if (currentDepth >= maxDepth && _hasChildren(element)) '_truncated': true,
      'children': children,
    };
  }

  /// Returns true if [element] has at least one child, without building a list.
  static bool _hasChildren(Element element) {
    bool found = false;
    element.visitChildren((_) {
      found = true;
    });
    return found;
  }
}
