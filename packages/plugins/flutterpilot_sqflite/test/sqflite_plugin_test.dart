import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sqflite/flutterpilot_sqflite.dart';

void main() {
  setUp(() => SqflitePilotInspector.reset());

  group('SqflitePilotInspector', () {
    group('registration', () {
      test('registeredDatabases is empty initially', () {
        expect(SqflitePilotInspector.registeredDatabases, isEmpty);
      });

      test('unregister does not throw for nonexistent database', () {
        expect(
          () => SqflitePilotInspector.unregister('nonexistent'),
          returnsNormally,
        );
      });

      test('reset clears state', () {
        // Can't register a real DB without sqflite FFI in tests, but we can
        // verify reset doesn't throw.
        expect(() => SqflitePilotInspector.reset(), returnsNormally);
        expect(SqflitePilotInspector.registeredDatabases, isEmpty);
      });
    });

    group('SQL validation', () {
      test('allows safe read-only queries', () {
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest('SELECT * FROM users'),
          isTrue,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest('EXPLAIN SELECT 1'),
          isTrue,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'PRAGMA table_info(users)',
          ),
          isTrue,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'WITH cte AS (SELECT 1) SELECT * FROM cte',
          ),
          isTrue,
        );
      });

      test('blocks destructive statements', () {
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'INSERT INTO users VALUES (1)',
          ),
          isFalse,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest('DELETE FROM users'),
          isFalse,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'UPDATE users SET name="x"',
          ),
          isFalse,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest('DROP TABLE users'),
          isFalse,
        );
      });

      test('blocks multi-statement injection', () {
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'SELECT 1; DROP TABLE users',
          ),
          isFalse,
        );
      });

      test('blocks SELECT INTO', () {
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'SELECT * INTO OUTFILE "x" FROM users',
          ),
          isFalse,
        );
      });

      test('blocks dangerous PRAGMAs', () {
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'PRAGMA journal_mode=WAL',
          ),
          isFalse,
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'PRAGMA writable_schema=ON',
          ),
          isFalse,
        );
      });

      test('blocks SQL comment injection', () {
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'SELECT 1 -- ; DROP TABLE users',
          ),
          isTrue, // Comment stripped, remainder is a valid SELECT
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            '/* DROP TABLE users */ SELECT 1',
          ),
          isTrue, // Comment stripped, remainder is a valid SELECT
        );
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest(
            'DROP TABLE users -- hidden',
          ),
          isFalse, // Even with comment, DROP is not allowed
        );
      });

      test('blocks empty queries', () {
        expect(SqflitePilotInspector.isSafeReadOnlyForTest(''), isFalse);
        expect(SqflitePilotInspector.isSafeReadOnlyForTest('   '), isFalse);
        expect(
          SqflitePilotInspector.isSafeReadOnlyForTest('-- just a comment'),
          isFalse,
        );
      });
    });
  });
}
