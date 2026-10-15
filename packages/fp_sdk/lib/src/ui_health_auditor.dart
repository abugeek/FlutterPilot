import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'widget_inspector.dart';

/// Audits the visible screen for RenderFlex overflows and undersized tap
/// targets.
class UiHealthAuditor {
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
    final seenFlexes = <RenderFlex>{};

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
        });
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

    return {
      'isHealthy': overflows.isEmpty && accessibilityIssues.isEmpty,
      'overflowCount': overflows.length,
      'accessibilityIssueCount': accessibilityIssues.length,
      'overflows': overflows,
      'accessibilityIssues': accessibilityIssues,
    };
  }
}
