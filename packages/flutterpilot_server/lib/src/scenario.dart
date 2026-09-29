import 'dart:convert';

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
    this.riverpod = const {},
    this.bloc = const {},
  });

  final String? description;
  final String? route;

  /// SharedPreferences, all of them: loading replaces what is stored.
  /// Null leaves the app's preferences alone.
  final Map<String, Object?>? prefs;
  final List<Map<String, Object?>> mocks;
  final Map<String, Object?> riverpod;
  final Map<String, Object?> bloc;

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
      riverpod: map((j['state'] as Map?)?['riverpod']),
      bloc: map((j['state'] as Map?)?['bloc']),
    );
  }

  Map<String, Object?> toJson() => {
    'description': ?description,
    'route': ?route,
    'prefs': ?prefs,
    if (mocks.isNotEmpty) 'mocks': mocks,
    if (riverpod.isNotEmpty || bloc.isNotEmpty)
      'state': {
        if (riverpod.isNotEmpty) 'riverpod': riverpod,
        if (bloc.isNotEmpty) 'bloc': bloc,
      },
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// One line: what loading it sets.
  String get summary => [
    if (route != null) 'route $route',
    if (prefs != null) '${prefs!.length} preference(s)',
    if (mocks.isNotEmpty) '${mocks.length} mocked response(s)',
    if (riverpod.isNotEmpty || bloc.isNotEmpty)
      '${riverpod.length + bloc.length} state value(s)',
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

/// States a plugin reported (`name: {value, type}`) that set_state can put
/// back: bool, numbers and strings. Plugins report values as `toString()`,
/// so lists, maps and classes can't be read back faithfully.
({Map<String, Object?> kept, List<String> skipped}) restorableStates(
  Map<String, dynamic> states,
  String valueKey,
) {
  final kept = <String, Object?>{};
  final skipped = <String>[];
  for (final MapEntry(key: name, value: entry) in states.entries) {
    if (entry is! Map) continue;
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
  return (kept: kept, skipped: skipped);
}
