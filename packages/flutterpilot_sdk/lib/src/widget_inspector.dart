import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'ai_overlay_manager.dart';
import 'hit_test_utils.dart';

extension on Element {
  /// On-screen children, minus FlutterPilot's own overlay (the AI tap badge).
  void visitScreenChildren(ElementVisitor visitor) =>
      debugVisitOnstageChildren((c) {
        if (c.widget is! AiOverlayMarker) visitor(c);
      });
}

/// Provides high-performance, single-pass introspection and semantic element querying into the live Flutter widget tree.
/// All screen queries traverse with [Element.debugVisitOnstageChildren] (what
/// flutter_test's finders do by default): routes covered by an opaque route
/// and hidden IndexedStack tabs are skipped, so finders, assertions and trees
/// only ever see what is actually on screen. Available in all build modes.
class PilotWidgetInspector {
  /// Default maximum depth for widget tree traversal.
  static const int defaultMaxDepth = 250;

  static Map<String, dynamic>? lastCapturedTree;

  /// Extracts the inner string from a key, stripping [<'...'>] wrappers.
  static String? extractCleanKey(Key? key) => _extractCleanKey(key);
  static String? _extractCleanKey(Key? key) {
    if (key == null) return null;
    if (key is ValueKey) {
      return key.value.toString();
    }
    final raw = key.toString();
    final match = RegExp(r"\[<'(.*)'>\]|\[<(.*)>\]|\['(.*)'\]").firstMatch(raw);
    if (match != null) {
      return match.group(1) ?? match.group(2) ?? match.group(3) ?? raw;
    }
    return raw;
  }

  /// Extracts the Semantics identifier (Flutter 3.19+) if present.
  static String? _extractIdentifier(Widget widget) {
    if (widget is Semantics) {
      final id = widget.properties.identifier;
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
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
    if (targetRoot == null &&
        rootQuery != null &&
        rootQuery.trim().isNotEmpty) {
      targetRoot = findElement(rootQuery);
      if (targetRoot == null) {
        return {
          'error': 'Scoped root widget not found for query: "$rootQuery"',
        };
      }
    }
    targetRoot ??= WidgetsBinding.instance.rootElement;
    if (targetRoot == null) return {'error': 'No root element found'};
    final depth = maxDepth ?? defaultMaxDepth;
    if (compact) {
      final nodes = _summaryNodes(targetRoot, 0, depth);
      return nodes.length == 1
          ? nodes.first
          : {'type': 'Root', 'children': nodes};
    }
    return _elementToJson(targetRoot, 0, depth, compact: false) ??
        {'type': 'Empty'};
  }

  /// Summary tree, like DevTools: keeps widgets created by the app's own code,
  /// keyed widgets and Text; flattens framework/package internals into their
  /// parent. Depth counts kept nodes only, so app widgets are always reached.
  static List<Map<String, dynamic>> _summaryNodes(
    Element element,
    int depth,
    int maxDepth,
  ) {
    final widget = element.widget;
    final local = debugIsWidgetLocalCreation(widget);
    final key = widget.key;
    // Framework widgets carry internal keys (LayoutId slots, branch proxies);
    // only surface keys the app wrote or plain String/num ValueKeys.
    final userKey =
        key != null &&
        key is! GlobalKey &&
        (local ||
            (key is ValueKey && (key.value is String || key.value is num)));
    final keyStr = userKey ? key.toString() : null;
    final keep = keyStr != null || widget is Text || local;

    final childDepth = keep ? depth + 1 : depth;
    final children = <Map<String, dynamic>>[];
    if (childDepth <= maxDepth) {
      element.visitScreenChildren(
        (c) => children.addAll(_summaryNodes(c, childDepth, maxDepth)),
      );
    }
    if (!keep) return children;

    final typeName = widget.runtimeType.toString();
    var text = '';
    if (widget is Text) {
      text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    } else if (widget is EditableText) {
      text = widget.controller.text;
    } else if (_isButtonOrClickable(typeName) && children.isEmpty) {
      text = _extractDescendantText(element);
    }
    final ro = element.renderObject;
    final selector = _computeSemanticSelector(element);
    final value = _controlValue(element);
    return [
      {
        'type': typeName,
        'key': ?keyStr,
        'selector': ?selector,
        if (text.isNotEmpty) 'text': text,
        'value': ?value,
        if (ro is RenderBox && ro.hasSize && widget is! Text)
          'layout': () {
            final pos = ro.localToGlobal(Offset.zero);
            return {
              'x': pos.dx.round(),
              'y': pos.dy.round(),
              'w': ro.size.width.round(),
              'h': ro.size.height.round(),
            };
          }(),
        if (children.isNotEmpty) 'children': children,
        if (childDepth > maxDepth) 'truncated': true,
      },
    ];
  }

  /// The state of a switch, checkbox or slider at [element] or, for an app
  /// widget wrapping one (a SwitchListTile), the first one inside it: a
  /// toggle changes nothing else a diff could see.
  static Object? _controlValue(Element element) {
    Object? valueOf(Widget w) => switch (w) {
      Switch s => s.value,
      SwitchListTile s => s.value,
      CupertinoSwitch s => s.value,
      Checkbox c => c.value,
      CheckboxListTile c => c.value,
      Slider s => s.value,
      _ => null,
    };
    var value = valueOf(element.widget);
    if (value != null) return value;
    var budget = 12;
    void visit(Element e) {
      if (value != null || --budget < 0) return;
      value = valueOf(e.widget);
      if (value == null) e.visitChildren(visit);
    }

    element.visitChildren(visit);
    return value;
  }

  /// High-performance Hierarchical & Positional Element Matcher (O(N)).
  ///
  /// Supports:
  /// - Exact keys: `"login_btn"`
  /// - Semantic selectors: `"Button['Submit']"`
  /// - Chained selectors: `"Card['order_1'] -> Button['Cancel']"`
  /// - Positional selectors: `"ListTile:nth-child(2)"` or `"Button[index=1]"`
  /// Set when the last [findElement] refused an ambiguous query.
  static String? lastAmbiguity;

  static Element? findElement(String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    // 2. Chained Hierarchy Evaluation ("Parent -> Child")
    if (cleanQuery.contains('->')) {
      final parts = cleanQuery
          .split('->')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      Element? currentScope = root;
      for (final part in parts) {
        if (currentScope == null) return null;
        currentScope = _findSingleElementUnder(currentScope, part);
      }
      return currentScope;
    }

    return _findSingleElementUnder(root, cleanQuery);
  }

  static Element? _findSingleElementUnder(Element root, String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    // Check positional indexing (e.g. ListTile:nth-child(2) or Button[index=1])
    int? targetIndex;
    var queryToSearch = cleanQuery;
    final indexMatch = RegExp(
      r':nth-child\((\d+)\)|\[index=(\d+)\]',
    ).firstMatch(cleanQuery);
    if (indexMatch != null) {
      final idxStr = indexMatch.group(1) ?? indexMatch.group(2);
      targetIndex = int.tryParse(idxStr ?? '');
      queryToSearch = cleanQuery.replaceFirst(indexMatch.group(0)!, '').trim();
    }

    // Parse selector pattern if present (e.g. Type['value'])
    String? typeTarget;
    String? valueTarget;
    final selectorRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = selectorRegex.firstMatch(queryToSearch);
    if (match != null) {
      typeTarget = match.group(1)!;
      var rawVal = match.group(2)!.trim();
      if ((rawVal.startsWith("'") && rawVal.endsWith("'")) ||
          (rawVal.startsWith('"') && rawVal.endsWith('"'))) {
        rawVal = rawVal.substring(1, rawVal.length - 1);
      }
      valueTarget = rawVal;
    }

    final matches = <Element>[];
    final bestElements = <Element>[];
    Element? bestMatch;
    int bestPriority = -1; // Higher is better
    bool foundExact = false;

    void evaluateElement(Element element) {
      if (foundExact) return;

      final widget = element.widget;
      final typeName = widget.runtimeType.toString();
      final widgetKey = widget.key?.toString();

      final cleanKey = _extractCleanKey(widget.key);
      final id = _extractIdentifier(widget);
      // Hit-testing is the expensive part: only do it for elements that match.
      bool? hittable;
      bool isHittable() => hittable ??= HitTestUtils.isElementHittable(element);

      // Visible (hittable) elements win ties, so a widget on the route or
      // dialog underneath never beats the one the user actually sees.
      void consider(int priority) {
        final effective = priority + (isHittable() ? 5 : 0);
        if (effective > bestPriority) {
          bestMatch = element;
          bestPriority = effective;
          bestElements
            ..clear()
            ..add(element);
        } else if (effective == bestPriority) {
          bestElements.add(element);
        }
        matches.add(element);
      }

      // Priority 100: Exact Key Match or Semantics Identifier Match
      if (widgetKey != null || cleanKey != null || id != null) {
        final keyMatches =
            widgetKey == queryToSearch ||
            widgetKey == "['$queryToSearch']" ||
            widgetKey == "[<'$queryToSearch'>]" ||
            (cleanKey != null && cleanKey == queryToSearch);
        final idMatches = id != null && id == queryToSearch;

        if (keyMatches || idMatches) {
          final priority = (keyMatches ? 100 : 98) + (isHittable() ? 5 : 0);
          if (priority > bestPriority) {
            bestMatch = element;
            bestPriority = priority;
            matches.add(element);
            if (targetIndex == null && isHittable()) {
              foundExact = true;
              return;
            }
          }
        }
      }

      // Priority 96 / 90: Structured Semantic Selector (e.g.
      // ElevatedButton['Sign In']): the exact value beats a substring even
      // when the substring match is the visible one (+5).
      if (typeTarget != null &&
          (targetIndex != null || bestPriority < 96 + 5)) {
        if (_isMatchingType(typeName, typeTarget)) {
          if (valueTarget == null || valueTarget.isEmpty) {
            consider(90);
          } else {
            final label = _describeDescendants(element);
            final text = label.text.toLowerCase();
            final value = valueTarget.toLowerCase();
            final ownLabel = widget is Tooltip
                ? widget.message?.toLowerCase()
                : null;
            if (ownLabel == value || (text == value && !label.glyphOnly)) {
              consider(96);
            } else if (text == value) {
              // Only an icon's name: IconButton['settings'] on a button
              // without a tooltip, beaten by a real label.
              consider(93);
            } else if (text.contains(value)) {
              consider(90);
            }
          }
        }
      }

      // Priority 80: Clickable Button Text Match
      if (_isButtonOrClickable(typeName) &&
          (targetIndex != null || bestPriority < 80 + 5)) {
        final label = _describeDescendants(element);
        final text = label.text.toLowerCase();
        final q = queryToSearch.toLowerCase();
        if (label.glyphOnly) {
          // Only an icon's name ("menu" for Icons.menu): a weak label, so
          // any real text or tooltip that matches wins over it.
          if (text == q) consider(67);
        } else if (text == q) {
          consider(80);
        } else if (text.contains(q)) {
          consider(69);
        }
      }

      // Priority 75: a text field's label / hint / placeholder. The label is a
      // sibling of the input, so resolving to the label Text would leave
      // enter_text without a field and make tap_widget report it covered.
      if ((targetIndex != null || bestPriority < 75 + 5) &&
          (widget is TextField || widget is CupertinoTextField)) {
        final q = queryToSearch.toLowerCase();
        final names = widget is TextField
            ? [widget.decoration?.labelText, widget.decoration?.hintText]
            : [(widget as CupertinoTextField).placeholder];
        if (names.any((n) => n != null && n.toLowerCase() == q)) {
          consider(75);
        }
      }

      // Priority 70 / 60: Text / RichText / EditableText Direct Match
      if (targetIndex != null || bestPriority < 70 + 5) {
        if (widget is Text && widget.data != null) {
          if (widget.data!.toLowerCase() == queryToSearch.toLowerCase()) {
            consider(70);
          } else if ((targetIndex != null || bestPriority < 60 + 5) &&
              widget.data!.toLowerCase().contains(
                queryToSearch.toLowerCase(),
              )) {
            consider(60);
          }
        } else if (widget is RichText) {
          final plain = widget.text.toPlainText();
          if (plain.toLowerCase() == queryToSearch.toLowerCase()) {
            consider(70);
          } else if ((targetIndex != null || bestPriority < 60 + 5) &&
              plain.toLowerCase().contains(queryToSearch.toLowerCase())) {
            consider(60);
          }
        } else if (widget is EditableText &&
            (targetIndex != null || bestPriority < 60 + 5)) {
          if (widget.controller.text.toLowerCase().contains(
            queryToSearch.toLowerCase(),
          )) {
            consider(60);
          }
        }
      }

      // Priority 50: Tooltip / Semantics
      if ((targetIndex != null || bestPriority < 57 + 5) && widget is Tooltip) {
        final message = widget.message?.toLowerCase();
        final q = queryToSearch.toLowerCase();
        if (message == q) {
          consider(57);
        } else if ((targetIndex != null || bestPriority < 50 + 5) &&
            (message?.contains(q) ?? false)) {
          consider(50);
        }
      }

      // Priority 40: Type Exact Match
      if ((targetIndex != null || bestPriority < 40 + 5) &&
          typeName.toLowerCase() == queryToSearch.toLowerCase()) {
        consider(40);
      }

      // Continue single-pass traversal if not already resolved by exact key
      if (!foundExact) {
        element.visitScreenChildren(evaluateElement);
      }
    }

    evaluateElement(root);

    if (targetIndex != null) {
      if (targetIndex >= 0 && targetIndex < matches.length) {
        return matches[targetIndex];
      }
      return null;
    }

    // Substring-only tiers (90 Type['value'], 69 button text, 60 text,
    // 50 tooltip, ±5 boost):
    // several different texts contain the query, so any pick is a guess.
    final raw =
        bestPriority >= 5 &&
            bestMatch != null &&
            HitTestUtils.isElementHittable(bestMatch!)
        ? bestPriority - 5
        : bestPriority;
    lastAmbiguity = null;
    final bestTexts = (raw == 90 || raw == 69 || raw == 60 || raw == 50)
        ? {for (final e in bestElements) _labelOf(e)}
        : const <String>{};
    if (bestTexts.length > 1) {
      lastAmbiguity =
          '"$cleanQuery" matches several widgets: '
          '${bestTexts.take(5).map((t) => '"$t"').join(', ')}. '
          'Use the exact text, a key, or a Type[\'text\'] selector.';
      return null;
    }
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

    // What can be tapped first, by the name tap_widget accepts; then other
    // widgets the app keyed (a card to scope a search to).
    final suggestions = <String>{
      for (final e in getInteractiveElements())
        (e['key'] ?? e['text'] ?? e['type']) as String,
    };
    void collect(Element element) {
      if (suggestions.length >= limit) return;
      final key = _userKey(element);
      if (key != null && key.isNotEmpty) suggestions.add(key);
      element.visitScreenChildren(collect);
    }

    if (suggestions.length < limit) collect(root);
    return suggestions.take(limit).toList();
  }

  /// Finds an [Element] by Key string.
  static Element? findElementByKey(String keyString) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
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
      element.visitScreenChildren(search);
    }

    search(root);
    return found;
  }

  /// Recursively counts all elements.
  static int countElements(Element element) {
    int count = 1;
    element.visitScreenChildren((child) {
      count += countElements(child);
    });
    return count;
  }

  static bool _isButtonOrClickable(String typeName) {
    // IconButtonTheme, ElevatedButtonTheme… only style their buttons.
    if (typeName.endsWith('Theme')) return false;
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

  static const Map<int, String> _commonIconNames = {
    0xe57f: 'settings',
    0xe567: 'search',
    0xf012d: 'search',
    0xe3dc: 'menu',
    0xe16a: 'close',
    0xe047: 'add',
    0xe156: 'check',
    0xe1bb: 'delete',
    0xe21a: 'edit',
    0xe092: 'arrow_back',
    0xe095: 'arrow_forward',
    0xe514: 'refresh',
    0xe3e3: 'more_vert',
    0xe3e1: 'more_horiz',
    0xe25b: 'favorite',
    0xe25c: 'favorite_border',
    0xe318: 'home',
    0xe491: 'person',
    0xe580: 'share',
    0xe44f: 'notifications',
    0xe59c: 'shopping_cart',
    0xe6c5: 'visibility',
    0xe6c6: 'visibility_off',
    0xe52f: 'send',
    0xe33c: 'info',
    0xe306: 'help',
    0xe5f9: 'star',
    0xe2c7: 'filter_list',
    0xe158: 'check_box',
    0xe159: 'check_box_outline_blank',
    0xe3ab: 'lock',
    0xe3ac: 'lock_open',
    0xe3a8: 'location_on',
    0xe199: 'content_copy',
    0xe204: 'done',
    0xe205: 'done_all',
  };

  static String _resolveIconName(IconData icon) {
    final known = _commonIconNames[icon.codePoint];
    if (known != null) return known;
    return 'Icon#${icon.codePoint.toRadixString(16)}';
  }

  static String _extractDescendantText(
    Element element, {
    Set<Element> skip = const {},
  }) => _describeDescendants(element, skip: skip).text;

  /// A widget's own label for ambiguity messages: a Tooltip's message,
  /// otherwise the text under it.
  static String _labelOf(Element element) {
    final w = element.widget;
    if (w is Tooltip && w.message != null) return w.message!;
    return _extractDescendantText(element);
  }

  /// The text under [element], leaving out the subtrees in [skip];
  /// `glyphOnly` when it is only icon names.
  static ({String text, bool glyphOnly}) _describeDescendants(
    Element element, {
    Set<Element> skip = const {},
  }) {
    // Ordered and de-duplicated: widgets like NavigationDestination render
    // their label twice (text + tooltip).
    final parts = <String>{};
    // Glyph names ("delete", "add") only label icon-only widgets; next to a
    // tooltip or text they'd just repeat it ("Delete delete").
    final iconNames = <String>{};
    void add(String? t) {
      final v = t?.trim();
      if (v != null && v.isNotEmpty) parts.add(v);
    }

    void extract(Element e) {
      if (skip.contains(e)) return;
      final w = e.widget;
      if (w is Text) {
        add(w.data ?? w.textSpan?.toPlainText());
        return;
      } else if (w is RichText) {
        add(w.text.toPlainText());
        return;
      } else if (w is Tooltip) {
        add(w.message);
      } else if (w is IconButton) {
        add(w.tooltip);
      } else if (w is Icon) {
        // Only meaningful names; unknown glyphs would just add "Icon#e5d2" noise.
        if (w.semanticLabel != null) {
          add(w.semanticLabel);
        } else if (w.icon != null) {
          final name = _resolveIconName(w.icon!);
          if (!name.startsWith('Icon#')) iconNames.add(name);
        }
        return; // its child RichText is just the private-use glyph character
      }
      e.visitScreenChildren(extract);
    }

    extract(element);
    return parts.isEmpty
        ? (text: iconNames.join(' '), glyphOnly: iconNames.isNotEmpty)
        : (text: parts.join(' '), glyphOnly: false);
  }

  static String? _computeSemanticSelector(Element element) {
    final type = element.widget.runtimeType.toString();
    final text = _extractDescendantText(element);

    if (_isButtonOrClickable(type)) {
      if (text.isNotEmpty) {
        final cleanText = text.length > 25
            ? '${text.substring(0, 25)}...'
            : text;
        return "$type['$cleanText']";
      }
      return type;
    }

    if (type == 'TextField' ||
        type == 'TextFormField' ||
        type == 'EditableText') {
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
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    final keyStr = widget.key?.toString();

    // Early Depth Exit: immediately short-circuit if maxDepth reached
    if (currentDepth >= maxDepth) {
      return {'type': typeName, 'key': ?keyStr, 'truncated': true};
    }

    final List<Map<String, dynamic>> children = [];
    element.visitScreenChildren((child) {
      final childJson = _elementToJson(
        child,
        currentDepth + 1,
        maxDepth,
        compact: compact,
      );
      if (childJson != null) children.add(childJson);
    });

    // Scoped Direct Text Extraction: avoid deep descendant walk on layout wrappers
    String text = '';
    if (widget is Text) {
      text = widget.data ?? '';
    } else if (widget is RichText) {
      text = widget.text.toPlainText();
    } else if (widget is Tooltip) {
      text = widget.message ?? '';
    } else if (widget is EditableText) {
      text = widget.controller.text;
    } else if (_isButtonOrClickable(typeName)) {
      text = _extractDescendantText(element);
    }

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
      'key': ?keyStr,
      'selector': ?selector,
      if (text.isNotEmpty) 'text': text,
      'layout': ?layout,
      if (children.isNotEmpty) 'children': children,
    };

    return result;
  }

  /// Maximum sample entries kept per added/removed/modified list in
  /// [diffWidgetTrees]. Counts are always exact; only the listed examples
  /// are capped, so a bulk list rebuild (e.g. 500 rows) reports its size
  /// instead of returning hundreds of unbounded strings.
  static const int defaultDiffSampleLimit = 8;

  /// Compares two widget tree snapshots and returns a minimal delta list
  /// containing only added, removed, or updated nodes (95% token savings).
  ///
  /// [sampleLimit] bounds how many example entries are included per
  /// category; `addedCount`/`removedCount`/`modifiedCount` always reflect
  /// the true totals even when the sample lists are truncated.
  static Map<String, dynamic> diffWidgetTrees(
    Map<String, dynamic> oldTree,
    Map<String, dynamic> newTree, {
    int sampleLimit = defaultDiffSampleLimit,
  }) {
    final added = <String>[];
    final removed = <String>[];
    final modified = <String>[];

    final oldNodes = _flattenTree(oldTree);
    final newNodes = _flattenTree(newTree);

    for (final entry in newNodes.entries) {
      final oldNode = oldNodes[entry.key];
      if (oldNode == null) {
        added.add(entry.value.description);
      } else if (oldNode.description != entry.value.description) {
        modified.add(
          '${entry.value.label}: changed from "${oldNode.description}" to "${entry.value.description}"',
        );
      }
    }

    for (final entry in oldNodes.entries) {
      if (!newNodes.containsKey(entry.key)) {
        removed.add(entry.value.description);
      }
    }

    final totalChanges = added.length + removed.length + modified.length;
    final truncated =
        added.length > sampleLimit ||
        removed.length > sampleLimit ||
        modified.length > sampleLimit;

    return {
      'hasChanges': totalChanges > 0,
      'addedCount': added.length,
      'removedCount': removed.length,
      'modifiedCount': modified.length,
      'added': added.take(sampleLimit).toList(),
      'removed': removed.take(sampleLimit).toList(),
      'modified': modified.take(sampleLimit).toList(),
      'truncated': truncated,
      if (truncated)
        'note':
            '$totalChanges total node changes — likely a bulk rebuild (e.g. a list). '
            'Showing up to $sampleLimit samples per category; call get_widget_tree '
            'for full detail if the samples are not enough to confirm the change.',
    };
  }

  static Map<String, ({String label, String description})> _flattenTree(
    Map<String, dynamic> node,
  ) {
    final result = <String, ({String label, String description})>{};
    void traverse(Map<String, dynamic> current, String path) {
      final type = current['type']?.toString() ?? 'Widget';
      final key = current['key']?.toString();
      final text = current['text']?.toString();
      final selector = current['selector']?.toString();
      final value = current['value'];

      // Keys and semantic selectors are not guaranteed to be unique. Keep the
      // structural path in the identity so repeated list rows do not overwrite
      // one another in the diff map — but keep that path out of the
      // human-readable label; it's meaningless to a caller.
      final semanticIdentity = key ?? selector ?? type;
      final nodeIdentifier = '$path:$semanticIdentity';
      final nodeDescription =
          '$type${key != null ? '($key)' : ''}${text != null && text.isNotEmpty ? '["$text"]' : ''}'
          '${value != null ? ' = $value' : ''}';
      result[nodeIdentifier] = (
        label: semanticIdentity,
        description: nodeDescription,
      );

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

  /// Returns a concise, high-signal list of all interactive or text elements
  /// that are currently visible and hittable on screen.
  static List<Map<String, dynamic>> getInteractiveElements() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return [];

    // Find real gesture handlers, remembering the nearest widget from the
    // app's own code (ListTile, ChoiceChip, NavigationDestination...) and
    // the framework widgets in between.
    final hits = <({Element primitive, Element? owner, List<Element> chain})>[];
    final path = <Element>[];
    // Only the outermost tap handler per owner counts: an InkWell's inner
    // GestureDetector is the same control.
    void visit(Element element, Element? owner, int ownerDepth, bool inHit) {
      final widget = element.widget;
      if (debugIsWidgetLocalCreation(widget)) {
        owner = element;
        ownerDepth = path.length;
        inHit = false;
      }
      path.add(element);
      if (!inHit &&
          _isGesturePrimitive(widget) &&
          HitTestUtils.isElementHittable(element)) {
        hits.add((
          primitive: element,
          owner: owner,
          chain: path.sublist(owner == null ? 0 : ownerDepth + 1),
        ));
        // A drag surface can hold separate tap controls (the drawer's scrim).
        inHit = !_isDragOnly(widget);
      }
      element.visitScreenChildren((c) => visit(c, owner, ownerDepth, inHit));
      path.removeLast();
    }

    visit(root, null, 0, false);

    final perOwner = <Element, int>{};
    for (final h in hits) {
      if (h.owner != null) perOwner[h.owner!] = (perOwner[h.owner!] ?? 0) + 1;
    }

    // Report each handler under the app widget that owns it, so labels and
    // keys are the ones the developer wrote — unless that widget is a
    // container (Scaffold, AppBar, TabBar) holding several handlers or a
    // small control of its own: then under that control (DrawerButton) or
    // the handler itself, so the label isn't every text in the container.
    final targets = <Element>[];
    for (final h in hits) {
      final owner = h.owner;
      Element? target;
      if (owner != null &&
          perOwner[owner] == 1 &&
          // An app widget above an Overlay (MaterialApp) only hosts what
          // is shown there — text selection handles, menus — it isn't it.
          !h.chain.any((e) => e.widget is Overlay) &&
          (_coversMostOf(h.primitive, owner) ||
              (!_isDragOnly(h.primitive.widget) &&
                  !h.chain.any(_isNamedControl)))) {
        target = owner;
      } else {
        target = h.chain.firstWhere(_isNamedControl, orElse: () => h.primitive);
        // Framework drag surfaces (drawer edge, scroll views) aren't targets.
        if (target == h.primitive && _isDragOnly(target.widget)) continue;
      }
      if (!targets.contains(target)) targets.add(target);
    }

    final elements = <Map<String, dynamic>>[];
    final byRect = <String, int>{};
    for (final target in targets) {
      final ro = target.renderObject;
      if (ro is! RenderBox || !ro.hasSize) continue;
      // Text of other targets inside this one is theirs: a container whose
      // label would only repeat its children's (a drawer scrim, a card
      // around buttons) has none of its own.
      final nested = <Element>{};
      void findNested(Element e) {
        if (targets.contains(e)) {
          nested.add(e);
        } else {
          e.visitScreenChildren(findNested);
        }
      }

      target.visitScreenChildren(findNested);
      final key = _userKey(target);
      final text = _extractDescendantText(target, skip: nested);
      if (key == null && text.isEmpty && nested.isNotEmpty) continue;
      // A framework handler with no key or text can't be addressed anyway.
      if (key == null &&
          text.isEmpty &&
          !debugIsWidgetLocalCreation(target.widget) &&
          !_isNamedControl(target)) {
        continue;
      }
      final pos = ro.localToGlobal(Offset.zero);
      final rect =
          '${pos.dx.round()},${pos.dy.round()},${ro.size.width.round()},${ro.size.height.round()}';
      final entry = <String, dynamic>{
        'type': target.widget.runtimeType.toString(),
        'key': ?key,
        if (text.isNotEmpty) 'text': text,
        'bounds': {
          'x': pos.dx.round(),
          'y': pos.dy.round(),
          'width': ro.size.width.round(),
          'height': ro.size.height.round(),
        },
      };
      final existing = byRect[rect];
      if (existing == null) {
        byRect[rect] = elements.length;
        elements.add(entry);
      } else if (key != null && elements[existing]['key'] == null) {
        elements[existing] = entry; // prefer the keyed widget
      }
    }
    return elements;
  }

  /// A key the developer can pass back to a finder: not framework-internal
  /// ones (GlobalObjectKey, UniqueKey, LayoutId slots like
  /// `_ScaffoldSlot.body`, `StandardComponentType.drawerButton`).
  static String? _userKey(Element element) {
    final key = element.widget.key;
    if (key == null || key is GlobalKey || key is UniqueKey) return null;
    if (!debugIsWidgetLocalCreation(element.widget)) {
      // Framework widgets: only a plain string could have come from the app.
      return key is ValueKey && key.value is String
          ? key.value as String
          : null;
    }
    final value = key is ValueKey
        ? key.value
        : key is ObjectKey
        ? key.value
        : null;
    if (value != null &&
        value is! String &&
        value is! num &&
        value.runtimeType.toString().startsWith('_')) {
      return null;
    }
    return _extractCleanKey(key);
  }

  /// The handler fills most of [owner], so it is that widget's own tap area
  /// (a Card's InkWell), not one small control inside it.
  static bool _coversMostOf(Element primitive, Element owner) {
    final p = primitive.renderObject;
    final o = owner.renderObject;
    if (p is! RenderBox || o is! RenderBox || !p.hasSize || !o.hasSize) {
      return false;
    }
    return p.size.width * p.size.height * 4 >= o.size.width * o.size.height;
  }

  /// A GestureDetector that only handles drags (drawer edge, scrollables).
  static bool _isDragOnly(Widget w) =>
      w is GestureDetector &&
      w.onTap == null &&
      w.onTapDown == null &&
      w.onTapUp == null &&
      w.onLongPress == null &&
      w.onLongPressStart == null &&
      w.onDoubleTap == null &&
      w.onSecondaryTap == null;

  /// A public framework control a handler belongs to (DrawerButton,
  /// BackButton, IconButton, ListTile, Chip...).
  static bool _isNamedControl(Element e) {
    final name = e.widget.runtimeType.toString().split('<').first;
    return !name.startsWith('_') &&
        (name.endsWith('Button') ||
            name.endsWith('ListTile') ||
            name.endsWith('Chip'));
  }

  /// Widgets that actually receive taps/text/drags.
  static bool _isGesturePrimitive(Widget w) =>
      w is InkResponse ||
      w is GestureDetector ||
      w is EditableText ||
      w.runtimeType.toString() == 'Checkbox' ||
      w.runtimeType.toString() == 'Switch' ||
      w.runtimeType.toString() == 'Radio' ||
      w.runtimeType.toString() == 'Slider';
}
