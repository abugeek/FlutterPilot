import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IssueDetector Centralized Engine Tests', () {
    setUp(() {
      IssueDetector.clear();
    });

    test('clean state returns null alert and healthy status (0 tokens wasted)', () {
      final alert = IssueDetector.getActionAlertSummary();
      expect(alert, isNull);

      final summary = IssueDetector.getSummaryJson();
      expect(summary['isHealthy'], isTrue);
      expect(summary['criticalCount'], equals(0));
      expect(summary['warningCount'], equals(0));
      expect((summary['issues'] as List).isEmpty, isTrue);
    });

    test('automatically detects Supabase RLS policy violations from console logs', () {
      IssueDetector.sniffLog(
        'PostgrestException(message: new row violates row-level security policy for table "orders", code: 42501)',
      );

      final summary = IssueDetector.getSummaryJson();
      expect(summary['isHealthy'], isFalse);
      expect(summary['criticalCount'], equals(1));

      final alert = IssueDetector.getActionAlertSummary(markSeen: false);
      expect(alert, contains('🚨 CRITICAL [dataSync]'));
      expect(alert, contains('Supabase RLS Policy Violation'));
    });

    test('automatically detects Firebase permission-denied security rule violations', () {
      IssueDetector.sniffLog(
        '[cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.',
      );

      final summary = IssueDetector.getSummaryJson();
      expect(summary['criticalCount'], equals(1));
      expect(summary['issues'].first['category'], equals('dataSync'));
      expect(summary['issues'].first['title'], contains('Firebase Permission Denied'));
    });

    test('automatically detects RenderFlex visual layout overflows', () {
      IssueDetector.sniffLog(
        'A RenderFlex overflowed by 28.5 pixels on the bottom.',
      );

      final summary = IssueDetector.getSummaryJson();
      expect(summary['criticalCount'], equals(1));
      expect(summary['issues'].first['category'], equals('uiLayout'));
      expect(summary['issues'].first['title'], contains('RenderFlex Overflow'));
    });

    test('automatically detects offline network failure and database sync errors', () {
      IssueDetector.sniffLog(
        'SocketException: Failed host lookup: "api.backend.com" (OS Error: No address associated with hostname, errno = 7)',
      );

      IssueDetector.sniffLog(
        'SqliteException(5): database is locked, sync failed on local queue',
      );

      final summary = IssueDetector.getSummaryJson();
      expect(summary['criticalCount'], equals(2));
      final titles = (summary['issues'] as List).map((i) => i['title'].toString()).toList();
      expect(titles.any((t) => t.contains('Network Unreachable')), isTrue);
      expect(titles.any((t) => t.contains('Database / Offline Sync')), isTrue);
    });

    test('deduplicates recurring issues and increments occurrenceCount', () {
      IssueDetector.sniffLog('A RenderFlex overflowed by 15.0 pixels on the right.');
      IssueDetector.sniffLog('A RenderFlex overflowed by 15.0 pixels on the right.');
      IssueDetector.sniffLog('A RenderFlex overflowed by 15.0 pixels on the right.');

      final summary = IssueDetector.getSummaryJson();
      expect(summary['criticalCount'], equals(1));
      final issue = summary['issues'].first;
      expect(issue['occurrenceCount'], equals(3));
    });

    test('supports manual high-level issue recording', () {
      FlutterPilot.recordSyncError(
        'Cloud sync queue stalled',
        queueLength: 42,
        details: 'Server returned 504 Gateway Timeout during batch upload',
      );

      final summary = IssueDetector.getSummaryJson();
      expect(summary['criticalCount'], equals(1));
      expect(summary['issues'].first['metadata']['queueLength'], equals(42));
    });

    test('filters issues by severity accurately', () {
      IssueDetector.recordIssue(
        severity: IssueSeverity.info,
        category: IssueCategory.performance,
        title: 'Minor cache miss',
      );
      IssueDetector.recordIssue(
        severity: IssueSeverity.warning,
        category: IssueCategory.uiLayout,
        title: 'Touch target is 36dp (recommended 48dp)',
      );
      IssueDetector.recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.dataSync,
        title: 'Database connection failed',
      );

      final criticalOnly = IssueDetector.getSummaryJson(minSeverity: IssueSeverity.critical);
      expect((criticalOnly['issues'] as List).length, equals(1));

      final warningsAndAbove = IssueDetector.getSummaryJson(minSeverity: IssueSeverity.warning);
      expect((warningsAndAbove['issues'] as List).length, equals(2));

      final all = IssueDetector.getSummaryJson(minSeverity: IssueSeverity.info);
      expect((all['issues'] as List).length, equals(3));
    });
  });
}
