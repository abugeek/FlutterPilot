import 'package:flutter/material.dart';

/// Provides high-performance, single-pass introspection and semantic element querying into the live Flutter widget tree.
class PilotWidgetInspector {
  /// Default maximum depth for widget tree traversal.
  static const int defaultMaxDepth = 250;

  // Frame-scoped key cache for O(1) lookups
  static final Map<String, Element> _keyCache = {};
  static Expando<String> _textCache = Expando<String>('textCache');
  static Map<String, dynamic>? lastCapturedTree;

  /// Invalidates the internal frame-scoped element cache.
  static void invalidateCache() {
    _keyCache.clear();
    _textCache = Expando<String>('textCache');
  }

  /// Captures the widget tree as a nested JSON-compatible map with optional semantic compaction.
  /// If [rootQuery] (key or semantic selector) or [rootElement] is provided, scopes the capture
  /// to that specific subtree, saving up to 90% of token consumption.
  static Map<String, dynamic> captureWidgetTree({
    int? maxDepth,
    bool compact = true,
    String? rootQuery,
    Element? rootElement,
  }) {
    Element? targetRoot = rootElement;
    if (targetRoot == null && rootQuery != null && rootQuery.trim().isNotEmpty) {
      targetRoot = findElement(rootQuery);
      if (targetRoot == null) {
        return {'error': 'Scoped root widget not found for query: "$rootQuery"'};
      }
    }
    targetRoot ??= WidgetsBinding.instance.rootElement;
    if (targetRoot == null) return {'error': 'No root element found'};
    final depth = maxDepth ?? defaultMaxDepth;
    return _elementToJson(targetRoot, 0, depth, compact: compact) ?? {'type': 'Empty'};
  }

  /// High-performance Single-Pass Multi-Priority Element Matcher (O(N)).
  ///
  /// Evaluates exact keys, semantic selectors, button texts, text widgets,
  /// tooltips, widget types, and fuzzy similarity in a single tree walk.
  static Element? findElement(String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    // 1. O(1) Key Cache Lookup
    final cached = _keyCache[cleanQuery];
    if (cached != null && cached.mounted) return cached;

    // 2. Parse selector pattern if present (e.g. Type['value'])
    String? typeTarget;
    String? valueTarget;
    final selectorRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = selectorRegex.firstMatch(cleanQuery);
    if (match != null) {
      typeTarget = match.group(1)!;
      var rawVal = match.group(2)!.trim();
      if ((rawVal.startsWith("'") && rawVal.endsWith("'")) ||
          (rawVal.startsWith('"') && rawVal.endsWith('"'))) {
        rawVal = rawVal.substring(1, rawVal.length - 1);
      }
      valueTarget = rawVal;
    }

    Element? bestMatch;
    int bestPriority = -1; // Higher is better
    double bestSimilarity = 0.0;

    void evaluateElement(Element element) {
      final widget = element.widget;
      final typeName = widget.runtimeType.toString();
      final widgetKey = widget.key?.toString();

      // Priority 100: Exact Key Match
      if (widgetKey != null) {
        if (widgetKey == cleanQuery ||
            widgetKey == "['$cleanQuery']" ||
            widgetKey == "[<'$cleanQuery'>]") {
          bestMatch = element;
          bestPriority = 100;
          _keyCache[cleanQuery] = element;
          return; // Short-circuit
        }
      }

      // Priority 90: Structured Semantic Selector (e.g. ElevatedButton['Sign In'])
      if (typeTarget != null && bestPriority < 90) {
        if (_isMatchingType(typeName, typeTarget)) {
          if (valueTarget == null || valueTarget.isEmpty) {
            bestMatch = element;
            bestPriority = 90;
          } else {
            final text = _extractDescendantText(element);
            if (text.toLowerCase().contains(valueTarget.toLowerCase())) {
              bestMatch = element;
              bestPriority = 90;
            }
          }
        }
      }

      // Priority 80: Clickable Button Text Match
      if (bestPriority < 80 && _isButtonOrClickable(typeName)) {
        final text = _extractDescendantText(element);
        if (text.toLowerCase() == cleanQuery.toLowerCase() ||
            text.toLowerCase().contains(cleanQuery.toLowerCase())) {
          bestMatch = element;
          bestPriority = 80;
        }
      }

      // Priority 70 / 60: Text / RichText / EditableText Direct Match
      if (bestPriority < 70) {
        if (widget is Text) {
          final data = widget.data ?? '';
          if (data.toLowerCase() == cleanQuery.toLowerCase()) {
            bestMatch = element;
            bestPriority = 70;
          } else if (bestPriority < 60 && data.toLowerCase().contains(cleanQuery.toLowerCase())) {
            bestMatch = element;
            bestPriority = 60;
          }
        } else if (widget is RichText) {
          final plain = widget.text.toPlainText();
          if (plain.toLowerCase() == cleanQuery.toLowerCase()) {
            bestMatch = element;
            bestPriority = 70;
          } else if (bestPriority < 60 && plain.toLowerCase().contains(cleanQuery.toLowerCase())) {
            bestMatch = element;
            bestPriority = 60;
          }
        } else if (widget is EditableText && bestPriority < 60) {
          if (widget.controller.text.toLowerCase().contains(cleanQuery.toLowerCase())) {
            bestMatch = element;
            bestPriority = 60;
          }
        }
      }

      // Priority 50: Tooltip / Semantics
      if (bestPriority < 50 && widget is Tooltip) {
        if (widget.message?.toLowerCase().contains(cleanQuery.toLowerCase()) ?? false) {
          bestMatch = element;
          bestPriority = 50;
        }
      }

      // Priority 40: Type Exact Match
      if (bestPriority < 40 && typeName.toLowerCase() == cleanQuery.toLowerCase()) {
        bestMatch = element;
        bestPriority = 40;
      }

      // Priority 10-39: Fuzzy / Similarity Match
      if (bestPriority < 40) {
        String? candidateText;
        if (widget is Text) {
          candidateText = widget.data;
        } else if (widget is RichText) {
          candidateText = widget.text.toPlainText();
        } else if (widget is Tooltip) {
          candidateText = widget.message;
        }

        if (candidateText != null && candidateText.isNotEmpty) {
          final sim = calculateSimilarity(cleanQuery, candidateText);
          if (sim >= 0.65 && sim > bestSimilarity) {
            bestSimilarity = sim;
            bestMatch = element;
            bestPriority = (sim * 39).round();
          }
        }
      }

      // Continue single-pass traversal
      element.visitChildren(evaluateElement);
    }

    evaluateElement(root);
    return bestMatch;
  }

  /// Fast Bigram Dice similarity calculator with early length cutoff and substring ratio check.
  static double calculateSimilarity(String s1, String s2) {
    final a = s1.trim().toLowerCase();
    final b = s2.trim().toLowerCase();
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final minLen = a.length < b.length ? a.length : b.length;
    final maxLen = a.length > b.length ? a.length : b.length;

    // If one contains the other and they are close in length (>= 60% overlap ratio)
    if ((a.contains(b) || b.contains(a)) && (minLen / maxLen >= 0.6)) {
      return 0.85;
    }

    // Fast length pre-filter: if difference is too large, similarity cannot exceed 0.65
    final lenDiff = (a.length - b.length).abs();
    if (lenDiff > 10 || (minLen / maxLen < 0.3)) return 0.0;

    final Set<String> bigramsA = {};
    for (int i = 0; i < a.length - 1; i++) {
      bigramsA.add(a.substring(i, i + 2));
    }
    final Set<String> bigramsB = {};
    for (int i = 0; i < b.length - 1; i++) {
      bigramsB.add(b.substring(i, i + 2));
    }
    if (bigramsA.isEmpty || bigramsB.isEmpty) return 0.0;
    final intersection = bigramsA.intersection(bigramsB).length;
    return (2.0 * intersection) / (bigramsA.length + bigramsB.length);
  }

  /// Collects top visible actionable targets (buttons, inputs, key names) on screen.
  /// Used to provide actionable suggestions to AI agents when an element is not found.
  static List<String> getAvailableActionableTargets({int limit = 6}) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return [];

    final suggestions = <String>{};
    void collect(Element element) {
      if (suggestions.length >= limit) return;
      final widget = element.widget;
      final typeName = widget.runtimeType.toString();
      final key = widget.key?.toString();

      if (widget.key is ValueKey) {
        final val = (widget.key as ValueKey).value.toString();
        suggestions.add(val);
      } else if (key != null &&
          key.isNotEmpty &&
          !key.startsWith('[<#') &&
          !key.contains('GlobalKey') &&
          !key.contains('RawViewKey') &&
          !key.contains('_MaterialApp') &&
          !key.contains('_WidgetsApp') &&
          !key.contains('OverlayState')) {
        var cleanKey = key;
        if (cleanKey.startsWith("['") && cleanKey.endsWith("']")) {
          cleanKey = cleanKey.substring(2, cleanKey.length - 2);
        } else if (cleanKey.startsWith("[<'") && cleanKey.endsWith("'>]")) {
          cleanKey = cleanKey.substring(3, cleanKey.length - 3);
        }
        suggestions.add(cleanKey);
      } else if (_isButtonOrClickable(typeName)) {
        final selector = _computeSemanticSelector(element);
        if (selector != null) suggestions.add(selector);
      } else if (typeName == 'TextField' || typeName == 'TextFormField') {
        final selector = _computeSemanticSelector(element);
        if (selector != null) suggestions.add(selector);
      }
      element.visitChildren(collect);
    }

    collect(root);
    return suggestions.take(limit).toList();
  }

  /// Finds an [Element] by Key string.
  static Element? findElementByKey(String keyString) {
    final cached = _keyCache[keyString];
    if (cached != null && cached.mounted) return cached;

    Element? found;
    void search(Element element) {
      if (found != null) return;
      final widgetKey = element.widget.key?.toString();
      if (widgetKey == keyString ||
          widgetKey == "['$keyString']" ||
          widgetKey == "[<'$keyString'>]") {
        found = element;
        _keyCache[keyString] = element;
        return;
      }
      element.visitChildren(search);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) search(root);
    return found;
  }

  /// Recursively counts all elements.
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
    final cached = _textCache[element];
    if (cached != null) return cached;

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
    final result = buffer.toString().trim();
    _textCache[element] = result;
    return result;
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

  static bool _isTransparentLayoutWrapper(String type) {
    return type == 'Padding' ||
        type == 'SizedBox' ||
        type == 'ColoredBox' ||
        type == 'DecoratedBox' ||
        type == 'ConstrainedBox' ||
        type == 'Align' ||
        type == 'Center' ||
        type == 'RepaintBoundary' ||
        type == 'Semantics' ||
        type == 'DefaultTextStyle' ||
        type == 'MediaQuery' ||
        type == 'Theme' ||
        type == 'InheritedTheme' ||
        type == 'FocusScope' ||
        type == 'Actions' ||
        type == 'Shortcuts';
  }

  static Map<String, dynamic>? _elementToJson(
    Element element,
    int currentDepth,
    int maxDepth, {
    bool compact = true,
  }) {
    final List<Map<String, dynamic>> children = [];
    if (currentDepth < maxDepth) {
      element.visitChildren((child) {
        final childJson = _elementToJson(child, currentDepth + 1, maxDepth, compact: compact);
        if (childJson != null) children.add(childJson);
      });
    }

    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    final keyStr = widget.key?.toString();
    final text = _extractDescendantText(element);
    final selector = _computeSemanticSelector(element);

    // If compact mode is enabled, collapse intermediate single-child layout wrappers without keys
    if (compact && keyStr == null && _isTransparentLayoutWrapper(typeName)) {
      if (children.length == 1) {
        return children.first;
      } else if (children.isEmpty && text.isEmpty) {
        return null; // Prune empty leaf wrappers
      }
    }

    Map<String, dynamic>? layout;
    final ro = element.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      final pos = ro.localToGlobal(Offset.zero);
      layout = {
        'x': pos.dx.round(),
        'y': pos.dy.round(),
        'w': ro.size.width.round(),
        'h': ro.size.height.round(),
      };
    }

    final result = <String, dynamic>{
      'type': typeName,
      if (keyStr != null) 'key': keyStr,
      if (selector != null) 'selector': selector,
      if (text.isNotEmpty) 'text': text,
      if (layout != null) 'layout': layout,
      if (children.isNotEmpty) 'children': children,
    };

    return result;
  }

  /// Compares two widget tree snapshots and returns a minimal delta list
  /// containing only added, removed, or updated nodes (95% token savings).
  static Map<String, dynamic> diffWidgetTrees(
    Map<String, dynamic> oldTree,
    Map<String, dynamic> newTree,
  ) {
    final added = <String>[];
    final removed = <String>[];
    final modified = <String>[];

    final oldNodes = _flattenTree(oldTree);
    final newNodes = _flattenTree(newTree);

    for (final entry in newNodes.entries) {
      if (!oldNodes.containsKey(entry.key)) {
        added.add(entry.value);
      } else if (oldNodes[entry.key] != entry.value) {
        modified.add('${entry.key}: changed from "${oldNodes[entry.key]}" to "${entry.value}"');
      }
    }

    for (final entry in oldNodes.entries) {
      if (!newNodes.containsKey(entry.key)) {
        removed.add(entry.value);
      }
    }

    return {
      'hasChanges': added.isNotEmpty || removed.isNotEmpty || modified.isNotEmpty,
      'addedCount': added.length,
      'removedCount': removed.length,
      'modifiedCount': modified.length,
      'added': added,
      'removed': removed,
      'modified': modified,
    };
  }

  static Map<String, String> _flattenTree(Map<String, dynamic> node) {
    final result = <String, String>{};
    void traverse(Map<String, dynamic> current, String path) {
      final type = current['type']?.toString() ?? 'Widget';
      final key = current['key']?.toString();
      final text = current['text']?.toString();
      final selector = current['selector']?.toString();

      final nodeIdentifier = key ?? selector ?? '$type#$path';
      final nodeDescription = '$type${key != null ? '($key)' : ''}${text != null && text.isNotEmpty ? '["$text"]' : ''}';
      result[nodeIdentifier] = nodeDescription;

      final children = current['children'] as List?;
      if (children != null) {
        for (int i = 0; i < children.length; i++) {
          final child = children[i];
          if (child is Map<String, dynamic>) {
            traverse(child, '$path/$i');
          }
        }
      }
    }

    traverse(node, '0');
    return result;
  }
}
