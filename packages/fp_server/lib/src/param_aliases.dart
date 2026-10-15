/// Canonicalizes MCP tool arguments: schemas list one name per argument
/// (`key` for the widget), and the other names agents send for it
/// (`target`, `selector`, `identifier`, `dbName`/`database`) keep working.
Map<String, dynamic> normalizeToolParams(Map<String, dynamic> parameters) {
  final p = Map<String, dynamic>.from(parameters);

  String? firstNonEmpty(List<String> keys) {
    for (final key in keys) {
      final value = p[key];
      if (value == null) continue;
      final text = value.toString();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  void alias(List<String> names) {
    final value = firstNonEmpty(names);
    if (value == null) return;
    for (final name in names) {
      p[name] ??= value;
    }
  }

  _normalized.forEach(alias);
  return p;
}

/// Names that mean the same argument in every tool.
const _normalized = [
  ['target', 'key', 'identifier', 'selector'],
  ['rootTarget', 'rootKey', 'rootSelector', 'root'],
  ['expected', 'expect', 'expectedValue'],
  ['dbName', 'database'],
];

/// Parameters that were snake_case among camelCase ones: the schema lists
/// the new name, the tool and the SDK in the app still read the former one,
/// and a caller may send either.
const _renamed = {
  'clearFirst': 'clear_first',
  'sinceSeconds': 'since_seconds',
  'statusFilter': 'status_filter',
};

/// [args] with each renamed parameter also under its former name, its type
/// kept ([normalizeToolParams] makes strings of what it copies).
Map<String, dynamic> withFormerNames(Map<String, dynamic> args) {
  if (!_renamed.keys.any(args.containsKey)) return args;
  return {
    ...args,
    for (final MapEntry(key: name, value: former) in _renamed.entries)
      if (args.containsKey(name) && !args.containsKey(former))
        former: args[name],
  };
}

/// Old names single tools still read.
const _legacy = [
  ['name', 'provider', 'cubit'],
  ['submitWith', 'submitTarget'],
  ['query', 'search'],
];

/// The arguments in [given] a tool with these schema [properties] doesn't
/// take. A name counts as known when the schema has it or one of its
/// aliases (`target` for `key`).
List<String> unknownToolArguments(
  Iterable<String> given,
  Iterable<String> properties,
) {
  final known = properties.toSet();
  for (final group in [
    ..._normalized,
    ..._legacy,
    for (final e in _renamed.entries) [e.key, e.value],
  ]) {
    if (group.any(known.contains)) known.addAll(group);
  }
  return [
    for (final name in given)
      if (!known.contains(name)) name,
  ];
}
