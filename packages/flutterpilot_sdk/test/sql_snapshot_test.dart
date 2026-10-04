import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A database that answers the catalog queries [SqlSnapshot] makes and
/// remembers the statements it runs. (The real engines are exercised
/// through the Drift and sqflite plugins in a running app.)
class _Db {
  _Db(this.tables, {this.sql = const {}, this.sequences = const {}});

  final Map<String, List<Map<String, Object?>>> tables;
  final Map<String, String> sql;
  final Map<String, int> sequences;
  final statements = <String>[];
  final arguments = <List<Object?>>[];

  Future<List<Map<String, Object?>>> select(
    String q,
    List<Object?> args,
  ) async {
    if (q.contains('FROM sqlite_master')) {
      return [
        for (final t in tables.keys)
          {'name': t, 'sql': sql[t] ?? 'CREATE TABLE "$t" (...)'},
        if (sequences.isNotEmpty && !q.contains('NOT LIKE'))
          {'name': 'sqlite_sequence', 'sql': ''},
      ];
    }
    if (q == 'SELECT name, seq FROM sqlite_sequence') {
      if (sequences.isEmpty) throw StateError('no such table');
      return [
        for (final e in sequences.entries) {'name': e.key, 'seq': e.value},
      ];
    }
    final table = RegExp(r'"([^"]+)"\)?$').firstMatch(q)![1]!;
    if (q.startsWith('SELECT COUNT')) {
      return [
        {'c': tables[table]!.length},
      ];
    }
    if (q.startsWith('PRAGMA table_xinfo')) {
      return [
        for (final c in tables[table]!.first.keys)
          {'name': c, 'hidden': c == 'total' ? 2 : 0},
      ];
    }
    return tables[table]!;
  }

  Future<void> execute(String q, List<Object?> args) async {
    statements.add(q);
    arguments.add(args);
  }
}

void main() {
  test('dump writes rows, blobs and sequences; not what it can\'t', () async {
    final db = _Db(
      {
        'cart': [
          {'id': 1, 'name': 'Milk', 'total': 3},
          {'id': 2, 'name': 'Tea', 'total': 5},
        ],
        'photos': [
          {
            'id': 1,
            'data': Uint8List.fromList([1, 2, 3]),
          },
        ],
        'search': [
          {'q': 'x'},
        ],
        'search_data': [
          {'id': 1},
        ],
        'log': [
          for (var i = 0; i <= SqlSnapshot.maxRowsPerTable; i++) {'id': i},
        ],
        'android_metadata': [
          {'locale': 'en_US'},
        ],
      },
      sql: {'search': 'CREATE VIRTUAL TABLE search USING fts5(q)'},
      sequences: {'cart': 2, 'log': 1001},
    );

    final dump = await SqlSnapshot.dump(db.select);
    expect(dump['tables'], {
      // `total` is a generated column: an INSERT can't set it.
      'cart': [
        {'id': 1, 'name': 'Milk'},
        {'id': 2, 'name': 'Tea'},
      ],
      'photos': [
        {
          'id': 1,
          'data': {r'$blob': 'AQID'},
        },
      ],
    });
    expect(dump['sequences'], {'cart': 2});
    expect(dump['skipped'], [
      'search (virtual table)',
      'log (1001 rows, over 1000)',
    ]);
  });

  test('restore empties the named tables and inserts the rows', () async {
    final db = _Db(
      {
        'cart': [
          {'id': 9},
        ],
        'photos': [
          {'id': 9},
        ],
        'users': [
          {'id': 9},
        ],
      },
      sequences: {'cart': 7},
    );
    final written = await SqlSnapshot.restore(
      {
        'cart': [
          {'id': 1, 'name': 'Milk'},
        ],
        'photos': [
          {
            'id': 1,
            'data': {r'$blob': 'AQID'},
          },
        ],
      },
      {'cart': 1},
      select: db.select,
      execute: db.execute,
    );
    expect(written, {'cart': 1, 'photos': 1});
    expect(db.statements, [
      'PRAGMA defer_foreign_keys = ON',
      'DELETE FROM "cart"',
      'DELETE FROM "photos"',
      'INSERT INTO "cart" ("id", "name") VALUES (?, ?)',
      'INSERT INTO "photos" ("id", "data") VALUES (?, ?)',
      'DELETE FROM sqlite_sequence WHERE name = ?',
      'INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)',
      'DELETE FROM sqlite_sequence WHERE name = ?',
    ]);
    expect(db.arguments[3], [1, 'Milk']);
    expect(db.arguments[4], [
      1,
      Uint8List.fromList([1, 2, 3]),
    ]);
    // `users` is not in the scenario: untouched.
    expect(db.statements.join(), isNot(contains('users')));
  });

  test('a table the database lacks changes nothing', () async {
    final db = _Db({
      'cart': [
        {'id': 1},
      ],
    });
    await expectLater(
      SqlSnapshot.restore(
        {'basket': []},
        const {},
        select: db.select,
        execute: db.execute,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('no table basket'), contains('cart')),
        ),
      ),
    );
    expect(db.statements, isEmpty);
  });
}
