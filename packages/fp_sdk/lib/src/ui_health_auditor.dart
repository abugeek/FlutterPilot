import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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

  static Map<String, dynamic> audit() {
    final root = WidgetsBinding.instance.rootElement;
    final overflows = <Map<String, dynamic>>[];
    final cramped = <Map<String, dynamic>>[];
    final clipped = <Map<String, dynamic>>[];
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
        overflows.add({
          'type': element.widget.runtimeType.toString(),
          'details':
              'at (${pos.dx.round()}, ${pos.dy.round()}), '
              '${ro.size.width.round()}x${ro.size.height.round()} — '
              'call get_errors for the overflow amount and source file:line',
          'source': _source(element),
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
          },
    ];

    // Deliberately not part of isHealthy: an ellipsized identifier (a UUID in
    // a table cell) is sometimes the right answer, so clippedText is a list to
    // read, not a pass/fail gate.
    return {
      'isHealthy':
          overflows.isEmpty && cramped.isEmpty && accessibilityIssues.isEmpty,
      'route': NavigationTracker.currentRoute,
      'window': _window(),
      'overflowCount': overflows.length,
      'accessibilityIssueCount': accessibilityIssues.length,
      'crampedScrollableViewCount': cramped.length,
      'clippedTextCount': clipped.length,
      'overflows': overflows,
      'accessibilityIssues': accessibilityIssues,
      'crampedScrollables': cramped,
      'clippedText': clipped,
    };
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
      return SourceLocator.locationOf(element);
    } catch (_) {
      return null;
    }
  }
}
