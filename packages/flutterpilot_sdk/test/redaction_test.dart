import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/redaction.dart';

void main() {
  group('Redaction.text', () {
    test('masks credentials in logs, URLs and JSON-ish text', () {
      expect(
        Redaction.text('signing in with api_key=LOG1 password: LOG2'),
        'signing in with api_key=<redacted> password: <redacted>',
      );
      expect(
        Redaction.text('https://x.io/login?api_key=U3&page=1&token=T4'),
        'https://x.io/login?api_key=<redacted>&page=1&token=<redacted>',
      );
      expect(
        Redaction.text('{"user": "pilot", "password": "B4", "id": 7}'),
        '{"user": "pilot", "password": "<redacted>", "id": 7}',
      );
      expect(
        Redaction.text('Authorization: Bearer abc.def-123456'),
        'Authorization: <redacted> <redacted>',
      );
      expect(
        Redaction.text('got eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOjF9.c2lnbmF0dXJl'),
        'got <redacted>',
      );
    });

    test('names that only look alike are not secrets', () {
      for (final name in ['author', 'passengers', 'sessionCount', 'bypass']) {
        expect(Redaction.sensitiveName.hasMatch(name), isFalse, reason: name);
      }
      for (final name in ['authToken', 'userPassword', 'sessionId', 'auth']) {
        expect(Redaction.sensitiveName.hasMatch(name), isTrue, reason: name);
      }
    });

    test('leaves ordinary text alone', () {
      const plain = 'Loaded 30 stories in 540 ms; page=2 of 5, user: pilot';
      expect(Redaction.text(plain), plain);
    });
  });

  group('isReadOnlySqlStatement', () {
    test('reads pass', () {
      for (final sql in [
        'SELECT * FROM users',
        "SELECT replace(name, 'a', 'b') FROM users;",
        "SELECT * FROM t WHERE note = 'please DELETE me'",
        'WITH x AS (SELECT 1) SELECT * FROM x',
        'EXPLAIN QUERY PLAN SELECT * FROM users',
        'PRAGMA table_info(users)',
        'PRAGMA main.user_version',
        "SELECT name FROM sqlite_master WHERE type='table'",
      ]) {
        expect(isReadOnlySqlStatement(sql), isTrue, reason: sql);
      }
    });

    test('writes are refused, however they are dressed', () {
      for (final sql in [
        'WITH x AS (SELECT 1) DELETE FROM users',
        'WITH x AS (SELECT 1) INSERT INTO users VALUES (1)',
        'PRAGMA main.journal_mode = DELETE',
        'PRAGMA user_version = 5',
        'PRAGMA optimize',
        'SELECT 1; DROP TABLE users',
        'SELECT * INTO backup FROM users',
        'DELETE FROM users',
        'REPLACE INTO users VALUES (1)',
        '/* SELECT */ UPDATE users SET a = 1',
        'ATTACH DATABASE "x.db" AS x',
        '',
      ]) {
        expect(isReadOnlySqlStatement(sql), isFalse, reason: sql);
      }
    });
  });
}
