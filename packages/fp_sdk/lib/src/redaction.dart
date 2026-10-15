/// Redaction shared by every place FlutterPilot hands app data to an agent
/// (logs, URLs, network logs): secrets an app prints or sends stay out of
/// tool results (security review, ROADMAP §8).
class Redaction {
  static const mask = '<redacted>';

  /// Names whose values are secrets: `password=…`, `"api_key": "…"`,
  /// `?token=…`.
  static final RegExp sensitiveName = RegExp(
    // Not "author", "passenger", "sessionCount".
    r'(passw(or)?d|passcode|passphrase|pwd|secret|token|api[_-]?key|'
    r'access[_-]?key|private[_-]?key|client[_-]?secret|authorization|'
    r'auth(?!or)|cookie|session[_-]?id|credential|jwt)',
    caseSensitive: false,
  );

  static final _pair = RegExp(
    // Not `https://`: a scheme is not a name.
    r'''(["']?)([A-Za-z0-9_.-]*?)\1(\s*[:=]\s*)(?!//)(["']?)([^\s&,;"'}\])]+)''',
  );
  static final _scheme = RegExp(
    r'\b(Bearer|Basic|Token)\s+[A-Za-z0-9._~+/=-]{6,}',
    caseSensitive: false,
  );
  static final _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]+',
  );

  /// [text] with credential values masked: `Bearer <token>`, JWTs, and the
  /// value of every `name=value` / `name: value` whose name looks secret
  /// (query strings included).
  static String text(String text) => text
      .replaceAllMapped(_scheme, (m) => '${m[1]} $mask')
      .replaceAllMapped(_jwt, (_) => mask)
      .replaceAllMapped(_pair, (m) {
        final name = m[2]!;
        if (name.isEmpty || !sensitiveName.hasMatch(name)) return m[0]!;
        return '${m[1]}$name${m[1]}${m[3]}${m[4]}$mask';
      });
}

/// Read-only SQL for `exec_sql_query`: a statement that reads, and PRAGMAs
/// that only report. A prefix check is not enough: `WITH x AS (SELECT 1)
/// DELETE FROM t` starts with WITH, and `PRAGMA main.journal_mode=…` or
/// `PRAGMA user_version=5` write.
bool isReadOnlySqlStatement(String sql) {
  var s = sql
      .replaceAll(RegExp(r'--[^\n]*'), ' ')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      // String literals and quoted names may say anything.
      .replaceAll(RegExp(r"'(?:[^']|'')*'"), "''")
      .replaceAll(RegExp(r'"(?:[^"]|"")*"'), '""')
      .replaceAll(RegExp(r'`[^`]*`'), '""')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '""')
      .trim();
  if (s.endsWith(';')) s = s.substring(0, s.length - 1).trim();
  if (s.isEmpty || s.contains(';')) return false;
  final upper = s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  if (upper.startsWith('PRAGMA ')) {
    if (upper.contains('=')) return false;
    final name = RegExp(
      r'^PRAGMA (?:\w+\.)?(\w+)',
    ).firstMatch(upper)?.group(1)?.toLowerCase();
    return name != null && _readPragmas.contains(name);
  }
  if (!RegExp(r'^(SELECT|WITH|EXPLAIN|VALUES)\b').hasMatch(upper)) {
    return false;
  }
  // No writing statement anywhere (REPLACE( is the string function).
  return !RegExp(
    r'\b(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|ATTACH|DETACH|VACUUM|'
    r'REINDEX|ANALYZE|SAVEPOINT|RELEASE|BEGIN|COMMIT|ROLLBACK|INTO)\b|'
    r'\bREPLACE\b(?!\s*\()',
  ).hasMatch(upper);
}

/// PRAGMAs that only report (in their no-argument or `(table)` form).
const _readPragmas = {
  'table_info',
  'table_xinfo',
  'table_list',
  'index_list',
  'index_info',
  'index_xinfo',
  'foreign_key_list',
  'foreign_key_check',
  'database_list',
  'collation_list',
  'function_list',
  'module_list',
  'pragma_list',
  'compile_options',
  'user_version',
  'schema_version',
  'application_id',
  'page_count',
  'page_size',
  'freelist_count',
  'journal_mode',
  'encoding',
  'integrity_check',
  'quick_check',
  'foreign_keys',
  'data_version',
};
