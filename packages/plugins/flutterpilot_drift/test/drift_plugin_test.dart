import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_drift/flutterpilot_drift.dart';

void main() {
  group('DriftPilotInspector', () {
    group('SQL validation', () {
      test('allows safe read-only queries', () {
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest('SELECT * FROM users'),
          isTrue,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest('EXPLAIN SELECT 1'),
          isTrue,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'PRAGMA table_info(users)',
          ),
          isTrue,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'WITH cte AS (SELECT 1) SELECT * FROM cte',
          ),
          isTrue,
        );
      });

      test('blocks destructive statements', () {
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'INSERT INTO users VALUES (1)',
          ),
          isFalse,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest('DELETE FROM users'),
          isFalse,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'UPDATE users SET name="x"',
          ),
          isFalse,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest('DROP TABLE users'),
          isFalse,
        );
      });

      test('blocks multi-statement injection', () {
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'SELECT 1; DROP TABLE users',
          ),
          isFalse,
        );
      });

      test('blocks SELECT INTO', () {
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'SELECT * INTO OUTFILE "x" FROM users',
          ),
          isFalse,
        );
      });

      test('blocks dangerous PRAGMAs', () {
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest('PRAGMA journal_mode=WAL'),
          isFalse,
        );
        expect(
          DriftPilotInspector.isSafeReadOnlyForTest(
            'PRAGMA writable_schema=ON',
          ),
          isFalse,
        );
      });
    });

    test('unregister does not throw for nonexistent database', () {
      expect(
        () => DriftPilotInspector.unregister('nonexistent'),
        returnsNormally,
      );
    });
  });
}
