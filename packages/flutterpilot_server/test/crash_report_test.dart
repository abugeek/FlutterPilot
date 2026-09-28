import 'package:flutterpilot_server/src/self_heal_manager.dart';
import 'package:test/test.dart';

void main() {
  group('CrashReport', () {
    final report = CrashReport(
      timestamp: '2026-09-28T11:06:50',
      exception: 'Bad state: Boom',
      errorData: {
        'errors': [
          {
            'exception': 'Other',
            'stackTrace': '#0 other (package:app/a.dart:1:1)',
          },
          {
            'exception': 'Bad state: Boom',
            'stackTrace':
                '#0 _HomeState.build (package:app/main.dart:73:28)\n'
                '  ... [8 framework frames skipped]',
          },
        ],
      },
      riverpodData: {
        'states': {
          'counterProvider': {'value': 3, 'type': 'int'},
          'itemsProvider': {'value': 'x' * 500, 'type': 'List'},
        },
      },
      blocData: 'N/A',
      networkData: {
        'logs': [
          for (var i = 0; i < 10; i++)
            {'type': 'response', 'uri': 'https://api/$i', 'statusCode': 200},
        ],
      },
      navigationData: {
        'stack': ['/', '/cart'],
      },
    );
    final md = report.toMarkdown();

    test('says what happened, without alarm or directives', () {
      expect(md, startsWith('# Uncaught exception\n\nBad state: Boom'));
      expect(md, isNot(contains('CRITICAL')));
      expect(md, isNot(contains('DIRECTIVE')));
    });

    test('shows the crashing error\'s app frame, not other errors', () {
      expect(md, contains('package:app/main.dart:73:28'));
      expect(md, isNot(contains('a.dart')));
    });

    test('route, clipped state and the last 6 requests', () {
      expect(md, contains('/ -> /cart'));
      expect(md, contains('counterProvider: 3'));
      expect(md, isNot(contains('x' * 150)));
      expect(md, contains('https://api/9'));
      expect(md, contains('https://api/4'));
      expect(md, isNot(contains('https://api/3 ')));
    });

    test('leaves out sections without data', () {
      final bare = CrashReport(
        timestamp: 't',
        exception: 'E',
        errorData: 'N/A',
        riverpodData: 'N/A',
        blocData: null,
        networkData: 'N/A',
        navigationData: 'N/A',
      ).toMarkdown();
      expect(bare, isNot(contains('##')));
      expect(bare, contains('hot_reload'));
    });

    test('stays small', () {
      expect(md.length, lessThan(1500));
    });
  });
}
