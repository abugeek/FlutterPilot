import 'dart:io';

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
  final lineStart = offset;
  offset += column - 1;
  if (offset < 0 || offset >= source.length) return null;

  // If column == 1, skip leading whitespace on the line
  if (column == 1) {
    while (offset < source.length &&
        (source[offset] == ' ' || source[offset] == '\t')) {
      offset++;
    }
    // If the line starts with 'return ', 'yield ', a declaration, or a named argument,
    // advance past it to the constructor call.
    final prefixMatch = RegExp(
      r'(?:(?:return|yield)\s+|(?:(?:final|const|var)\s+)?[A-Za-z_$][\w$]*\s*[:=]\s*)',
    ).matchAsPrefix(source, offset);
    if (prefixMatch != null) {
      offset = prefixMatch.end;
    }
  } else {
    // If offset is inside an identifier, rewind to its start
    while (offset > lineStart && _identChar(source, offset - 1)) {
      offset--;
    }
  }

  // If offset is preceded by a dot (e.g. named constructor or library prefix),
  // rewind across the dot and the preceding identifier / type arguments.
  while (offset > lineStart && (source[offset - 1] == '.' || (offset >= lineStart + 1 && source[offset] == '.'))) {
    if (source[offset] == '.') {
      offset--;
    }
    var prev = offset;
    if (prev > lineStart && source[prev - 1] == '.') prev--;
    while (prev > lineStart && _isSpace(source[prev - 1])) {
      prev--;
    }
    // Skip type arguments: e.g. List<T>.filled
    if (prev > lineStart && source[prev - 1] == '>') {
      var depth = 1;
      prev--;
      while (prev > lineStart && depth > 0) {
        if (source[prev - 1] == '>') depth++;
        if (source[prev - 1] == '<') depth--;
        prev--;
      }
    }
    if (prev > lineStart && _identChar(source, prev - 1)) {
      while (prev > lineStart && _identChar(source, prev - 1)) {
        prev--;
      }
      offset = prev;
    } else {
      break;
    }
  }

  // If preceded by 'const ' or 'new ', include it
  final before = source.substring(lineStart, offset);
  if (before.endsWith('const ')) {
    offset -= 6;
  } else if (before.endsWith('new ')) {
    offset -= 4;
  }

  final head = RegExp(
    r'(?:const\s+|new\s+)?(?:[A-Za-z_$][\w$]*\.)*[A-Za-z_$][\w$]*(?:<[^()]*?>)?(?:\.[A-Za-z_$][\w$]*)?(?:<[^()]*?>)?\s*\(',
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

/// Finds the innermost constructor call that strictly encloses [targetOffset]..[targetEnd].
ConstructorSpan? enclosingConstructorSpan(
  String source,
  int targetOffset,
  int targetEnd, {
  int? hintLine,
}) {
  var currentLine = hintLine ?? 1;
  if (hintLine == null) {
    for (var j = 0; j < targetOffset && j < source.length; j++) {
      if (source[j] == '\n') currentLine++;
    }
  }

  // Walk backwards from targetOffset to find the closest constructor call
  // that encloses targetOffset..targetEnd.
  var i = targetOffset - 1;
  while (i >= 0) {
    if (source[i] == '\n') {
      currentLine--;
    } else if (source[i] == '(') {
      final lineStart = source.lastIndexOf('\n', i) + 1;
      final col = (i - lineStart) + 1;
      final span = constructorSpanAt(source, currentLine, col);
      if (span != null && span.offset < targetOffset && span.end >= targetEnd) {
        return span;
      }
    }
    i--;
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

/// Result of finding a widget constructor call statically in Dart source files.
typedef AstMatchResult = ({
  String file,
  int line,
  int column,
  String? type,
  ConstructorSpan span,
  String snippet,
});

/// Searches [source] for a widget constructor containing [targetKey].
AstMatchResult? findWidgetConstructorInSource(
  String source,
  String targetKey, {
  String filePath = '',
}) {
  final escaped = RegExp.escape(targetKey);
  const q = '["\']';
  // Match key: ...Key('targetKey') / Key("targetKey") / ValueKey('targetKey') / ValueKey("targetKey")
  final keyPattern = RegExp(
    r'\bkey\s*:\s*(?:const\s+)?(?:[A-Za-z_$][\w$]*\.)?(?:Key|ValueKey)(?:<[^>]*>)?\s*\(\s*'
    '$q$escaped$q'
    r'\s*\)',
  );
  var match = keyPattern.firstMatch(source);
  if (match == null) {
    // Match raw Key('targetKey') or ValueKey('targetKey')
    final rawKeyPattern = RegExp(
      r'(?:const\s+)?(?:[A-Za-z_$][\w$]*\.)?(?:Key|ValueKey)(?:<[^>]*>)?\s*\(\s*'
      '$q$escaped$q'
      r'\s*\)',
    );
    match = rawKeyPattern.firstMatch(source);
  }
  if (match == null) {
    // Match Text('targetKey')
    final textPattern = RegExp(
      r'\bText\s*\(\s*'
      '$q$escaped$q'
      r'\s*[,)]',
    );
    match = textPattern.firstMatch(source);
  }
  if (match == null) return null;

  final targetOffset = match.start;
  final targetEnd = match.end;

  // Compute 1-based line of the match
  var matchLine = 1;
  var lastLineStart = 0;
  for (var i = 0; i < targetOffset; i++) {
    if (source[i] == '\n') {
      matchLine++;
      lastLineStart = i + 1;
    }
  }

  // If the match is a Text widget itself and has no enclosing constructor we care about,
  // or if we find an enclosing constructor (like a button or tile) that wraps this Text/key
  final enclosing = enclosingConstructorSpan(
    source,
    targetOffset,
    targetEnd,
    hintLine: matchLine,
  );

  final span = enclosing ??
      (source.substring(targetOffset).startsWith('Text')
          ? constructorSpanAt(
              source,
              matchLine,
              (targetOffset - lastLineStart) + 1,
            )
          : null);
  if (span == null) return null;

  var spanLine = 1;
  var spanLineStart = 0;
  for (var i = 0; i < span.offset; i++) {
    if (source[i] == '\n') {
      spanLine++;
      spanLineStart = i + 1;
    }
  }
  final spanCol = (span.offset - spanLineStart) + 1;

  final headMatch = RegExp(
    r'(?:const\s+|new\s+)?([A-Za-z_$][\w$]*)(?:\.[A-Za-z_$][\w$]*)?\s*\(',
  ).matchAsPrefix(source, span.offset);
  final type = headMatch?.group(1);

  return (
    file: filePath,
    line: spanLine,
    column: spanCol,
    type: type,
    span: span,
    snippet: source.substring(span.offset, span.end),
  );
}

/// Recursively scans Dart files in [dir] for a widget constructor matching [targetKey].
Future<AstMatchResult?> findWidgetConstructorInProject(
  Directory dir,
  String targetKey,
) async {
  if (!dir.existsSync()) return null;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart') ||
        entity.path.endsWith('.freezed.dart')) {
      continue;
    }
    try {
      final content = await entity.readAsString();
      if (!content.contains(targetKey)) continue;
      final result = findWidgetConstructorInSource(
        content,
        targetKey,
        filePath: entity.path,
      );
      if (result != null) return result;
    } catch (_) {}
  }
  return null;
}
