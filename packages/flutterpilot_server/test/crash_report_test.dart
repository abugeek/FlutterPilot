import 'package:flutterpilot_server/src/self_heal_manager.dart';
import 'package:test/test.dart';

void main() {
  group('CrashReport', () {
    test('formats Markdown correctly', () {
      final report = CrashReport(
        timestamp: '2026-04-06T12:00:00',
        exception: 'TestException: something went wrong',
        errorData: {'count': 1},
        navigationData: ['/home', '/settings'],
      );

      final markdown = report.toMarkdown();

      expect(markdown, contains('# 🚨 Critical App Crash Report'));
      expect(markdown, contains('**Timestamp:** 2026-04-06T12:00:00'));
      expect(markdown, contains('TestException: something went wrong'));
      expect(markdown, contains('Recent Errors'));
      expect(markdown, contains('Navigation Stack'));
      expect(markdown, contains('DIRECTIVE FOR AI'));
    });

    test('truncates large widget trees', () {
      final largeTree = 'A' * 5000;
      final report = CrashReport(
        timestamp: 'now',
        exception: 'Error',
        widgetTreeData: largeTree,
      );

      final markdown = report.toMarkdown();
      expect(markdown.length, lessThan(5000));
      expect(markdown, contains('[Truncated]'));
    });
  });
}
