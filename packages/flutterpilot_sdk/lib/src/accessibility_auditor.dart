import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'ai_overlay_manager.dart';
import 'screen_capture.dart';
import 'source_locator.dart';

/// Accessibility checks beyond tap-target size (ROADMAP §5.7), from what a
/// screen reader gets (the semantics tree) and what the user sees (pixels):
/// controls with no label, text below WCAG contrast, and a reading order
/// that jumps back up the screen.
class AccessibilityAuditor {
  /// WCAG 2.x AA: 4.5:1 for text, 3:1 for large text.
  static const double minContrast = 4.5;
  static const double minContrastLarge = 3.0;

  /// flutter_test's large-text rule: 18 logical px, or 14 bold.
  static bool isLarge(double fontSize, bool bold) =>
      fontSize >= 18 || (bold && fontSize >= 14);

  static Future<Map<String, dynamic>> audit() async {
    final root = await _semanticsRoot();
    final nodes = root == null ? const <_Node>[] : _inTraversalOrder(root);
    return {
      'unlabeled': _unlabeled(nodes),
      'lowContrast': await _lowContrast(),
      'readingOrder': [
        for (final n in nodes.where((n) => n.actionable))
          '${n.name} (${n.rect.left.round()}, ${n.rect.top.round()})',
      ],
      'readingOrderJumps': readingOrderJumps([
        for (final n in nodes.where((n) => n.actionable)) (n.name, n.rect),
      ]),
      if (root == null)
        'semanticsNote':
            'The semantics tree was not built, so labels and reading order '
            'were not checked.',
    };
  }

  static SemanticsHandle? _handle;

  /// Tests must dispose every semantics handle they leave open.
  @visibleForTesting
  static void debugReleaseSemantics() {
    _handle?.dispose();
    _handle = null;
  }

  static Future<SemanticsNode?> _semanticsRoot() async {
    // Flutter builds semantics only while something asks for them (no
    // screen reader on desktop): keep them on once audited.
    if (_handle == null) {
      _handle = SemanticsBinding.instance.ensureSemantics();
      WidgetsBinding.instance.scheduleFrame();
      // A frame may never come (tests, a paused app): don't wait forever.
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }
    for (final view in RendererBinding.instance.renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) return root;
    }
    return null;
  }

  /// Nodes in the order a screen reader visits them, with global logical
  /// rects.
  static List<_Node> _inTraversalOrder(SemanticsNode root) {
    final out = <_Node>[];
    void visit(SemanticsNode node) {
      // A node merged into its parent (an extended FAB's label, a
      // MergeSemantics group) is read as part of it, not on its own.
      if (node.isMergedIntoParent) return;
      final data = node.getSemanticsData();
      if (data.flagsCollection.isHidden) return;
      if (node != root && !node.isInvisible) {
        out.add(_Node(node.id, data, _globalRect(node)));
      }
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        visit(child);
      }
    }

    visit(root);
    return out;
  }

  /// Semantics rects end up in physical pixels (the device pixel ratio is
  /// in the transforms, not always on the root): apply them all, then
  /// divide.
  static Rect _globalRect(SemanticsNode node) {
    var rect = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final t = n.transform;
      if (t != null) rect = MatrixUtils.transformRect(t, rect);
    }
    final dpr =
        WidgetsBinding
            .instance
            .platformDispatcher
            .implicitView
            ?.devicePixelRatio ??
        1.0;
    return Rect.fromLTRB(
      rect.left / dpr,
      rect.top / dpr,
      rect.right / dpr,
      rect.bottom / dpr,
    );
  }

  /// Unlabeled tappable nodes, grouped by the code that makes them (a
  /// list row repeats one widget).
  static List<String> _unlabeled(List<_Node> nodes) {
    final groups = <String, List<_Node>>{};
    final hints = <String, String>{};
    for (final n in nodes.where((n) => n.actionable && !n.labeled)) {
      final source = _sourceOfNode(n) ?? '';
      final key = '${n.role}|$source';
      (groups[key] ??= []).add(n);
      // Over a labeled control with the same box: a wrapper (often a
      // GestureDetector for right-click or long-press) adds a silent stop.
      final twin = nodes.where(
        (m) => m != n && m.labeled && _sameBox(m.rect, n.rect),
      );
      if (twin.isNotEmpty && !hints.containsKey(key)) {
        hints[key] =
            'It covers ${twin.first.name} (same box): an extra silent stop '
            'for screen readers. If the wrapper only adds a gesture, set '
            'excludeFromSemantics: true on it; otherwise give it a label.';
      }
    }
    return [
      for (final MapEntry(:key, value: list) in groups.entries)
        () {
          final n = list.first;
          final at = list
              .take(3)
              .map((m) => '(${m.rect.left.round()}, ${m.rect.top.round()})')
              .join(', ');
          final source = key.substring(key.indexOf('|') + 1);
          return '${n.role}${list.length > 1 ? ' ×${list.length}' : ''} at '
              '$at${list.length > 3 ? ', …' : ''} '
              '${n.rect.width.round()}×${n.rect.height.round()} has no label: '
              'a screen reader only says "${n.role.toLowerCase()}". '
              '${source.isEmpty ? '' : 'Code: $source. '}'
              '${hints[key] ?? 'Add a tooltip (IconButton), semanticsLabel or '
                      'Semantics(label:).'}';
        }(),
    ];
  }

  static bool _sameBox(Rect a, Rect b) =>
      (a.left - b.left).abs() <= 1 &&
      (a.top - b.top).abs() <= 1 &&
      (a.right - b.right).abs() <= 1 &&
      (a.bottom - b.bottom).abs() <= 1;

  /// The app code behind a semantics node's tap: going up from what a tap
  /// at its center hits, the first render object that adds a tap or
  /// long-press action to this node (a GestureDetector adds its action to
  /// the enclosing node, often a list's per-row one), else the one that
  /// made the node; then the nearest app widget at or above its creator —
  /// `GestureDetector lib/ui/tile.dart:22:12`.
  static String? _sourceOfNode(_Node node) {
    if (!SourceLocator.available) return null;
    final binding = WidgetsBinding.instance;
    final viewId = binding.platformDispatcher.implicitView?.viewId;
    if (viewId == null) return null;
    final result = HitTestResult();
    binding.hitTestInView(result, node.rect.center, viewId);
    RenderObject? leaf;
    for (final entry in result.path) {
      if (entry.target is RenderObject) {
        leaf = entry.target as RenderObject;
        break;
      }
    }
    RenderObject? contributor;
    for (var ro = leaf; ro != null; ro = ro.parent) {
      final own = ro.debugSemantics;
      if (own != null && own.id != node.id) {
        // Belongs to a node below this one (e.g. the labeled tile).
        contributor = null;
        continue;
      }
      if (contributor == null && _addsTap(ro)) contributor = ro;
      if (own?.id != node.id) continue;
      final creator = (contributor ?? ro).debugCreator;
      if (creator is! DebugCreator) return null;
      final source = SourceLocator.describe(creator.element)['source'] as Map?;
      return source == null ? null : '${source['type']} ${source['loc']}';
    }
    return null;
  }

  static bool _addsTap(RenderObject ro) {
    final config = SemanticsConfiguration();
    try {
      // ignore: invalid_use_of_protected_member
      ro.describeSemanticsConfiguration(config);
    } catch (_) {
      return false;
    }
    return config.onTap != null || config.onLongPress != null;
  }

  /// Each on-screen text's contrast against what is behind it, from the
  /// rendered pixels: the most common color in its box is the background,
  /// the one contrasting most with it the text (antialiased edges contrast
  /// less than the glyph core). Handles opacity, images and themes alike.
  static Future<List<String>> _lowContrast() async {
    final shot = await _screenPixels();
    if (shot == null) return const [];
    // One line per code and colors: a list repeats the same Text per row.
    final issues = <String, (String, int)>{};
    var checked = 0;
    void visit(Element element) {
      if (element.widget is AiOverlayMarker) return;
      final ro = element.renderObject;
      if (element is RenderObjectElement &&
          ro is RenderParagraph &&
          ro.attached &&
          ro.hasSize &&
          checked < 200) {
        final text = ro.text.toPlainText().trim();
        if (text.isNotEmpty) {
          checked++;
          final rect = ro.localToGlobal(Offset.zero) & ro.size;
          final color = ro.text.style?.color;
          final pair = dominantPair(
            shot,
            rect,
            textColor: color != null && color.a == 1 ? color.toARGB32() : null,
          );
          if (pair != null) {
            final style = ro.text.style;
            final size = ro.textScaler.scale(style?.fontSize ?? 14);
            final bold = (style?.fontWeight?.value ?? 400) >= 700;
            final large = isLarge(size, bold);
            final ratio = contrastRatio(pair.$1, pair.$2);
            if (ratio < (large ? minContrastLarge : minContrast)) {
              final shown = text.length > 40
                  ? '${text.substring(0, 40)}…'
                  : text;
              final problem =
                  'contrast ${ratio.toStringAsFixed(2)}:1 '
                  '(${_hex(pair.$2)} on ${_hex(pair.$1)}), needs '
                  '${large ? '3' : '4.5'}:1 for ${large ? 'large' : 'body'} '
                  'text (${size.toStringAsFixed(0)} px'
                  '${bold ? ' bold' : ''}). '
                  '${_sourceOf(element) ?? ''}';
              final seen = issues[problem];
              issues[problem] = (seen?.$1 ?? '"$shown"', (seen?.$2 ?? 0) + 1);
            }
          }
        }
      }
      element.debugVisitOnstageChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.debugVisitOnstageChildren(visit);
    return [
      for (final MapEntry(key: problem, value: (text, count)) in issues.entries)
        '$text${count > 1 ? ' and ${count - 1} more like it' : ''} '
                '$problem'
            .trim(),
    ];
  }

  static String? _sourceOf(Element element) {
    if (!SourceLocator.available) return null;
    final source = SourceLocator.describe(element)['source'] as Map?;
    return source == null ? null : 'Code: ${source['type']} ${source['loc']}.';
  }

  static String _hex(int argb) =>
      '#${(argb & 0xffffff).toRadixString(16).padLeft(6, '0')}';

  /// The whole screen as RGBA at 1 pixel per logical pixel.
  static Future<ScreenPixels?> _screenPixels() async {
    AiOverlayManager.clearNow();
    // Colors mid-animation are neither theme's (a theme switch fades for
    // 200 ms): let animations finish, but not a spinner that never does.
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (SchedulerBinding.instance.transientCallbackCount > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    try {
      final image = await ScreenCapture.image();
      if (image == null) return null;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return null;
      return ScreenPixels(
        data.buffer.asUint8List(),
        image.width,
        image.height,
        Offset.zero,
      );
    } catch (_) {
      return null;
    }
  }

  /// Background and foreground inside [rect], as 0xAARRGGBB; null if the
  /// box is one color or off screen. With [textColor] (the style's, when
  /// opaque) the foreground is that color and the background the most
  /// common color unlike it: bold or large text can cover most of its box.
  /// Without it, the most common color is the background and the one
  /// contrasting most with it the text.
  static (int, int)? dominantPair(
    ScreenPixels shot,
    Rect rect, {
    int? textColor,
  }) {
    final r = (rect.shift(-shot.origin)).intersect(
      Rect.fromLTWH(0, 0, shot.width.toDouble(), shot.height.toDouble()),
    );
    if (r.isEmpty || r.width < 2 || r.height < 2) return null;
    // At most ~4000 samples per text.
    final step = math.max(1, math.sqrt(r.width * r.height / 4000).floor());
    final counts = <int, int>{};
    for (var y = r.top.floor(); y < r.bottom.floor(); y += step) {
      for (var x = r.left.floor(); x < r.right.floor(); x += step) {
        final i = (y * shot.width + x) * 4;
        if (shot.rgba[i + 3] < 200) continue; // nothing opaque drawn here
        final c =
            0xff000000 |
            (shot.rgba[i] << 16) |
            (shot.rgba[i + 1] << 8) |
            shot.rgba[i + 2];
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    if (textColor != null) {
      final behind = counts.entries.where(
        (e) => contrastRatio(e.key, textColor) > 1.1,
      );
      if (behind.isEmpty) return null;
      final background = behind
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      return (background, 0xff000000 | textColor);
    }
    if (counts.length < 2) return null;
    final background = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    var foreground = background;
    var best = 1.0;
    for (final c in counts.keys) {
      final ratio = contrastRatio(background, c);
      if (ratio > best) {
        best = ratio;
        foreground = c;
      }
    }
    return foreground == background ? null : (background, foreground);
  }

  /// WCAG contrast ratio of two 0xAARRGGBB colors, 1–21.
  static double contrastRatio(int a, int b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static double _luminance(int argb) {
    double channel(int v) {
      final c = v / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((argb >> 16) & 0xff) +
        0.7152 * channel((argb >> 8) & 0xff) +
        0.0722 * channel(argb & 0xff);
  }

  /// Places where the reading order moves clearly back up the screen: the
  /// next control ends above where the previous one starts.
  static List<String> readingOrderJumps(List<(String, Rect)> order) => [
    for (var i = 1; i < order.length; i++)
      if (order[i].$2.bottom < order[i - 1].$2.top - 4)
        'After ${order[i - 1].$1} (y ${order[i - 1].$2.top.round()}) a '
            'screen reader goes back up to ${order[i].$1} '
            '(y ${order[i].$2.top.round()}).',
  ];
}

/// A screenshot's RGBA bytes and where its top-left is on screen.
class ScreenPixels {
  ScreenPixels(this.rgba, this.width, this.height, this.origin);
  final Uint8List rgba;
  final int width;
  final int height;
  final Offset origin;
}

class _Node {
  _Node(this.id, this.data, this.rect);
  final int id;
  final SemanticsData data;
  final Rect rect;

  SemanticsFlags get flags => data.flagsCollection;

  bool get actionable =>
      data.hasAction(SemanticsAction.tap) ||
      data.hasAction(SemanticsAction.longPress) ||
      flags.isTextField;

  bool get labeled =>
      '${data.label}${data.value}${data.hint}${data.tooltip}'.trim().isNotEmpty;

  String get role => flags.isTextField
      ? 'Text field'
      : flags.isButton
      ? 'Button'
      : flags.isLink
      ? 'Link'
      : 'Tappable';

  String get name {
    final label = data.label.isNotEmpty ? data.label : data.tooltip;
    final text = label.replaceAll('\n', ' ').trim();
    if (text.isEmpty) return '${role.toLowerCase()} (no label)';
    return '"${text.length > 30 ? '${text.substring(0, 30)}…' : text}"';
  }
}
