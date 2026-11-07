import 'package:flutter/material.dart';
import 'source_locator.dart';

/// Audits design system token compliance on active Flutter screens.
///
/// Detects hardcoded raw hex colors, unthemed text/containers, and
/// off-grid border radii (non-4/8dp multiples).
class DesignTokenAuditor {
  DesignTokenAuditor._();

  /// Audits the widget tree starting from the root element.
  static Map<String, dynamic> audit() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return {
        'tokenComplianceScore': 100,
        'violationsCount': 0,
        'unthemedColors': <Map<String, dynamic>>[],
        'offGridBorderRadii': <Map<String, dynamic>>[],
        'prescriptions': <String>[],
      };
    }

    final unthemedColors = <Map<String, dynamic>>[];
    final offGridRadii = <Map<String, dynamic>>[];
    var totalStyledElements = 0;

    void visit(Element element) {
      final widget = element.widget;
      final type = widget.runtimeType.toString();

      // Skip internal framework widgets
      if (type.startsWith('_')) {
        element.visitChildren(visit);
        return;
      }

      // 1. Audit Text Styles for hardcoded colors
      if (widget is Text) {
        final color = widget.style?.color;
        if (color != null) {
          totalStyledElements++;
          final hex = _toHex(color);
          final theme = _findTheme(element);
          if (theme != null && !_isThemeColor(color, theme.colorScheme)) {
            final loc = SourceLocator.locationOf(element);
            unthemedColors.add({
              'widget': 'Text("${_truncate(widget.data ?? '', 20)}")',
              'color': hex,
              'location': loc,
              'suggestedToken': _findClosestToken(color, theme.colorScheme),
            });
          }
        }
      }

      // 2. Audit Container / DecoratedBox for colors and border radius
      if (widget is DecoratedBox) {
        final decoration = widget.decoration;
        if (decoration is BoxDecoration) {
          if (decoration.color != null) {
            totalStyledElements++;
            final color = decoration.color!;
            final hex = _toHex(color);
            final theme = _findTheme(element);
            if (theme != null && !_isThemeColor(color, theme.colorScheme)) {
              final loc = SourceLocator.locationOf(element);
              unthemedColors.add({
                'widget': 'DecoratedBox',
                'color': hex,
                'location': loc,
                'suggestedToken': _findClosestToken(color, theme.colorScheme),
              });
            }
          }

          if (decoration.borderRadius != null && decoration.borderRadius is BorderRadius) {
            final br = decoration.borderRadius as BorderRadius;
            final r = br.topLeft.x;
            if (r > 0 && r % 4.0 != 0 && r < 999) {
              totalStyledElements++;
              final loc = SourceLocator.locationOf(element);
              offGridRadii.add({
                'widget': 'BoxDecoration(borderRadius)',
                'radius': r,
                'location': loc,
                'suggestedRadius': (r / 4.0).round() * 4.0,
              });
            }
          }
        }
      }

      // 3. Audit ClipRRect
      if (widget is ClipRRect && widget.borderRadius is BorderRadius) {
        final br = widget.borderRadius as BorderRadius;
        final r = br.topLeft.x;
        if (r > 0 && r % 4.0 != 0 && r < 999) {
          totalStyledElements++;
          final loc = SourceLocator.locationOf(element);
          offGridRadii.add({
            'widget': 'ClipRRect',
            'radius': r,
            'location': loc,
            'suggestedRadius': (r / 4.0).round() * 4.0,
          });
        }
      }

      element.visitChildren(visit);
    }

    visit(root);

    final violations = unthemedColors.length + offGridRadii.length;
    final score = totalStyledElements == 0
        ? 100
        : (((totalStyledElements - violations) / totalStyledElements) * 100).clamp(0, 100).round();

    final prescriptions = <String>[];
    if (unthemedColors.isNotEmpty) {
      prescriptions.add(
        'Found ${unthemedColors.length} raw unthemed color(s). Migrate to Theme.of(context).colorScheme tokens.',
      );
    }
    if (offGridRadii.isNotEmpty) {
      prescriptions.add(
        'Found ${offGridRadii.length} off-grid border radius value(s). Snap radii to multiples of 4dp (e.g. 8dp, 12dp, 16dp).',
      );
    }

    return {
      'tokenComplianceScore': score,
      'violationsCount': violations,
      'unthemedColorCount': unthemedColors.length,
      'offGridBorderRadiiCount': offGridRadii.length,
      'unthemedColors': unthemedColors.take(15).toList(),
      'offGridBorderRadii': offGridRadii.take(15).toList(),
      'prescriptions': prescriptions,
    };
  }

  static ThemeData? _findTheme(Element element) {
    try {
      return Theme.of(element);
    } catch (_) {
      return null;
    }
  }

  static bool _isThemeColor(Color color, ColorScheme scheme) {
    if (color == Colors.transparent ||
        color == Colors.black ||
        color == Colors.white ||
        color == Colors.black87 ||
        color == Colors.white70) {
      return true;
    }

    final csColors = <Color>[
      scheme.primary,
      scheme.onPrimary,
      scheme.primaryContainer,
      scheme.onPrimaryContainer,
      scheme.secondary,
      scheme.onSecondary,
      scheme.secondaryContainer,
      scheme.onSecondaryContainer,
      scheme.tertiary,
      scheme.onTertiary,
      scheme.surface,
      scheme.onSurface,
      scheme.error,
      scheme.onError,
      scheme.outline,
      scheme.outlineVariant,
    ];

    return csColors.any((c) => c.toARGB32() == color.toARGB32());
  }

  static String _findClosestToken(Color color, ColorScheme scheme) {
    final candidates = <String, Color>{
      'colorScheme.primary': scheme.primary,
      'colorScheme.secondary': scheme.secondary,
      'colorScheme.surface': scheme.surface,
      'colorScheme.error': scheme.error,
      'colorScheme.outline': scheme.outline,
      'colorScheme.onSurface': scheme.onSurface,
    };

    String bestToken = 'colorScheme.primary';
    double minDiff = double.infinity;

    for (final entry in candidates.entries) {
      final diff = _colorDistance(color, entry.value);
      if (diff < minDiff) {
        minDiff = diff;
        bestToken = entry.key;
      }
    }

    return bestToken;
  }

  static double _colorDistance(Color a, Color b) {
    final argbA = a.toARGB32();
    final argbB = b.toARGB32();
    final dr = ((argbA >> 16) & 0xFF) - ((argbB >> 16) & 0xFF);
    final dg = ((argbA >> 8) & 0xFF) - ((argbB >> 8) & 0xFF);
    final db = (argbA & 0xFF) - (argbB & 0xFF);
    return (dr * dr + dg * dg + db * db).toDouble();
  }

  static String _toHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  static String _truncate(String s, int max) {
    return s.length > max ? '${s.substring(0, max)}...' : s;
  }
}
