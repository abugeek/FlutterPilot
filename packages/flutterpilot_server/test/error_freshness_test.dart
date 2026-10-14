import 'package:flutterpilot_server/src/error_freshness.dart';
import 'package:test/test.dart';

Map<String, dynamic> error(String timestamp, {String exception = 'Boom'}) => {
  'exception': exception,
  'timestamp': timestamp,
};

void main() {
  group('errorsByReload', () {
    test('splits the list at the reload', () {
      final split = errorsByReload([
        error('2026-10-14T15:00:00.000Z'),
        error('2026-10-14T15:10:00.000Z'),
        error('2026-10-14T15:20:00.000Z'),
      ], DateTime.parse('2026-10-14T15:15:00.000Z'));

      expect(split.before.map((e) => e['timestamp']), [
        '2026-10-14T15:00:00.000Z',
        '2026-10-14T15:10:00.000Z',
      ]);
      expect(split.since.map((e) => e['timestamp']), [
        '2026-10-14T15:20:00.000Z',
      ]);
    });

    test('with no reload since the connection nothing is called before it', () {
      final split = errorsByReload([error('2026-10-14T15:00:00.000Z')], null);

      expect(split.before, isEmpty);
      expect(split.since, hasLength(1));
    });

    test('an error at the reload itself counts as since', () {
      final split = errorsByReload([
        error('2026-10-14T15:15:00.000Z'),
      ], DateTime.parse('2026-10-14T15:15:00.000Z'));

      expect(split.before, isEmpty);
      expect(split.since, hasLength(1));
    });

    test('an entry with no timestamp counts as since, not before', () {
      final split = errorsByReload([
        {'exception': 'No timestamp'},
      ], DateTime.parse('2026-10-14T15:15:00.000Z'));

      expect(split.before, isEmpty);
      expect(split.since.single['exception'], 'No timestamp');
    });

    test('an empty list splits into two empties', () {
      final split = errorsByReload(
        const [],
        DateTime.parse('2026-10-14T15:15:00.000Z'),
      );

      expect(split.since, isEmpty);
      expect(split.before, isEmpty);
    });

    test('the entries are the same objects, in order', () {
      final first = error('2026-10-14T15:00:00.000Z');
      final second = error('2026-10-14T15:20:00.000Z');
      final split = errorsByReload([
        first,
        second,
      ], DateTime.parse('2026-10-14T15:15:00.000Z'));

      expect(split.before.single, same(first));
      expect(split.since.single, same(second));
    });
  });

  group('beforeReloadNote', () {
    test('says how many and what the reload may have done', () {
      expect(
        beforeReloadNote(1),
        '1 uncaught exception from before the last reload (the reload may '
        'have fixed it)',
      );
      expect(beforeReloadNote(2), contains('2 uncaught exceptions'));
      expect(beforeReloadNote(2), contains('may have fixed them'));
    });
  });
}
