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

  alias(['target', 'key', 'identifier', 'selector']);
  alias(['rootTarget', 'rootKey', 'rootSelector', 'root']);
  alias(['expected', 'expect', 'expectedValue']);
  alias(['dbName', 'database']);
  return p;
}
