import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// "What does this look like, in numbers?": the text styles, paddings,
/// fills, borders and corner radii a widget is drawn with, read from its
/// render objects — what a design spec states and a screenshot only hints
/// at (16 or 12 of padding, weight 600 or 700, #0F172A or #1E293B).
///
/// Only what the framework's own render objects draw: a `CustomPainter`
/// keeps its colors to itself.
class StyleExplorer {
  /// Entries listed per kind; the rest are counted.
  static const int maxPerKind = 8;

  /// The style of [element]'s widget and what it contains, plus the padding
  /// and fill around it.
  static Map<String, dynamic> describe(Element element) {
    final root = _renderObjectOf(element);
    if (root == null) {
      return {
        'style': {
          'note': '${element.widget.runtimeType} draws nothing (not laid out).',
        },
      };
    }
    final text = <Map<String, Object?>>[];
    final icons = <Map<String, Object?>>[];
    final padding = <Map<String, Object?>>[];
    final boxes = <Map<String, Object?>>[];
    var budget = 600; // a screen has thousands: describe a widget, not a page
    var custom = 0;

    void visit(RenderObject ro) {
      if (--budget < 0) return;
      if (ro is RenderParagraph) {
        final entry = _text(ro.text, ro.textScaler);
        if (entry != null) {
          (entry.containsKey('icon') ? icons : text).add(entry..remove('icon'));
        }
      } else if (ro is RenderEditable) {
        final span = ro.text;
        final entry = span == null ? null : _text(span, ro.textScaler);
        if (entry != null) text.add(entry..remove('icon'));
      } else if (ro is RenderPadding) {
        final entry = _padding(ro);
        if (entry != null) padding.add(entry);
      } else if (ro is RenderCustomPaint) {
        // The app's own painters only: the framework paints checkboxes,
        // outlines and spinners with CustomPaint too.
        final creator = ro.debugCreator;
        if (creator is DebugCreator &&
            debugIsWidgetLocalCreation(creator.element.widget)) {
          custom++;
        }
      } else {
        final box = _box(ro);
        if (box != null) boxes.add(box);
      }
      ro.visitChildren(visit);
    }

    visit(root);

    // What surrounds it: the nearest padding and the nearest fill behind.
    Map<String, Object?>? around;
    Map<String, Object?>? behind;
    var steps = 0;
    for (RenderObject? ro = root.parent; ro != null; ro = ro.parent) {
      if (++steps > 40) break;
      if (around == null && ro is RenderPadding) around = _padding(ro);
      if (behind == null) {
        final box = _box(ro);
        if (box != null && box['color'] != null) behind = box;
      }
      if (around != null && behind != null) break;
    }

    List<Object?> capped(List<Map<String, Object?>> all) => [
      ...all.take(maxPerKind),
      if (all.length > maxPerKind) '+${all.length - maxPerKind} more',
    ];

    return {
      'style': {
        if (text.isNotEmpty) 'text': capped(text),
        if (icons.isNotEmpty) 'icons': capped(icons),
        if (padding.isNotEmpty) 'padding': capped(padding),
        if (boxes.isNotEmpty) 'boxes': capped(boxes),
        'paddingAround': ?around,
        'behind': ?behind,
        if (custom > 0)
          'note':
              '$custom CustomPaint${custom == 1 ? '' : 's'} inside: what a '
              'painter draws (its colors, strokes) is not listed.',
        if (text.isEmpty &&
            icons.isEmpty &&
            padding.isEmpty &&
            boxes.isEmpty &&
            custom == 0)
          'note': 'No text, padding, fill or border inside this widget.',
      },
    };
  }

  /// The padding [ro] applies, as the code wrote it: a `Container` with a
  /// border folds the border's width into its padding (16 + a 1 px border
  /// lays out as 17), which is taken out again and named.
  static Map<String, Object?>? _padding(RenderPadding ro) {
    var resolved = ro.padding.resolve(ro.textDirection);
    EdgeInsets? border;
    final parent = ro.parent;
    if (parent is RenderDecoratedBox) {
      final inset = parent.decoration.padding.resolve(ro.textDirection);
      final rest = resolved - inset;
      if (inset != EdgeInsets.zero && rest.isNonNegative) {
        border = inset;
        resolved = rest;
      }
    }
    if (resolved == EdgeInsets.zero) return null;
    return {
      'ltrb': _insets(resolved),
      if (border != null) 'plusBorder': _insets(border),
      'box': _size(ro),
    };
  }

  static RenderObject? _renderObjectOf(Element element) {
    final ro = element.renderObject;
    if (ro == null || !ro.attached) return null;
    return ro;
  }

  /// `#RRGGBB`, or `#RRGGBBAA` when translucent.
  static String hex(Color color) {
    final argb = color.toARGB32();
    final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final alpha = argb >> 24 & 0xFF;
    final a = alpha == 0xFF ? '' : alpha.toRadixString(16).padLeft(2, '0');
    return '#$rgb$a'.toUpperCase();
  }

  static num _n(double v) => v == v.roundToDouble() ? v.round() : _round(v);

  static double _round(double v) => (v * 100).round() / 100;

  static List<num> _insets(EdgeInsets e) => [
    _n(e.left),
    _n(e.top),
    _n(e.right),
    _n(e.bottom),
  ];

  static String? _size(RenderObject ro) => ro is RenderBox && ro.hasSize
      ? '${_n(ro.size.width)}x${_n(ro.size.height)}'
      : null;

  /// A text run's style as drawn; `icon: true` for an icon font glyph.
  static Map<String, Object?>? _text(InlineSpan span, TextScaler scaler) {
    final style = span.style;
    final plain = span.toPlainText(includeSemanticsLabels: false).trim();
    if (style == null || plain.isEmpty) return null;
    final family = style.fontFamily;
    final isIcon =
        family != null &&
        (family.contains('Icons') || family.contains('Symbols')) &&
        plain.runes.length == 1;
    final size = style.fontSize;
    final scaled = size == null ? null : scaler.scale(size);
    return {
      if (isIcon) 'icon': true,
      if (!isIcon)
        'text': plain.length > 40 ? '${plain.substring(0, 40)}…' : plain,
      if (size != null) 'size': _n(size),
      if (scaled != null && (scaled - size!).abs() > 0.01) 'scaled': _n(scaled),
      if (!isIcon) 'weight': (style.fontWeight ?? FontWeight.normal).value,
      if (style.color != null) 'color': hex(style.color!),
      if (!isIcon && family != null) 'font': family,
      if (!isIcon && style.height != null) 'height': _round(style.height!),
      if ((style.letterSpacing ?? 0) != 0)
        'letterSpacing': _round(style.letterSpacing!),
      if (style.fontStyle == FontStyle.italic) 'italic': true,
      if (style.decoration != null && style.decoration != TextDecoration.none)
        'decoration': style.decoration.toString().replaceAll(
          'TextDecoration.',
          '',
        ),
      if (span is TextSpan && _mixed(span)) 'mixed': true,
    };
  }

  /// Whether child spans restyle parts of the text (`Text.rich`).
  static bool _mixed(TextSpan span) =>
      span.children?.any((c) => c.style != null) ?? false;

  /// A fill, border, radius or shadow drawn by [ro]; null when it draws
  /// none.
  static Map<String, Object?>? _box(RenderObject ro) {
    final out = <String, Object?>{};
    if (ro is RenderDecoratedBox) {
      final d = ro.decoration;
      if (d is BoxDecoration) {
        if (d.color != null) out['color'] = hex(d.color!);
        final gradient = d.gradient;
        if (gradient != null) {
          out['gradient'] = [for (final c in gradient.colors) hex(c)];
        }
        final radius = _radius(d.borderRadius, ro);
        if (radius != null) out['radius'] = radius;
        if (d.shape == BoxShape.circle) out['shape'] = 'circle';
        final border = d.border;
        if (border is Border) {
          final side = _side(border.top);
          if (side != null) out['border'] = border.isUniform ? side : 'mixed';
        }
        final shadows = d.boxShadow;
        if (shadows != null && shadows.isNotEmpty) {
          out['shadow'] =
              '${hex(shadows.first.color)} blur '
              '${_n(shadows.first.blurRadius)}';
        }
      } else if (d is ShapeDecoration) {
        if (d.color != null) out['color'] = hex(d.color!);
        _shape(d.shape, ro, out);
      }
    } else if (ro is RenderPhysicalModel) {
      if (ro.color.a > 0) out['color'] = hex(ro.color);
      if (ro.elevation > 0) out['elevation'] = _n(ro.elevation);
      final radius = _radius(ro.borderRadius, ro);
      if (radius != null) out['radius'] = radius;
      if (ro.shape == BoxShape.circle) out['shape'] = 'circle';
    } else if (ro is RenderPhysicalShape) {
      if (ro.color.a > 0) out['color'] = hex(ro.color);
      if (ro.elevation > 0) out['elevation'] = _n(ro.elevation);
      final clipper = ro.clipper;
      if (clipper is ShapeBorderClipper) _shape(clipper.shape, ro, out);
    } else if (ro is RenderClipRRect) {
      final radius = _radius(ro.borderRadius, ro);
      if (radius != null) out['radius'] = radius;
    } else if (ro is RenderOpacity) {
      if (ro.opacity < 1) out['opacity'] = _round(ro.opacity);
    } else if (ro.runtimeType.toString() == '_RenderColoredBox') {
      // ColoredBox's render object is private; its color is public on it.
      try {
        final color = (ro as dynamic).color;
        if (color is Color && color.a > 0) out['color'] = hex(color);
      } catch (_) {}
    }
    if (out.isEmpty) return null;
    final size = _size(ro);
    if (size != null) out['box'] = size;
    return out;
  }

  static void _shape(
    ShapeBorder shape,
    RenderObject ro,
    Map<String, Object?> out,
  ) {
    if (shape is RoundedRectangleBorder) {
      final radius = _radius(shape.borderRadius, ro);
      if (radius != null) out['radius'] = radius;
    } else if (shape is StadiumBorder) {
      out['shape'] = 'stadium';
    } else if (shape is CircleBorder) {
      out['shape'] = 'circle';
    } else if (shape is ContinuousRectangleBorder ||
        shape is BeveledRectangleBorder) {
      out['shape'] = shape.runtimeType.toString();
    }
    if (shape is OutlinedBorder) {
      final side = _side(shape.side);
      if (side != null) out['border'] = side;
    }
  }

  /// One number when the four corners agree, else `[tl, tr, br, bl]`.
  static Object? _radius(BorderRadiusGeometry? geometry, RenderObject ro) {
    if (geometry == null) return null;
    final r = geometry.resolve(TextDirection.ltr);
    if (r == BorderRadius.zero) return null;
    final corners = [
      r.topLeft.x,
      r.topRight.x,
      r.bottomRight.x,
      r.bottomLeft.x,
    ];
    return corners.every((c) => c == corners.first)
        ? _n(corners.first)
        : corners.map(_n).toList();
  }

  /// `#RRGGBB 1` (color and width), or null for no visible side.
  static String? _side(BorderSide side) =>
      side.style == BorderStyle.none || side.width == 0
      ? null
      : '${hex(side.color)} ${_n(side.width)}';
}
