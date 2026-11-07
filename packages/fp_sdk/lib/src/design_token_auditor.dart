import 'package:flutter/material.dart';

import 'source_locator.dart';

/// Colors and corner radii the app's own code hard-codes instead of taking
/// from its theme.
///
/// Only widgets created in the app's code are checked: the framework derives
/// its own colors (an input decorator's hint, a navigation bar's labels), and
/// an agent can't change those. Needs creation locations (debug builds).
class DesignTokenAuditor {
  DesignTokenAuditor._();

  static Map<String, dynamic> audit() {
    final root = WidgetsBinding.instance.rootElement;
    if (!SourceLocator.available || root == null) {
      return {
        'unavailable':
            'Needs a debug build: only it records which widgets the app '
            'creates.',
      };
    }
    final colors = <Map<String, dynamic>>[];
    final radii = <Map<String, dynamic>>[];
    var checked = 0;

    void color(Element element, String what, Color? c) {
      if (c == null) return;
      checked++;
      final scheme = Theme.of(element).colorScheme;
      if (_tokenFor(c, scheme) != null) return;
      colors.add({
        'widget': what,
        'color': _hex(c),
        'location': ?SourceLocator.locationOf(element),
        'closestToken': _closestToken(c, scheme),
      });
    }

    void radius(Element element, String what, BorderRadiusGeometry? r) {
      if (r is! BorderRadius) return;
      final value = r.topLeft.x;
      checked++;
      if (value <= 0 || value % 4 == 0 || value >= 999) return;
      radii.add({
        'widget': what,
        'radius': value,
        'location': ?SourceLocator.locationOf(element),
        'nearest': (value / 4).round() * 4,
      });
    }

    void decoration(Element element, String what, Decoration? d) {
      if (d is! BoxDecoration) return;
      color(element, what, d.color);
      radius(element, what, d.borderRadius);
    }

    void visit(Element element) {
      final widget = element.widget;
      if (debugIsWidgetLocalCreation(widget)) {
        switch (widget) {
          case Text():
            color(
              element,
              'Text("${_short(widget.data ?? '')}")',
              widget.style?.color,
            );
          case Icon():
            color(element, 'Icon', widget.color);
          case Container():
            color(element, 'Container', widget.color);
            decoration(element, 'Container', widget.decoration);
          case DecoratedBox():
            decoration(element, 'DecoratedBox', widget.decoration);
          case ClipRRect():
            radius(element, 'ClipRRect', widget.borderRadius);
          case Card():
            color(element, 'Card', widget.color);
          default:
        }
      }
      element.visitChildren(visit);
    }

    visit(root);
    return {
      'checked': checked,
      'unthemedColors': colors.take(15).toList(),
      'unthemedColorCount': colors.length,
      'offGridRadii': radii.take(15).toList(),
      'offGridRadiusCount': radii.length,
    };
  }

  /// The scheme's colors by name. A token used with an opacity
  /// (`onSurface.withValues(alpha: .6)`) is still that token, so alpha is
  /// ignored when matching.
  static Map<String, Color> _tokens(ColorScheme s) => {
    'primary': s.primary,
    'onPrimary': s.onPrimary,
    'primaryContainer': s.primaryContainer,
    'onPrimaryContainer': s.onPrimaryContainer,
    'secondary': s.secondary,
    'onSecondary': s.onSecondary,
    'secondaryContainer': s.secondaryContainer,
    'onSecondaryContainer': s.onSecondaryContainer,
    'tertiary': s.tertiary,
    'onTertiary': s.onTertiary,
    'tertiaryContainer': s.tertiaryContainer,
    'onTertiaryContainer': s.onTertiaryContainer,
    'error': s.error,
    'onError': s.onError,
    'errorContainer': s.errorContainer,
    'onErrorContainer': s.onErrorContainer,
    'surface': s.surface,
    'onSurface': s.onSurface,
    'onSurfaceVariant': s.onSurfaceVariant,
    'surfaceContainerLowest': s.surfaceContainerLowest,
    'surfaceContainerLow': s.surfaceContainerLow,
    'surfaceContainer': s.surfaceContainer,
    'surfaceContainerHigh': s.surfaceContainerHigh,
    'surfaceContainerHighest': s.surfaceContainerHighest,
    'inverseSurface': s.inverseSurface,
    'onInverseSurface': s.onInverseSurface,
    'inversePrimary': s.inversePrimary,
    'outline': s.outline,
    'outlineVariant': s.outlineVariant,
    'shadow': s.shadow,
    'scrim': s.scrim,
  };

  static int _rgb(Color c) => c.toARGB32() & 0xFFFFFF;

  static String? _tokenFor(Color c, ColorScheme scheme) {
    // Fully transparent, black and white aren't brand colors.
    if (c.a == 0 || _rgb(c) == 0 || _rgb(c) == 0xFFFFFF) return 'plain';
    for (final MapEntry(:key, :value) in _tokens(scheme).entries) {
      if (_rgb(value) == _rgb(c)) return key;
    }
    return null;
  }

  static String _closestToken(Color c, ColorScheme scheme) {
    var best = 'primary';
    var bestDistance = double.infinity;
    for (final MapEntry(:key, :value) in _tokens(scheme).entries) {
      final dr = (c.r - value.r) * 255;
      final dg = (c.g - value.g) * 255;
      final db = (c.b - value.b) * 255;
      final d = dr * dr + dg * dg + db * db;
      if (d < bestDistance) {
        bestDistance = d;
        best = key;
      }
    }
    return 'colorScheme.$best';
  }

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static String _short(String s) =>
      s.length > 20 ? '${s.substring(0, 20)}…' : s;
}
