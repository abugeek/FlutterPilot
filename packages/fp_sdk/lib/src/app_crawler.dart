import 'navigation_tracker.dart';
import 'ui_health_auditor.dart';
import 'widget_inspector.dart';

/// Client-side app crawling and route graph discovery for FlutterPilot.
///
/// Finds navigable elements on the active screen, filters out destructive
/// actions, and reports candidates for route exploration.
class AppCrawler {
  AppCrawler._();

  static const _destructivePatterns = <String>[
    'delete',
    'remove',
    'logout',
    'sign out',
    'signout',
    'clear',
    'reset',
    'exit',
    'discard',
    'cancel subscription',
  ];

  /// Gathers navigation candidates from the current screen.
  static Map<String, dynamic> inspectScreenForCrawl() {
    final currentRoute = NavigationTracker.currentRoute.isEmpty
        ? '/'
        : NavigationTracker.currentRoute;
    final interactive = PilotWidgetInspector.getInteractiveElements();

    final navigableCandidates = <Map<String, dynamic>>[];

    for (final el in interactive) {
      final label = (el['text'] ?? el['label'] ?? el['key'] ?? el['type'] ?? '').toString();
      final lowerLabel = label.toLowerCase();

      // Skip destructive buttons
      final isDestructive = _destructivePatterns.any(
        (pattern) => lowerLabel.contains(pattern),
      );
      if (isDestructive) continue;

      // Identify navigation-friendly elements
      final type = (el['type'] ?? '').toString();
      final isNavFriendly = type.contains('ListTile') ||
          type.contains('Tab') ||
          type.contains('BottomNavigationBar') ||
          type.contains('NavigationDestination') ||
          type.contains('Card') ||
          type.contains('Button') ||
          type.contains('InkWell');

      if (isNavFriendly && label.isNotEmpty) {
        navigableCandidates.add({
          'label': label,
          'type': type,
          'key': el['key'],
          'bounds': el['bounds'],
        });
      }
    }

    final health = UiHealthAuditor.audit(designQuality: true);

    return {
      'currentRoute': currentRoute,
      'isHealthy': health['isHealthy'],
      'overflowCount': health['overflowCount'],
      'accessibilityIssueCount': health['accessibilityIssueCount'],
      'navigableCandidateCount': navigableCandidates.length,
      'navigableCandidates': navigableCandidates.take(10).toList(),
      'healthSummary': health,
    };
  }
}
