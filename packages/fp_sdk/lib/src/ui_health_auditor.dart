import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'error_inspector.dart';
import 'navigation_tracker.dart';
import 'source_locator.dart';
import 'widget_inspector.dart';

/// Audits the visible screen for layout defects and undersized tap targets.
///
/// A `RenderFlex` overflow is only the loudest failure. The quiet ones an
/// operator hits first are a scrollable that has no room left to show its
/// content (a landscape phone whose search bar and filter chips fill the
/// window) and a label that is silently cut with an ellipsis. Neither throws,
/// so neither used to appear here.
class UiHealthAuditor {
  /// A vertical scrollable this short cannot show a list row plus a hint; the
  /// screen reads as "empty" even though the list has content.
  static const double minUsableViewport = 120;

  /// Material's 48dp on touch platforms; WCAG 2.5.8's 24px on desktop/web,
  /// where Flutter deliberately uses denser controls.
  static double get minTouchTargetSize {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return kIsWeb ? 24 : 48;
      default:
        return 24;
    }
  }

  static Map<String, dynamic> audit({bool designQuality = false}) {
    final root = WidgetsBinding.instance.rootElement;
    final overflows = <Map<String, dynamic>>[];
    final cramped = <Map<String, dynamic>>[];
    final clipped = <Map<String, dynamic>>[];
    final spacingGridIssues = <Map<String, dynamic>>[];
    final seenFontSizes = <double>{};
    final seenFlexes = <RenderFlex>{};
    final seenViewports = <RenderViewportBase>{};
    final seenParagraphs = <RenderParagraph>{};

    void visit(Element element) {
      final ro = element.renderObject;
      // Row, DefaultTextStyle, etc. can share one RenderFlex; report it once,
      // named after the Flex widget that owns it.
      if (element.widget is Flex &&
          ro is RenderFlex &&
          ro.attached &&
          ro.toString().contains('OVERFLOWING') &&
          seenFlexes.add(ro)) {
        final pos = ro.localToGlobal(Offset.zero);
        final flexOverflow = _computeFlexOverflow(ro);
        final px = flexOverflow['pixels'];
        final side = flexOverflow['side'];
        final src = _source(element);
        final pxStr = px != null ? 'by ${px}px on the $side' : 'on the $side';
        overflows.add({
          'type': element.widget.runtimeType.toString(),
          'pixels': ?px,
          'side': side,
          'axis': flexOverflow['axis'],
          'details':
              'overflowed $pxStr at (${pos.dx.round()}, ${pos.dy.round()}), '
              'size: ${ro.size.width.round()}x${ro.size.height.round()}',
          'source': src,
        });
      }
      // A vertical list that can scroll but shows less than a row: the screen
      // has content the operator cannot see, and nothing throws.
      if (ro is RenderViewportBase &&
          ro.attached &&
          ro.axis == Axis.vertical &&
          seenViewports.add(ro)) {
        final offset = ro.offset;
        if (offset is ScrollPosition &&
            offset.hasContentDimensions &&
            // Content at least twice the viewport: a list that only scrolls a
            // few dp past a 100 dp viewport is short, not starved.
            offset.maxScrollExtent > ro.size.height &&
            ro.size.height < minUsableViewport) {
          final pos = ro.localToGlobal(Offset.zero);
          cramped.add({
            'type': element.widget.runtimeType.toString(),
            'details':
                'at (${pos.dx.round()}, ${pos.dy.round()}): shows '
                '${ro.size.height.round()} dp of '
                '${(ro.size.height + offset.maxScrollExtent).round()} dp '
                'of content, so the list has almost no room',
            'source': _source(element),
          });
        }
      }
      // Text the layout cut (an ellipsis or a clip) although the widget's own
      // parent had room to lay it out differently.
      if (ro is RenderParagraph &&
          ro.attached &&
          seenParagraphs.add(ro) &&
          ro.didExceedMaxLines) {
        final text = ro.text.toPlainText().trim();
        if (text.length > 3) {
          final pos = ro.localToGlobal(Offset.zero);
          clipped.add({
            'text': text.length > 80 ? '${text.substring(0, 80)}…' : text,
            'details':
                'at (${pos.dx.round()}, ${pos.dy.round()}), '
                '${ro.size.width.round()}x${ro.size.height.round()}',
            'source': _source(element),
          });
        }
      }
      // Design Quality: 4/8dp spacing grid adherence & typography audit
      if (designQuality) {
        // Only padding the app's code sets (a Padding, or a Container's
        // padding/margin): the framework's own (a chip's 1dp) can't be
        // changed by the app.
        Element? owner;
        if (ro is RenderPadding && ro.attached) {
          if (debugIsWidgetLocalCreation(element.widget)) {
            owner = element;
          } else {
            element.visitAncestorElements((a) {
              if (a.widget is Container &&
                  debugIsWidgetLocalCreation(a.widget)) {
                owner = a;
              }
              return false;
            });
          }
        }
        if (owner != null && SourceLocator.available) {
          final insets = (ro as RenderPadding).padding.resolve(
            TextDirection.ltr,
          );
          final off = [
            insets.left,
            insets.top,
            insets.right,
            insets.bottom,
          ].where((v) => v > 0 && v % 4 != 0).toList();
          final at = SourceLocator.locationOf(owner!);
          if (off.isNotEmpty && at != null) {
            final seen = spacingGridIssues.where((g) => g['source'] == at);
            if (seen.isNotEmpty) {
              seen.first['count'] = (seen.first['count'] as int) + 1;
            } else if (spacingGridIssues.length < 15) {
              final bad = off.first;
              spacingGridIssues.add({
                'widget': owner!.widget.runtimeType.toString(),
                'details':
                    'padding ${bad.round() == bad ? bad.round() : bad} is off '
                    'the 4dp grid (nearest ${(bad / 4).round() * 4})',
                'source': at,
                'count': 1,
              });
            }
          }
        }
        if (ro is RenderParagraph && ro.attached) {
          final style = ro.text.style;
          if (style?.fontSize != null) {
            seenFontSizes.add(style!.fontSize!);
          }
        }
      }
      element.debugVisitOnstageChildren(visit);
    }

    if (root != null) visit(root);

    final min = minTouchTargetSize;
    final accessibilityIssues = [
      for (final e in PilotWidgetInspector.getInteractiveElements())
        if ((e['bounds']['width'] as int) < min ||
            (e['bounds']['height'] as int) < min)
          {
            'target': e['key'] ?? e['text'] ?? e['type'],
            'type': e['type'],
            'issue':
                'Tap target ${e['bounds']['width']}x${e['bounds']['height']} '
                'is smaller than ${min.round()}x${min.round()}.',
            if (e['source'] != null) 'source': e['source'],
          },
    ];

    final clippedElements = detectClippedElements();

    // Deliberately not part of isHealthy: an ellipsized identifier (a UUID in
    // a table cell) is sometimes the right answer, so clippedText is a list to
    // read, not a pass/fail gate. Clipped interactive elements, however, are
    // severe usability defects that compromise screen interaction.
    final result = <String, dynamic>{
      'isHealthy':
          overflows.isEmpty &&
          cramped.isEmpty &&
          accessibilityIssues.isEmpty &&
          clippedElements.isEmpty,
      'route': NavigationTracker.currentRoute,
      'window': _window(),
      'overflowCount': overflows.length,
      'accessibilityIssueCount': accessibilityIssues.length,
      'crampedScrollableViewCount': cramped.length,
      'clippedTextCount': clipped.length,
      'clippedElementCount': clippedElements.length,
      'overflows': overflows,
      'accessibilityIssues': accessibilityIssues,
      'crampedScrollables': cramped,
      'clippedText': clipped,
      'clippedElements': clippedElements,
    };
    if (designQuality) {
      final sortedSizes = seenFontSizes.toList()..sort();
      result['spacingGridIssues'] = spacingGridIssues;
      result['spacingGridIssueCount'] = spacingGridIssues.length;
      result['typographyHierarchy'] = [
        for (final s in sortedSizes) '${s.round()}sp',
      ];
    }
    return result;
  }

  /// Detects interactive elements that are partially cut off by screen boundaries.
  static List<Map<String, dynamic>> detectClippedElements() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView ??
        WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return const [];
    final dpr = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1.0;
    final logicalWidth = view.physicalSize.width / dpr;
    final logicalHeight = view.physicalSize.height / dpr;
    if (logicalWidth <= 0 || logicalHeight <= 0) return const [];

    final clipped = <Map<String, dynamic>>[];
    for (final e in PilotWidgetInspector.getInteractiveElements()) {
      final bounds = e['bounds'] as Map<String, dynamic>?;
      if (bounds == null) continue;
      final x = (bounds['x'] as num?)?.toDouble() ?? 0.0;
      final y = (bounds['y'] as num?)?.toDouble() ?? 0.0;
      final w = (bounds['width'] as num?)?.toDouble() ?? 0.0;
      final h = (bounds['height'] as num?)?.toDouble() ?? 0.0;

      // Detect partially cut-off interactive controls on screen edges
      final cutBottom = (y + h > logicalHeight) && (y < logicalHeight);
      final cutRight = (x + w > logicalWidth) && (x < logicalWidth);
      final cutTop = (y < 0) && (y + h > 0);
      final cutLeft = (x < 0) && (x + w > 0);

      if (cutBottom || cutRight || cutTop || cutLeft) {
        final cutPx = cutBottom
            ? (y + h - logicalHeight).round()
            : (cutRight ? (x + w - logicalWidth).round() : 0);
        final side = cutBottom
            ? 'bottom'
            : (cutRight ? 'right' : (cutTop ? 'top' : 'left'));
        clipped.add({
          'target': e['key'] ?? e['text'] ?? e['type'],
          'type': e['type'],
          'issue': 'partially clipped by viewport $side edge (cut off by ${cutPx}px)',
          'bounds': bounds,
          if (e['source'] != null) 'source': e['source'],
        });
      }
    }
    return clipped;
  }

  /// Calculates the overflow amount and overflowing edge of a [RenderFlex].
  static Map<String, dynamic> _computeFlexOverflow(RenderFlex ro) {
    try {
      final isVertical = ro.direction == Axis.vertical;
      double maxChildEnd = 0.0;
      double maxCrossEnd = 0.0;
      RenderBox? child = ro.firstChild;
      while (child != null) {
        if (child.hasSize) {
          final parentData = child.parentData;
          if (parentData is BoxParentData) {
            final end = isVertical
                ? parentData.offset.dy + child.size.height
                : parentData.offset.dx + child.size.width;
            if (end > maxChildEnd) maxChildEnd = end;

            final crossEnd = isVertical
                ? parentData.offset.dx + child.size.width
                : parentData.offset.dy + child.size.height;
            if (crossEnd > maxCrossEnd) maxCrossEnd = crossEnd;
          }
        }
        final dynamic p = child.parentData;
        try {
          child = p.nextSibling as RenderBox?;
        } catch (_) {
          child = null;
        }
      }
      final mainSize = isVertical ? ro.size.height : ro.size.width;
      final crossSize = isVertical ? ro.size.width : ro.size.height;

      double overflowPixels = 0.0;
      String side = isVertical ? 'bottom' : 'right';
      if (maxChildEnd > mainSize) {
        overflowPixels = maxChildEnd - mainSize;
      } else if (maxCrossEnd > crossSize) {
        overflowPixels = maxCrossEnd - crossSize;
        side = isVertical ? 'right' : 'bottom';
      }

      // Also check ErrorInspector for an exact match from the Flutter error report
      if (overflowPixels <= 0.0) {
        for (final err in ErrorInspector.errors.reversed) {
          final diag = err['overflowDiagnosis'] as Map<String, dynamic>?;
          if (diag != null && diag['overflowPixels'] != null) {
            overflowPixels = (diag['overflowPixels'] as num).toDouble();
            side = diag['side']?.toString() ?? side;
            break;
          }
        }
      }

      final roundedPixels = (overflowPixels * 10).round() / 10;
      return {
        'pixels': roundedPixels > 0 ? roundedPixels : null,
        'side': side,
        'axis': isVertical ? 'vertical' : 'horizontal',
      };
    } catch (_) {
      return {'pixels': null, 'side': 'edge', 'axis': 'unknown'};
    }
  }

  /// The window the findings belong to: a landscape phone at 1.3x and a
  /// desktop window produce different reports for the same route.
  static String _window() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return 'unknown';
    final size = view.physicalSize / view.devicePixelRatio;
    final scale = view.platformDispatcher.textScaleFactor;
    return '${size.width.round()}x${size.height.round()} @${scale.toStringAsFixed(2)}x';
  }

  static String? _source(Element element) {
    try {
      final direct = SourceLocator.locationOf(element);
      if (direct != null && !direct.contains('package:flutter/')) {
        return direct;
      }
      String? appLoc;
      element.visitAncestorElements((a) {
        if (debugIsWidgetLocalCreation(a.widget)) {
          final loc = SourceLocator.locationOf(a);
          if (loc != null) {
            appLoc = '$loc (${a.widget.runtimeType})';
            return false;
          }
        }
        return true;
      });
      return appLoc ?? direct;
    } catch (_) {
      return null;
    }
  }
}
