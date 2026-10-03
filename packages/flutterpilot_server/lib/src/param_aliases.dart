/// Canonicalizes MCP tool arguments so agents can use `target` (preferred)
/// while old names (`key`, `selector`, `identifier`, `dbName`/`database`)
/// still work for at least one release.
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
  for (final group in [..._normalized, ..._legacy]) {
    if (group.any(known.contains)) known.addAll(group);
  }
  return [
    for (final name in given)
      if (!known.contains(name)) name,
  ];
}
