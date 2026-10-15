import 'package:fp_server/src/truncation.dart';
import 'package:test/test.dart';

void main() {
  group('truncationNote', () {
    test('names the shown count, the exact total and how to see more', () {
      expect(
        truncationNote(
          shown: 100,
          total: 342,
          what: 'log lines',
          how: 'Narrow with level or raise limit (max 500).',
        ),
        'Showing 100 of 342 log lines. Narrow with level or raise limit '
        '(max 500).',
      );
    });

    test('says "at least" when the total is not known', () {
      expect(
        truncationNote(
          shown: 20,
          total: null,
          what: 'documents',
          how: 'Raise limit (1-100).',
        ),
        'Showing 20 of at least 21 documents. Raise limit (1-100).',
      );
    });

    test('no note when the list is complete', () {
      expect(
        truncationNote(shown: 100, total: 100, what: 'rows', how: 'x'),
        isNull,
      );
      expect(
        truncationNote(shown: 100, total: 12, what: 'rows', how: 'x'),
        isNull,
      );
    });

    test('a cut of one still gets a note', () {
      expect(
        truncationNote(shown: 50, total: 51, what: 'rows', how: 'Page.'),
        'Showing 50 of 51 rows. Page.',
      );
    });
  });
}
