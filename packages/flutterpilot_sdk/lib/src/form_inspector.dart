import 'package:flutter/material.dart' show InputDecorator;
import 'package:flutter/widgets.dart';

/// What is wrong with a form field: the validation error it shows, or the
/// one its validator would give for the current value (a form that has not
/// been submitted yet shows none, and its submit button may be disabled
/// for exactly that reason).
class FormInspector {
  /// Fields listed by [problemsOnScreen].
  static const int maxProblems = 6;

  /// The error of the field [element] is (or is part of, or holds): `shown`
  /// is on screen; `pending` is what the validator says about the current
  /// value without it being shown. Null for a field with neither.
  static ({String? shown, String? pending})? of(Element element) {
    FormFieldState<dynamic>? field = _fieldState(element);
    String? decorated;
    // Down the single-child wrappers a field is built from (TextField →
    // … → InputDecorator), never into a container's children: a Column of
    // fields has no error of its own.
    Element? current = element;
    for (var depth = 0; current != null && depth < 40; depth++) {
      field ??= _fieldState(current);
      final w = current.widget;
      if (w is InputDecorator) {
        decorated = _errorOf(w);
        break;
      }
      final children = <Element>[];
      current.debugVisitOnstageChildren(children.add);
      current = children.length == 1 ? children.single : null;
    }
    if (field == null) {
      // The TextField inside a TextFormField: the field is just above.
      var steps = 0;
      element.visitAncestorElements((a) {
        field = _fieldState(a);
        return field == null && ++steps < 6;
      });
    }
    final shown = field?.errorText ?? decorated;
    final pending = shown == null && field != null ? _validate(field!) : null;
    if (shown == null && pending == null) return null;
    return (shown: shown, pending: pending);
  }

  /// The fields on screen that show an error or would fail validation, as
  /// `Label: "message"`, for telling why a submit button is disabled.
  static List<String> problemsOnScreen() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];
    final problems = <String>[];
    void visit(Element e, bool inField) {
      if (problems.length >= maxProblems) return;
      final field = _fieldState(e);
      final w = e.widget;
      if (field != null) {
        final message = field.errorText ?? _validate(field);
        if (message != null) problems.add('${_labelOf(e)}: "$message"');
        inField = true;
      } else if (!inField && w is InputDecorator) {
        // A plain TextField with an errorText the app set itself.
        final message = _errorOf(w);
        if (message != null) problems.add('${_labelOf(e)}: "$message"');
      }
      e.debugVisitOnstageChildren((c) => visit(c, inField));
    }

    visit(root, false);
    return problems;
  }

  static FormFieldState<dynamic>? _fieldState(Element e) =>
      e is StatefulElement && e.state is FormFieldState
      ? e.state as FormFieldState<dynamic>
      : null;

  static String? _errorOf(InputDecorator w) {
    final d = w.decoration;
    if (d.errorText != null) return d.errorText;
    final error = d.error;
    return error is Text ? error.data : null;
  }

  /// What the field's validator says about its current value. Validators
  /// are asked the same way `FormFieldState.isValid` asks: nothing is shown.
  static String? _validate(FormFieldState<dynamic> field) {
    try {
      final dynamic widget = field.widget;
      if (widget.enabled == false) return null;
      final Object? result = widget.validator?.call(field.value);
      return result is String ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// The field's label as the user reads it, else its key or type.
  static String _labelOf(Element field) {
    String? label;
    var budget = 60;
    void visit(Element e) {
      if (label != null || --budget < 0) return;
      final w = e.widget;
      if (w is InputDecorator) {
        final d = w.decoration;
        final text = d.labelText ?? d.hintText;
        final widget = d.label;
        label = text ?? (widget is Text ? widget.data : null);
        if (label != null) return;
      }
      e.debugVisitOnstageChildren(visit);
    }

    visit(field);
    final key = field.widget.key;
    return label ??
        (key is ValueKey ? '${key.value}' : '${field.widget.runtimeType}');
  }
}
