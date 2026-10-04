import 'dart:convert';

import 'redaction.dart';

/// A named app state to start from (ROADMAP §7): the route, stored
/// preferences, mocked responses and simple provider/bloc values. Saved as
/// `flutterpilot/scenarios/<name>.json` in the app, to check in and edit;
/// loading it hot-restarts the app into that state.
class Scenario {
  Scenario({
    this.description,
    this.route,
    this.prefs,
    this.mocks = const [],
    this.channelMocks = const [],
    this.riverpod = const {},
    this.bloc = const {},
    this.databases = const {},
    this.hive = const {},
  });

  final String? description;
  final String? route;

  /// SharedPreferences, all of them: loading replaces what is stored.
  /// Null leaves the app's preferences alone.
  final Map<String, Object?>? prefs;
  final List<Map<String, Object?>> mocks;

  /// Platform-channel mocks (mock_platform_channel): `{channel, method,
  /// result | errorCode}`, in place before the app's first plugin call.
  final List<Map<String, Object?>> channelMocks;
  final Map<String, Object?> riverpod;
  final Map<String, Object?> bloc;

  /// Local SQLite databases by registered name: `{engine: "drift" |
  /// "sqflite", tables: {name: [row, ...]}, sequences: {name: seq}}`.
  /// Loading replaces the rows of the tables named; others keep theirs.
  final Map<String, Object?> databases;

  /// Hive boxes by name, as `[[key, value], ...]`: loading empties and
  /// fills each one named.
  final Map<String, Object?> hive;

  /// Whether loading writes to the app's stored data.
  bool get replacesStoredData =>
      prefs != null || databases.isNotEmpty || hive.isNotEmpty;

  /// Tables of every database, and their rows.
  ({int tables, int rows}) get _databaseSize {
    var tables = 0, rows = 0;
    for (final db in databases.values) {
      final t = db is Map ? db['tables'] : null;
      if (t is! Map) continue;
      tables += t.length;
      for (final r in t.values) {
        if (r is List) rows += r.length;
      }
    }
    return (tables: tables, rows: rows);
  }

  factory Scenario.fromJson(Map<String, dynamic> j) {
    Map<String, Object?> map(Object? v) =>
        v is Map ? v.cast<String, Object?>() : const {};
    return Scenario(
      description: j['description'] as String?,
      route: j['route'] as String?,
      prefs: j['prefs'] is Map ? map(j['prefs']) : null,
      mocks: [
        for (final m in (j['mocks'] as List? ?? const []))
          if (m is Map && m['urlPattern'] != null) m.cast<String, Object?>(),
      ],
      channelMocks: [
        for (final m in (j['channelMocks'] as List? ?? const []))
          if (m is Map && m['channel'] != null) m.cast<String, Object?>(),
      ],
      riverpod: map((j['state'] as Map?)?['riverpod']),
      bloc: map((j['state'] as Map?)?['bloc']),
      databases: map(j['databases']),
      hive: map(j['hive']),
    );
  }

  Map<String, Object?> toJson() => {
    'description': ?description,
    'route': ?route,
    'prefs': ?prefs,
    if (mocks.isNotEmpty) 'mocks': mocks,
    if (channelMocks.isNotEmpty) 'channelMocks': channelMocks,
    if (riverpod.isNotEmpty || bloc.isNotEmpty)
      'state': {
        if (riverpod.isNotEmpty) 'riverpod': riverpod,
        if (bloc.isNotEmpty) 'bloc': bloc,
      },
    if (databases.isNotEmpty) 'databases': databases,
    if (hive.isNotEmpty) 'hive': hive,
  };

  /// Indented, with each database row and Hive entry on one line: a table
  /// of 50 rows stays 50 lines to read, edit and diff.
  String encode() {
    final lines = <String, String>{};
    var n = 0;
    Object? oneLine(Object? v) {
      final token = '@@row${n++}@@';
      lines['"$token"'] = jsonEncode(v);
      return token;
    }

    final json = toJson();
    if (databases.isNotEmpty) {
      json['databases'] = {
        for (final MapEntry(key: name, value: db) in databases.entries)
          name: db is! Map
              ? db
              : {
                  for (final MapEntry(:key, :value) in db.entries)
                    key: key == 'tables' && value is Map
                        ? {
                            for (final t in value.entries)
                              t.key: t.value is List
                                  ? (t.value as List).map(oneLine).toList()
                                  : t.value,
                          }
                        : value,
                },
      };
    }
    if (hive.isNotEmpty) {
      json['hive'] = {
        for (final MapEntry(key: name, value: entries) in hive.entries)
          name: entries is List ? entries.map(oneLine).toList() : entries,
      };
    }
    final text = const JsonEncoder.withIndent('  ').convert(json);
    return '${text.replaceAllMapped(RegExp('"@@row\\d+@@"'), (m) => lines[m[0]]!)}\n';
  }

  /// One line: what loading it sets.
  String get summary => [
    if (route != null) 'route $route',
    if (prefs != null) '${prefs!.length} preference(s)',
    if (mocks.isNotEmpty) '${mocks.length} mocked response(s)',
    if (channelMocks.isNotEmpty)
      '${channelMocks.length} platform-channel mock(s)',
    if (riverpod.isNotEmpty || bloc.isNotEmpty)
      '${riverpod.length + bloc.length} state value(s)',
    if (databases.isNotEmpty)
      '${_databaseSize.rows} database row(s) in ${_databaseSize.tables} '
          'table(s)',
    if (hive.isNotEmpty) '${hive.length} Hive box(es)',
  ].join(', ');
}

/// The `type` the prefs plugin's setter takes, and the value as it wants
/// it (a string); null for values it can't store.
({String type, String value})? prefForSetter(Object? v) => switch (v) {
  bool() => (type: 'bool', value: '$v'),
  int() => (type: 'int', value: '$v'),
  double() => (type: 'double', value: '$v'),
  String() => (type: 'string', value: v),
  List() when v.every((e) => e is String) => (
    type: 'stringList',
    value: jsonEncode(v),
  ),
  _ => null,
};

/// The tables of a database dump that go in a scenario file: not the ones
/// with a column named like a credential (`token`, `password`) — files are
/// checked in, and a row is no use with that column blanked.
({Map<String, Object?> kept, List<String> secret}) scenarioTables(
  Map<String, Object?> tables,
) {
  final kept = <String, Object?>{};
  final secret = <String>[];
  for (final MapEntry(key: name, value: rows) in tables.entries) {
    final first = rows is List && rows.isNotEmpty ? rows.first : null;
    if (first is Map &&
        first.keys.any((c) => Redaction.sensitiveName.hasMatch('$c'))) {
      secret.add(name);
    } else {
      kept[name] = rows;
    }
  }
  return (kept: kept, secret: secret);
}

/// States a plugin reported (`name: {value, type}`) that set_state can put
/// back: bool, numbers and strings. Plugins report values as `toString()`,
/// so lists, maps and classes can't be read back faithfully.
({Map<String, Object?> kept, List<String> skipped, List<String> secret})
restorableStates(Map<String, dynamic> states, String valueKey) {
  final kept = <String, Object?>{};
  final skipped = <String>[];
  // Scenario files are checked in: never a credential.
  final secret = <String>[];
  for (final MapEntry(key: name, value: entry) in states.entries) {
    if (entry is! Map) continue;
    if (Redaction.sensitiveName.hasMatch(name)) {
      secret.add(name);
      continue;
    }
    final raw = '${entry[valueKey]}';
    final Object? value = switch ('${entry['type']}') {
      'bool' => raw == 'true',
      'int' => int.tryParse(raw),
      'double' => double.tryParse(raw),
      'String' => raw,
      _ => null,
    };
    if (value == null) {
      // Services (`Instance of 'Api'`) and requests in flight are not
      // state anyone restores: only mention real values left out.
      final type = '${entry['type']}';
      if (!raw.startsWith('Instance of ') &&
          !type.startsWith('Async') &&
          !type.startsWith('Future')) {
        skipped.add('$name ($type)');
      }
    } else {
      kept[name] = value;
    }
  }
  return (kept: kept, skipped: skipped, secret: secret);
}
