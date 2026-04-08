import 'package:flutter/widgets.dart';

/// Provides introspection into the Flutter widget tree.
class PilotWidgetInspector {
  /// Captures the complete widget tree starting from the root.
  static Map<String, dynamic> captureWidgetTree() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return {'error': 'No root element found'};
    return _elementToJson(root);
  }

  /// Finds a widget by its Key.
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

  /// Counts the total number of elements in the tree.
  static int countElements(Element element) {
    int count = 1;
    element.visitChildren((child) {
      count += countElements(child);
    });
    return count;
  }

  static Map<String, dynamic> _elementToJson(Element element) {
    final List<Map<String, dynamic>> children = [];
    element.visitChildren((child) => children.add(_elementToJson(child)));
    
    Map<String, dynamic>? layout;
    final ro = element.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      final pos = ro.localToGlobal(Offset.zero);
      layout = {
        'x': pos.dx, 
        'y': pos.dy, 
        'w': ro.size.width, 
        'h': ro.size.height
      };
    }

    Map<String, dynamic>? location;
    try {
      // Accessing private _location via dynamic for source mapping.
      // This uses a private Flutter API that may change between versions.
      final dynamic widget = element.widget;
      final dynamic loc = widget._location;
      if (loc != null) {
        location = {
          'file': loc.file?.toString(), 
          'line': loc.line, 
          'column': loc.column
        };
      }
    } on NoSuchMethodError catch (_) {
      // _location is a private API — expected to fail on some Flutter versions.
    }

    return {
      'type': element.widget.runtimeType.toString(),
      'key': element.widget.key?.toString(),
      'layout': layout,
      'location': location,
      'children': children
    };
  }
}
