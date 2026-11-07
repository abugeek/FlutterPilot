import 'navigation_tracker.dart';
import 'ui_health_auditor.dart';
import 'widget_inspector.dart';

/// What crawl_app may tap on the current screen, and the screen's health.
///
/// Only navigation-shaped elements: list rows, cards, tabs and navigation
/// destinations. Buttons, chips, checkboxes and switches are never tapped —
/// they save, send, toggle or open links (an "Open link" button leaves the
/// app). A row whose label reads like an action is skipped too.
class AppCrawler {
  AppCrawler._();

  static const _navigationTypes = <String>{
    'ListTile',
    'Card',
    'InkWell',
    'NavigationDestination',
    'NavigationRailDestination',
    'BottomNavigationBarItem',
    'Tab',
  };

  static final _actionWords = RegExp(
    r'\b(delete|remove|log ?out|sign ?out|clear|reset|exit|discard|cancel|'
    r'save|bookmark|share|send|submit|buy|pay|order|checkout|confirm|call|'
    r'open link|download|install|unsubscribe|archive|block|report)\b',
    caseSensitive: false,
  );

  static Map<String, dynamic> inspectScreenForCrawl() {
    final candidates = <Map<String, dynamic>>[];
    for (final el in PilotWidgetInspector.getInteractiveElements()) {
      final type = (el['type'] ?? '').toString();
      final label = (el['text'] ?? el['label'] ?? el['key'] ?? '').toString();
      if (!_navigationTypes.contains(type) || label.isEmpty) continue;
      if (_actionWords.hasMatch(label)) continue;
      candidates.add({
        'label': label,
        'type': type,
        'key': el['key'],
        'bounds': el['bounds'],
      });
    }
    final health = UiHealthAuditor.audit();
    return {
      'currentRoute': NavigationTracker.currentRoute.isEmpty
          ? '/'
          : NavigationTracker.currentRoute,
      'overflowCount': health['overflowCount'],
      'accessibilityIssueCount': health['accessibilityIssueCount'],
      'navigableCandidates': candidates,
    };
  }
}
