import 'package:flutterpilot_server/src/self_heal_manager.dart';
import 'package:test/test.dart';

void main() {
  group('CrashReport edge cases', () {
    test('handles all null optional fields gracefully', () {
      final report = CrashReport(
        timestamp: '2026-01-01T00:00:00',
        exception: 'NullFieldException',
      );

      final md = report.toMarkdown();

      expect(md, contains('# 🚨 Critical App Crash Report'));
      expect(md, contains('**Timestamp:** 2026-01-01T00:00:00'));
      expect(md, contains('NullFieldException'));
      // All optional sections should show "No data available."
      expect(md, contains('No data available.'));
      expect(md, contains('DIRECTIVE FOR AI'));
    });

    test('handles N/A string data (from failed extensions)', () {
      final report = CrashReport(
        timestamp: '2026-01-01T00:00:00',
        exception: 'Error',
        errorData: 'N/A',
        riverpodData: 'N/A',
        blocData: 'N/A',
        networkData: 'N/A',
        navigationData: 'N/A',
      );

      final md = report.toMarkdown();

      // "N/A" is treated as "No data available." by _addSection
      final noDataCount = 'No data available.'.allMatches(md).length;
      expect(noDataCount, greaterThanOrEqualTo(5));
    });

    test('includes json code blocks for non-null data', () {
      final report = CrashReport(
        timestamp: 'now',
        exception: 'Error',
        errorData: {'count': 3, 'items': []},
        navigationData: ['/home', '/settings'],
      );

      final md = report.toMarkdown();

      // Sections with actual data should be wrapped in ```json blocks
      expect(md, contains('```json'));
      expect(md, contains('```'));
    });

    test('truncates widget tree at exactly 2000 chars', () {
      // Exactly 2000 chars → should NOT truncate
      final exactTree = 'X' * 2000;
      final report = CrashReport(
        timestamp: 'now',
        exception: 'Error',
        widgetTreeData: exactTree,
      );

      final md = report.toMarkdown();
      expect(md, isNot(contains('[Truncated]')));
    });

    test('truncates widget tree at 2001 chars', () {
      final overTree = 'Y' * 2001;
      final report = CrashReport(
        timestamp: 'now',
        exception: 'Error',
        widgetTreeData: overTree,
      );

      final md = report.toMarkdown();
      expect(md, contains('[Truncated]'));
    });

    test('handles empty string exception', () {
      final report = CrashReport(timestamp: 'now', exception: '');

      final md = report.toMarkdown();

      expect(md, contains('## Exception'));
    });

    test('handles complex nested data structures', () {
      final report = CrashReport(
        timestamp: 'now',
        exception: 'NestedError',
        errorData: {
          'errors': [
            {
              'exception': 'NullPointer',
              'stack': ['frame1', 'frame2'],
              'context': {'widget': 'Button', 'key': 'submit-btn'},
            },
          ],
        },
        riverpodData: {
          'states': {
            'authProvider': {'value': null, 'type': 'AsyncValue<User?>'},
          },
        },
      );

      final md = report.toMarkdown();

      expect(md, contains('Recent Errors'));
      expect(md, contains('Riverpod State'));
    });

    test('handles widget tree that is null', () {
      final report = CrashReport(
        timestamp: 'now',
        exception: 'Error',
        widgetTreeData: null,
      );

      final md = report.toMarkdown();

      // Null widget tree → "No data available."
      expect(md, contains('Widget Tree Snippet'));
      expect(md, contains('No data available.'));
    });

    test('all six section headers are present', () {
      final report = CrashReport(timestamp: 'now', exception: 'Error');

      final md = report.toMarkdown();

      expect(md, contains('## Recent Errors'));
      expect(md, contains('## Riverpod State'));
      expect(md, contains('## Bloc State'));
      expect(md, contains('## Network Logs'));
      expect(md, contains('## Navigation Stack'));
      expect(md, contains('## Widget Tree Snippet'));
    });

    test('integer and boolean data rendered in json block', () {
      final report = CrashReport(
        timestamp: 'now',
        exception: 'Error',
        errorData: 42,
        riverpodData: true,
      );

      final md = report.toMarkdown();

      expect(md, contains('42'));
      expect(md, contains('true'));
    });
  });
}
