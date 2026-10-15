import 'dart:convert';
import 'dart:typed_data';

/// Runs a query on the app's database and returns its rows.
typedef SqlSelect =
    Future<List<Map<String, Object?>>> Function(String sql, List<Object?> args);

/// Runs a statement on the app's database.
typedef SqlExecute = Future<void> Function(String sql, List<Object?> args);

/// The rows of a SQLite database as JSON and back, for scenarios: the
/// database plugins (Drift, sqflite) pass their own connection, so it works
/// the same on every platform and with the database open.
///
/// Rows only, not the schema: a scenario is loaded into the tables the app
/// has now.
class SqlSnapshot {
  /// A table with more rows is not saved (scenario files are checked in).
  static const maxRowsPerTable = 1000;

  static String _q(String name) => '"${name.replaceAll('"', '""')}"';

  /// Every table's rows: `{tables: {name: [row, ...]}, sequences: {name:
  /// seq}, skipped: ["name (why)"]}`. Blobs become `{"$blob": base64}`.
  static Future<Map<String, Object?>> dump(SqlSelect select) async {
    final master = await select(
      "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      const [],
    );
    final virtual = [
      for (final t in master)
        if ('${t['sql']}'.toUpperCase().startsWith('CREATE VIRTUAL TABLE'))
          '${t['name']}',
    ];
    final tables = <String, Object?>{};
    final skipped = <String>[];
    for (final t in master) {
      final name = '${t['name']}';
      if (name == 'android_metadata') continue;
      if (virtual.contains(name)) {
        skipped.add('$name (virtual table)');
        continue;
      }
      // A virtual table's own storage (fts5: name_data, name_idx, ...).
      if (virtual.any((v) => name.startsWith('${v}_'))) continue;

      final count = await select('SELECT COUNT(*) AS c FROM ${_q(name)}', []);
      final rows = (count.first['c'] as num?)?.toInt() ?? 0;
      if (rows > maxRowsPerTable) {
        skipped.add('$name ($rows rows, over $maxRowsPerTable)');
        continue;
      }
      final columns = await _columns(select, name);
      if (columns.isEmpty) continue;
      final data = await select(
        'SELECT ${columns.map(_q).join(', ')} FROM ${_q(name)}',
        const [],
      );
      tables[name] = [
        for (final row in data) {for (final c in columns) c: _encode(row[c])},
      ];
    }

    final sequences = <String, Object?>{};
    try {
      for (final s in await select(
        'SELECT name, seq FROM sqlite_sequence',
        const [],
      )) {
        if (tables.containsKey(s['name'])) sequences['${s['name']}'] = s['seq'];
      }
    } catch (_) {
      // No AUTOINCREMENT table: sqlite_sequence does not exist.
    }
    return {'tables': tables, 'sequences': sequences, 'skipped': skipped};
  }

  /// The columns an INSERT can set: not generated ones.
  static Future<List<String>> _columns(SqlSelect select, String table) async {
    var info = await select('PRAGMA table_xinfo(${_q(table)})', const []);
    // SQLite before 3.26 has no table_xinfo (and no generated columns).
    if (info.isEmpty) {
      info = await select('PRAGMA table_info(${_q(table)})', const []);
    }
    return [
      for (final c in info)
        if (((c['hidden'] as num?) ?? 0) == 0) '${c['name']}',
    ];
  }

  /// Replaces the rows of every table in [tables] (`{name: [row, ...]}`, as
  /// [dump] wrote them); tables not named keep their rows. Call inside a
  /// transaction: a table or column the database doesn't have throws, and
  /// nothing is changed. Returns the rows written per table.
  static Future<Map<String, int>> restore(
    Map<String, Object?> tables,
    Map<String, Object?> sequences, {
    required SqlSelect select,
    required SqlExecute execute,
  }) async {
    final existing = {
      for (final t in await select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
        const [],
      ))
        '${t['name']}',
    };
    final missing = tables.keys.where((t) => !existing.contains(t)).toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'the database has no table ${missing.join(', ')} (it has '
        '${existing.where((t) => !t.startsWith('sqlite_')).join(', ')})',
      );
    }
    // Rows go in table by table: foreign keys are checked at commit.
    await execute('PRAGMA defer_foreign_keys = ON', const []);
    for (final name in tables.keys) {
      await execute('DELETE FROM ${_q(name)}', const []);
    }
    final written = <String, int>{};
    for (final MapEntry(key: name, value: rows) in tables.entries) {
      var n = 0;
      for (final row in (rows as List? ?? const [])) {
        final r = (row as Map).cast<String, Object?>();
        if (r.isEmpty) continue;
        await execute(
          'INSERT INTO ${_q(name)} (${r.keys.map(_q).join(', ')}) '
          'VALUES (${List.filled(r.length, '?').join(', ')})',
          [for (final v in r.values) _decode(v)],
        );
        n++;
      }
      written[name] = n;
    }
    if (existing.contains('sqlite_sequence')) {
      for (final name in tables.keys) {
        await execute('DELETE FROM sqlite_sequence WHERE name = ?', [name]);
        final seq = sequences[name];
        if (seq != null) {
          await execute(
            'INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)',
            [name, seq],
          );
        }
      }
    }
    return written;
  }

  static Object? _encode(Object? v) => switch (v) {
    Uint8List() => {r'$blob': base64.encode(v)},
    List<int>() => {r'$blob': base64.encode(v)},
    BigInt() => v.toInt(),
    double() when !v.isFinite => null,
    _ => v,
  };

  static Object? _decode(Object? v) => v is Map && v[r'$blob'] is String
      ? base64.decode(v[r'$blob'] as String)
      : v;
}
