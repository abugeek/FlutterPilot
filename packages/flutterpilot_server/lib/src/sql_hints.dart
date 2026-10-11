/// What exec_sql_query adds to "no such column" / "no such table": the
/// names that do exist. In field sessions 11 of 92 queries failed, nearly
/// all on a guessed column name, each costing another round trip to look
/// the schema up.
library;

/// The name SQLite could not find in a failed query.
typedef SqlMiss = ({bool isTable, String name});

final _miss = RegExp(r'no such (column|table):\s*([\w.]+)');

/// What [error] says is missing, if that is why the query failed.
SqlMiss? sqlMissIn(String error) {
  final m = _miss.firstMatch(error);
  if (m == null) return null;
  // `t.col` and `main.table`: the last part is the name.
  return (isTable: m[1] == 'table', name: m[2]!.split('.').last);
}

final _fromOrJoin = RegExp(
  r'''\b(?:from|join)\s+["`\[]?(\w+)["`\]]?''',
  caseSensitive: false,
);

/// The tables [sql] reads (after FROM and JOIN), in order, at most [max].
List<String> tablesIn(String sql, {int max = 4}) {
  final found = <String>[];
  for (final m in _fromOrJoin.allMatches(sql)) {
    final name = m[1]!;
    if (name.toLowerCase() == 'select' || found.contains(name)) continue;
    found.add(name);
    if (found.length == max) break;
  }
  return found;
}

/// [names] with the ones that look like [missing] first (one contains the
/// other, or they share a word between underscores).
List<String> closestFirst(String missing, List<String> names) {
  final wanted = missing.toLowerCase();
  final words = wanted.split('_').where((w) => w.length > 2).toSet();
  bool close(String name) {
    final n = name.toLowerCase();
    return n.contains(wanted) ||
        wanted.contains(n) ||
        n.split('_').any(words.contains);
  }

  return [...names.where(close), ...names.where((n) => !close(n))];
}

/// The hint line for one table's columns or the database's tables.
/// [names] are cut at [max].
String schemaHint(
  String label,
  String missing,
  List<String> names, {
  int max = 60,
}) {
  final ordered = closestFirst(missing, names);
  final shown = ordered.take(max).join(', ');
  final more = ordered.length > max ? ', … ${ordered.length - max} more' : '';
  return '$label: $shown$more';
}
