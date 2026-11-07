/// The widget constructor call that starts at a creation location, found by
/// matching its parentheses in the source text.
///
/// Skips what can hide a parenthesis: `//` and `/* */` comments, strings in
/// every quote style (raw, triple), and `${…}` inside them.
///
/// [offset] and [end] are string indexes (UTF-16 code units) into the file's
/// text, end exclusive.
typedef ConstructorSpan = ({int offset, int end, List<String> namedArgs});

/// The call starting at 1-based [line]:[column] of [source], or null when no
/// `Name(` / `Name.named(` / `Name<T>(` starts there or its parentheses
/// never close.
ConstructorSpan? constructorSpanAt(String source, int line, int column) {
  var offset = 0;
  for (var l = 1; l < line; l++) {
    final next = source.indexOf('\n', offset);
    if (next < 0) return null;
    offset = next + 1;
  }
  offset += column - 1;
  if (offset < 0 || offset >= source.length) return null;
  final head = RegExp(
    r'(?:const\s+|new\s+)?[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?(?:<[^()]*?>)?\s*\(',
  ).matchAsPrefix(source, offset);
  if (head == null) return null;

  final named = <String>[];
  var depth = 0; // parentheses, brackets and braces of the call
  var i = head.end - 1;
  var argStart = true; // at the start of a top-level argument
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      final eol = source.indexOf('\n', i);
      i = eol < 0 ? source.length : eol;
      continue;
    }
    if (c == '/' && next == '*') {
      final close = source.indexOf('*/', i + 2);
      if (close < 0) return null;
      i = close + 2;
      continue;
    }
    if (c == '"' || c == "'") {
      final after = _skipString(source, i);
      if (after == null) return null;
      i = after;
      argStart = false;
      continue;
    }
    if (c == 'r' &&
        (next == '"' || next == "'") &&
        !_identChar(source, i - 1)) {
      final after = _skipString(source, i + 1, raw: true);
      if (after == null) return null;
      i = after;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      if (depth == 1) argStart = true;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        return (offset: offset, end: i + 1, namedArgs: named);
      }
    } else if (depth == 1 && c == ',') {
      argStart = true;
    } else if (depth == 1 && argStart && _identStart(c)) {
      final m = RegExp(r'([A-Za-z_$][\w$]*)\s*:(?!:)').matchAsPrefix(source, i);
      if (m != null) named.add(m.group(1)!);
      argStart = false;
    } else if (!_isSpace(c)) {
      argStart = false;
    }
    i++;
  }
  return null;
}

/// The index just past the string literal opening at [start] (a quote).
int? _skipString(String s, int start, {bool raw = false}) {
  final q = s[start];
  final triple = s.startsWith(q * 3, start);
  final close = triple ? q * 3 : q;
  var i = start + close.length;
  while (i < s.length) {
    final c = s[i];
    if (!raw && c == r'\') {
      i += 2;
      continue;
    }
    if (!triple && c == '\n') return null;
    if (s.startsWith(close, i)) return i + close.length;
    if (!raw && c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
      // Interpolation: code until the matching brace, strings and all.
      var depth = 1;
      i += 2;
      while (i < s.length && depth > 0) {
        final d = s[i];
        if (d == '"' || d == "'") {
          final after = _skipString(s, i);
          if (after == null) return null;
          i = after;
          continue;
        }
        if (d == '{') depth++;
        if (d == '}') depth--;
        i++;
      }
      continue;
    }
    i++;
  }
  return null;
}

bool _identStart(String c) => RegExp(r'[A-Za-z_$]').hasMatch(c);
bool _identChar(String s, int i) => i >= 0 && RegExp(r'[\w$]').hasMatch(s[i]);
bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';
