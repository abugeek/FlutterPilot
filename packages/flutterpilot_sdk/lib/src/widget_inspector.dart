import 'package:flutter/material.dart';

/// Provides read-only introspection and semantic element querying into the live Flutter widget tree.
///
/// [PilotWidgetInspector] can serialize the entire element tree to JSON,
/// look up individual widgets by explicit keys or semantic selectors,
/// and count elements.
class PilotWidgetInspector {
  /// Default maximum depth for widget tree traversal.
  static const int defaultMaxDepth = 250;

  /// Captures the widget tree as a nested JSON-compatible map.
  ///
  /// Returns a recursive structure where each node contains:
  /// - `type` — the widget's `runtimeType`.
  /// - `key` — the widget's key (if any).
  /// - `selector` — Virtual Semantic Selector (e.g. `ElevatedButton['Sign In']`).
  /// - `text` — visible text content (if any).
  /// - `layout` — bounding box (`x`, `y`, `w`, `h`) when available.
  /// - `location` — source file, line, and column (best-effort).
  /// - `children` — child nodes.
  static Map<String, dynamic> captureWidgetTree({int? maxDepth}) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return {'error': 'No root element found'};
    return _elementToJson(root, 0, maxDepth ?? defaultMaxDepth);
  }

  /// Finds an [Element] in the tree matching [query].
  ///
  /// Lookup resolution order:
  /// 1. Exact widget key (`'login'`, `ValueKey('login')`, `GlobalKey`).
  /// 2. Structured semantic selector (e.g. `ElevatedButton['Log In']`, `Button['Submit']`, `TextField['Email']`, `Tooltip['Settings']`).
  /// 3. Visible button text (e.g. tapping `"Log In"` finds the enclosing `ElevatedButton`/`TextButton`/`InkWell`).
  /// 4. Direct text content on `Text` or `RichText` widgets.
  /// 5. Accessibility semantics label or Tooltip message.
  /// 6. Widget runtime type (e.g. `"FloatingActionButton"`).
  static Element? findElement(String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    // 1. Try exact key match first
    final byKey = findElementByKey(cleanQuery);
    if (byKey != null) return byKey;

    // 2. Try structured semantic selector pattern: Type['value'] or Type[attr:'value']
    final selectorRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = selectorRegex.firstMatch(cleanQuery);
    if (match != null) {
      final typeTarget = match.group(1)!;
      var valueTarget = match.group(2)!.trim();
      if ((valueTarget.startsWith("'") && valueTarget.endsWith("'")) ||
          (valueTarget.startsWith('"') && valueTarget.endsWith('"'))) {
        valueTarget = valueTarget.substring(1, valueTarget.length - 1);
      }

      Element? foundBySelector;
      void searchSelector(Element element) {
        if (foundBySelector != null) return;
        final typeName = element.widget.runtimeType.toString();
        final matchesType = _isMatchingType(typeName, typeTarget);

        if (matchesType) {
          if (valueTarget.isEmpty) {
            foundBySelector = element;
            return;
          }
          final text = _extractDescendantText(element);
          if (text.toLowerCase().contains(valueTarget.toLowerCase())) {
            foundBySelector = element;
            return;
          }
        }
        element.visitChildren(searchSelector);
      }

      searchSelector(root);
      if (foundBySelector != null) return foundBySelector;
    }

    // 3. Try finding an interactable button or tile whose descendant text matches query
    Element? foundButton;
    void searchButtonWithText(Element element) {
      if (foundButton != null) return;
      final typeName = element.widget.runtimeType.toString();
      if (_isButtonOrClickable(typeName)) {
        final text = _extractDescendantText(element);
        if (text.toLowerCase() == cleanQuery.toLowerCase() ||
            text.toLowerCase().contains(cleanQuery.toLowerCase())) {
          foundButton = element;
          return;
        }
      }
      element.visitChildren(searchButtonWithText);
    }

    searchButtonWithText(root);
    if (foundButton != null) return foundButton;

    // 4. Try matching Text / RichText / EditableText directly
    Element? foundText;
    void searchTextWidget(Element element) {
      if (foundText != null) return;
      final w = element.widget;
      if (w is Text) {
        final data = w.data ?? '';
        if (data.toLowerCase() == cleanQuery.toLowerCase() ||
            data.toLowerCase().contains(cleanQuery.toLowerCase())) {
          foundText = element;
          return;
        }
      } else if (w is RichText) {
        final plain = w.text.toPlainText();
        if (plain.toLowerCase() == cleanQuery.toLowerCase() ||
            plain.toLowerCase().contains(cleanQuery.toLowerCase())) {
          foundText = element;
          return;
        }
      } else if (w is EditableText) {
        final currentText = w.controller.text;
        if (currentText.toLowerCase().contains(cleanQuery.toLowerCase())) {
          foundText = element;
          return;
        }
      }
      element.visitChildren(searchTextWidget);
    }

    searchTextWidget(root);
    if (foundText != null) return foundText;

    // 5. Try Tooltip or Semantics label
    Element? foundTooltipOrSemantics;
    void searchTooltip(Element element) {
      if (foundTooltipOrSemantics != null) return;
      final w = element.widget;
      if (w is Tooltip && (w.message?.toLowerCase().contains(cleanQuery.toLowerCase()) ?? false)) {
        foundTooltipOrSemantics = element;
        return;
      }
      element.visitChildren(searchTooltip);
    }

    searchTooltip(root);
    if (foundTooltipOrSemantics != null) return foundTooltipOrSemantics;

    // 6. Try exact or suffix match on Widget Type (e.g. "FloatingActionButton")
    Element? foundByType;
    void searchByType(Element element) {
      if (foundByType != null) return;
      final typeName = element.widget.runtimeType.toString();
      if (typeName.toLowerCase() == cleanQuery.toLowerCase()) {
        foundByType = element;
        return;
      }
      element.visitChildren(searchByType);
    }

    searchByType(root);
    return foundByType;
  }

  /// Finds an [Element] in the tree whose widget key matches [keyString].
  ///
  /// Supports plain string keys, `ValueKey` (`['keyString']`), and
  /// `GlobalKey` (`[<'keyString'>]`) representations.
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

  /// Recursively counts all [Element] nodes in the subtree rooted at [element].
  static int countElements(Element element) {
    int count = 1;
    element.visitChildren((child) {
      count += countElements(child);
    });
    return count;
  }

  static bool _isButtonOrClickable(String typeName) {
    return typeName.contains('Button') ||
        typeName == 'InkWell' ||
        typeName == 'GestureDetector' ||
        typeName.contains('ListTile') ||
        typeName.contains('ActionChip') ||
        typeName.contains('IconButton');
  }

  static bool _isMatchingType(String elementTypeName, String targetType) {
    if (elementTypeName == targetType) return true;
    if (targetType == 'Button') return _isButtonOrClickable(elementTypeName);
    if (targetType == 'TextField' &&
        (elementTypeName == 'TextField' ||
            elementTypeName == 'TextFormField' ||
            elementTypeName == 'EditableText' ||
            elementTypeName == 'CupertinoTextField')) {
      return true;
    }
    return elementTypeName.endsWith(targetType);
  }

  static String _extractDescendantText(Element element) {
    final buffer = StringBuffer();
    void extract(Element e) {
      final w = e.widget;
      if (w is Text && w.data != null && w.data!.isNotEmpty) {
        buffer.write('${w.data} ');
        return;
      } else if (w is RichText) {
        buffer.write('${w.text.toPlainText()} ');
        return;
      } else if (w is Tooltip && w.message != null && w.message!.isNotEmpty) {
        buffer.write('${w.message} ');
      } else if (w is IconButton && w.tooltip != null && w.tooltip!.isNotEmpty) {
        buffer.write('${w.tooltip} ');
      }
      e.visitChildren(extract);
    }

    extract(element);
    return buffer.toString().trim();
  }

  static String? _computeSemanticSelector(Element element) {
    final type = element.widget.runtimeType.toString();
    final text = _extractDescendantText(element);

    if (_isButtonOrClickable(type)) {
      if (text.isNotEmpty) {
        final cleanText = text.length > 25 ? '${text.substring(0, 25)}...' : text;
        return "$type['$cleanText']";
      }
      return type;
    }

    if (type == 'TextField' || type == 'TextFormField' || type == 'EditableText') {
      if (text.isNotEmpty) {
        return "$type['$text']";
      }
      return type;
    }

    if (element.widget is Text && text.isNotEmpty) {
      final cleanText = text.length > 25 ? '${text.substring(0, 25)}...' : text;
      return "Text['$cleanText']";
    }

    if (element.widget is Tooltip) {
      final msg = (element.widget as Tooltip).message;
      if (msg != null && msg.isNotEmpty) {
        return "Tooltip['$msg']";
      }
    }

    return null;
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
      final dynamic loc = (element.widget as dynamic)._location;
      if (loc != null) {
        location = {
          'file': loc.file?.toString(),
          'line': loc.line,
          'column': loc.column,
        };
      }
    } catch (_) {}

    bool isSensitive = false;
    final keyStr = element.widget.key?.toString().toLowerCase() ?? '';
    if (keyStr.contains('password') ||
        keyStr.contains('pin') ||
        keyStr.contains('secret') ||
        keyStr.contains('token') ||
        keyStr.contains('ssn') ||
        keyStr.contains('cvv') ||
        keyStr.contains('card')) {
      isSensitive = true;
    }
    if (element.widget is EditableText && (element.widget as EditableText).obscureText) {
      isSensitive = true;
    }

    final selector = _computeSemanticSelector(element);
    final text = (element.widget is Text || element.widget is RichText)
        ? _extractDescendantText(element)
        : null;

    return {
      'type': element.widget.runtimeType.toString(),
      'key': element.widget.key?.toString(),
      if (selector != null) 'selector': selector,
      if (text != null && text.isNotEmpty && !isSensitive) 'text': text,
      'layout': layout,
      'location': location,
      if (isSensitive) 'isSensitive': true,
      if (currentDepth >= maxDepth && _hasChildren(element)) '_truncated': true,
      'children': children,
    };
  }

  static bool _hasChildren(Element element) {
    bool found = false;
    element.visitChildren((_) {
      found = true;
    });
    return found;
  }
}
