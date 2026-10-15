import 'package:flutter/material.dart';

import 'source_locator.dart';

/// Records what the agent did and checked as steps for a generated
/// `integration_test` (ROADMAP §6). Each step that acts on a widget carries
/// the Dart source of a `flutter_test` finder that finds that widget, and
/// only it, on the screen it was on.
class TestRecorder {
  static bool active = false;
  static final List<Map<String, dynamic>> steps = [];

  /// Obscured text is kept here, not in [steps]: the generated test reads
  /// it from a `--dart-define` so passwords never land in a file.
  static final List<String> secrets = [];

  static void start() {
    active = true;
    steps.clear();
    secrets.clear();
  }

  static void add(
    String type, {
    Element? element,
    bool field = false,
    Map<String, dynamic> data = const {},
  }) {
    if (!active) return;
    steps.add({
      'type': type,
      if (element != null) ...TestFinder.of(element, field: field),
      ...data,
    });
  }

  /// [shown] was scrolled into view: the test scrolls the same list until
  /// it is built and visible.
  static void addScroll(Element shown) {
    if (!active) return;
    Element? scrollable;
    shown.visitAncestorElements((a) {
      if (a.widget is Scrollable) scrollable = a;
      return scrollable == null;
    });
    add(
      'scrollTo',
      element: shown,
      data: {
        if (scrollable != null)
          'scrollable': TestFinder.of(scrollable!)['finder'],
      },
    );
  }

  /// A tap at a point, as a tap on the control drawn there (a point on
  /// the screen is not stable between runs); the point only if none is.
  static void addTapAt(Offset position) {
    if (!active) return;
    final hit = SourceLocator.elementAt(position);
    Element? control;
    var depth = 0;
    hit?.visitAncestorElements((a) {
      if (_tappable(a.widget)) control = a;
      return control == null && ++depth < 16;
    });
    if (control == null) {
      add('tapAt', data: {'x': position.dx, 'y': position.dy});
    } else {
      add('tap', element: control);
    }
  }

  static bool _tappable(Widget w) =>
      w is ButtonStyleButton ||
      w is IconButton ||
      w is InkResponse ||
      w is GestureDetector ||
      w is ListTile ||
      w is Checkbox ||
      w is Switch ||
      w is Radio ||
      w is Chip ||
      w is ChoiceChip ||
      w is FilterChip ||
      w is ActionChip ||
      w is FloatingActionButton ||
      w is TextField ||
      _tappableByName(w);

  /// The same controls from the separate material_ui package: other classes
  /// with Flutter's names, which `is` does not match.
  static bool _tappableByName(Widget w) {
    final name = _named(w);
    if (name.startsWith('_')) return false;
    return name.endsWith('Button') ||
        name.endsWith('Chip') ||
        const {
          'InkResponse',
          'InkWell',
          'ListTile',
          'Checkbox',
          'Switch',
          'Radio',
          'TextField',
        }.contains(name);
  }

  /// Text typed into a field; obscured text becomes secret number N.
  static Map<String, dynamic> typed(String text, {required bool obscured}) {
    if (!obscured) return {'text': text};
    secrets.add(text);
    return {'secret': secrets.length};
  }
}

/// Writes a `flutter_test` finder for one element, the way a person would:
/// by key, by text, by tooltip, by type and text, inside a keyed ancestor,
/// and only as a last resort by position.
class TestFinder {
  /// `{'finder': source, 'stable': bool}`; stable is false for positional
  /// finders, which break when the screen's content changes.
  static Map<String, dynamic> of(Element target, {bool field = false}) {
    final onstage = _collect(WidgetsBinding.instance.rootElement);
    String? found;
    var stable = true;

    // 1. A key on the widget, or on an ancestor drawn in the same box.
    for (final e in _sameBoxAncestors(target, field: field)) {
      final key = _keyLiteral(e.widget.key);
      if (key != null &&
          onstage.where((o) => o.widget.key == e.widget.key).length == 1) {
        found = 'find.byKey($key)';
        break;
      }
    }

    // 2–4. By what the user reads: text, tooltip, type with text.
    found ??= _byContent(target, onstage, field: field);

    // 5. The same inside the nearest ancestor with a unique key.
    if (found == null) {
      for (Element? a = _parent(target); a != null; a = _parent(a)) {
        final key = _keyLiteral(a.widget.key);
        if (key == null ||
            onstage.where((o) => o.widget.key == a!.widget.key).length != 1) {
          continue;
        }
        final inner = _byContent(target, _collect(a), field: field);
        if (inner != null) {
          found = 'find.descendant(of: find.byKey($key), matching: $inner)';
        }
        break;
      }
    }

    // 6. By type and position.
    if (found == null) {
      final w = field ? _fieldWidget(target) ?? target : target;
      final name = w.widget.runtimeType.toString();
      final same = onstage
          .where((o) => o.widget.runtimeType == w.widget.runtimeType)
          .toList();
      final byType = _frameworkTypes.contains(name)
          ? 'find.byType($name)'
          : 'find.byWidgetPredicate((w) => w.runtimeType.toString() == '
                '${_str(name)})';
      final index = same.indexOf(w);
      found = same.length == 1 || index < 0 ? byType : '$byType.at($index)';
      stable = same.length == 1;
    }
    return {'finder': found, 'stable': stable};
  }

  static String? _byContent(
    Element target,
    List<Element> scope, {
    required bool field,
  }) {
    final fieldElement = field ? _fieldWidget(target) : null;
    if (fieldElement != null) {
      // A text field by the label or hint drawn inside it.
      final type = fieldElement.widget.runtimeType.toString();
      if (!_frameworkTypes.contains(type)) return null;
      for (final label in _texts(fieldElement)) {
        final matches = scope.where(
          (o) =>
              o.widget.runtimeType == fieldElement.widget.runtimeType &&
              _texts(o).contains(label),
        );
        if (matches.length == 1) {
          return 'find.widgetWithText($type, ${_str(label)})';
        }
      }
      return null;
    }

    // The text inside the widget, when it is the only such text on screen.
    final texts = _texts(target).toSet();
    if (texts.length == 1) {
      final text = texts.single;
      final same = scope.where((o) => _textOf(o.widget) == text);
      if (same.length == 1) return 'find.text(${_str(text)})';
    }

    // A tooltip on the widget or around it.
    final tooltip = _tooltip(target);
    if (tooltip != null &&
        scope
                .where(
                  (o) =>
                      o.widget is Tooltip &&
                      (o.widget as Tooltip).message == tooltip,
                )
                .length ==
            1) {
      return 'find.byTooltip(${_str(tooltip)})';
    }

    // A known widget type holding that text.
    if (texts.length == 1 &&
        _frameworkTypes.contains(target.widget.runtimeType.toString())) {
      final same = scope.where(
        (o) =>
            o.widget.runtimeType == target.widget.runtimeType &&
            _texts(o).contains(texts.single),
      );
      if (same.length == 1) {
        return 'find.widgetWithText(${target.widget.runtimeType}, '
            '${_str(texts.single)})';
      }
    }
    return null;
  }

  /// The TextField / TextFormField around an EditableText, if any.
  static Element? _fieldWidget(Element e) {
    Element? found;
    var depth = 0;
    e.visitAncestorElements((a) {
      if (_isField(a.widget) || _isFormField(a.widget)) found = a;
      return found == null && ++depth < 30;
    });
    // TextFormField holds a TextField: prefer the outer one.
    if (found != null && _isField(found!.widget)) {
      Element? outer;
      var up = 0;
      found!.visitAncestorElements((a) {
        if (_isFormField(a.widget)) outer = a;
        return outer == null && ++up < 8;
      });
      found = outer ?? found;
    }
    return found ?? (_isField(e.widget) ? e : null);
  }

  static bool _isField(Widget w) => _named(w) == 'TextField';
  static bool _isFormField(Widget w) => _named(w) == 'TextFormField';

  static String? _tooltip(Element target) {
    if (target.widget is Tooltip) return (target.widget as Tooltip).message;
    String? message;
    void down(Element e) {
      if (message != null) return;
      if (e.widget is Tooltip) {
        message = (e.widget as Tooltip).message;
        return;
      }
      e.debugVisitOnstageChildren(down);
    }

    target.debugVisitOnstageChildren(down);
    if (message != null) return message;
    var depth = 0;
    target.visitAncestorElements((a) {
      if (a.widget is Tooltip) message = (a.widget as Tooltip).message;
      return message == null && ++depth < 4;
    });
    return message;
  }

  /// The element, then its ancestors while they are drawn in the same box
  /// (a tap on any of them lands on the same thing).
  static Iterable<Element> _sameBoxAncestors(
    Element target, {
    required bool field,
  }) sync* {
    yield target;
    final box = _rect(target);
    final fieldElement = field ? _fieldWidget(target) : null;
    var depth = 0;
    for (Element? a = _parent(target); a != null && depth < 12; depth++) {
      final r = _rect(a);
      if (fieldElement == null && (r == null || box == null || r != box)) {
        return;
      }
      yield a;
      if (identical(a, fieldElement)) return;
      a = _parent(a);
    }
  }

  static Rect? _rect(Element e) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  static Element? _parent(Element e) {
    Element? parent;
    e.visitAncestorElements((a) {
      parent = a;
      return false;
    });
    return parent;
  }

  /// What `find.text` matches: Text and EditableText.
  static String? _textOf(Widget w) {
    if (w is Text) return w.data ?? w.textSpan?.toPlainText();
    if (w is EditableText) return w.controller.text;
    return null;
  }

  /// Texts drawn by the element and below it (not typed ones).
  static List<String> _texts(Element root) {
    final out = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Text) {
        final t = _textOf(w);
        if (t != null && t.trim().isNotEmpty) out.add(t);
      }
      if (w is EditableText) return;
      e.debugVisitOnstageChildren(visit);
    }

    visit(root);
    return out;
  }

  /// Onstage elements in the order `flutter_test` finders visit them.
  static List<Element> _collect(Element? root) {
    final out = <Element>[];
    void visit(Element e) {
      out.add(e);
      e.debugVisitOnstageChildren(visit);
    }

    if (root != null) visit(root);
    return out;
  }

  static String? _keyLiteral(Key? key) {
    if (key is ValueKey<String>) return 'const ValueKey(${_str(key.value)})';
    if (key is ValueKey<int>) return 'const ValueKey(${key.value})';
    return null;
  }

  /// A single-quoted Dart string literal.
  static String _str(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }

  /// Types `package:flutter/material.dart` exports, safe to name in a test
  /// without importing the app's own files.
  static const _frameworkTypes = {
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'FilledButton',
    'IconButton',
    'FloatingActionButton',
    'BackButton',
    'CloseButton',
    'TextField',
    'TextFormField',
    'Checkbox',
    'CheckboxListTile',
    'Switch',
    'SwitchListTile',
    'Radio',
    'RadioListTile',
    'Slider',
    'ListTile',
    'Card',
    'InkWell',
    'GestureDetector',
    'Chip',
    'ChoiceChip',
    'FilterChip',
    'ActionChip',
    'InputChip',
    'Tab',
    'NavigationDestination',
    'PopupMenuButton',
    'DropdownButton',
    'MenuItemButton',
    'Text',
    'Icon',
    'SegmentedButton',
    'ExpansionTile',
    'SearchBar',
  };
}

String _named(Widget w) => w.runtimeType.toString().split('<').first;
