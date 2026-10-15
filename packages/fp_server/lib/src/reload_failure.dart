import 'dart:io';

/// What hot_reload / hot restart tells the agent when flutter_tools fails:
/// the error without flutter_tools' own stack frames, and a hint for the
/// cause that can be told from the message.
///
/// [compileErrors] are the compiler's or analyzer's own lines, when they
/// could be found: flutter_tools prints them in its terminal and answers
/// the call with an empty message.
String reloadFailureText(
  String service,
  String details, {
  String compileErrors = '',
}) {
  final message = details
      .split('\n')
      .where((line) => !_toolFrame.hasMatch(line))
      .where((line) => line.trim() != '<asynchronous suspension>')
      .join('\n')
      .trim();
  if (compileErrors.isNotEmpty) {
    return '$service failed: the code does not compile.\n$compileErrors\n'
        'Fix this and call hot_reload again; the app is still running the '
        'code from before.';
  }
  return '$service failed: $message\n${_hintFor(message)}';
}

final _compilerError = RegExp(r'^\S+\.dart:\d+:\d+: Error: ');

/// The compiler errors in [output] (what `flutter run` printed during a
/// reload): each `file:line:col: Error: …` with the source lines under it.
/// At most [max] errors and [maxChars] characters.
String compileErrorsIn(String output, {int max = 8, int maxChars = 2000}) {
  final blocks = <List<String>>[];
  var inError = false;
  for (final line in output.split('\n')) {
    if (_compilerError.hasMatch(line)) {
      blocks.add([line.trimRight()]);
      inError = true;
    } else if (inError && line.startsWith(' ') && line.trim().isNotEmpty) {
      blocks.last.add(line.trimRight());
    } else {
      inError = false;
    }
  }
  // The same error is printed again on a retry.
  final unique = {for (final b in blocks) b.join('\n')}.toList();
  var text = unique.take(max).join('\n');
  if (unique.length > max) text += '\n… ${unique.length - max} more errors';
  return text.length > maxChars ? '${text.substring(0, maxChars)}…' : text;
}

/// The errors in `dart analyze --format=machine` [output], as
/// `path:line:col: message`, paths relative to [root] with forward slashes
/// (the analyzer prints them in the platform's own style, field test #341).
String analyzerErrorsIn(String output, String root, {int max = 8}) {
  final errors = <String>[];
  for (final line in output.split('\n')) {
    final parts = line.split('|');
    if (parts.length < 8 || parts[0] != 'ERROR') continue;
    var path = parts[3].replaceAll(r'\', '/');
    final prefix = '${root.replaceAll(r'\', '/')}/';
    if (path.startsWith(prefix)) path = path.substring(prefix.length);
    errors.add('$path:${parts[4]}:${parts[5]}: ${parts.sublist(7).join('|')}');
  }
  final shown = errors.take(max).join('\n');
  return errors.length > max
      ? '$shown\n… ${errors.length - max} more errors'
      : shown;
}

/// The folder with the pubspec.yaml above [file], or null. [file] may come
/// from a `file:` URI and hold either separator (a Windows path walks up on
/// `\`, field test #342).
String? projectRootOfFile(String file, {bool Function(String)? exists}) {
  var dir = file.replaceAll(r'\', '/');
  while (true) {
    final cut = dir.lastIndexOf('/');
    if (cut <= 0) return null;
    dir = dir.substring(0, cut);
    if ((exists ?? _fileExists)('$dir/pubspec.yaml')) return dir;
  }
}

bool _fileExists(String path) => File(path).existsSync();

/// Dart files under [root]'s source folders changed after [since], newest
/// first, at most [max]: what a failed reload was about.
List<String> dartFilesChangedSince(
  String root,
  DateTime since, {
  int max = 20,
}) {
  final found = <({String path, DateTime at})>[];
  for (final name in const ['lib', 'tool', 'bin', 'test_driver']) {
    final dir = Directory('$root/$name');
    if (!dir.existsSync()) continue;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final at = entity.lastModifiedSync();
        if (at.isAfter(since)) found.add((path: entity.path, at: at));
      }
    } catch (_) {}
  }
  found.sort((a, b) => b.at.compareTo(a.at));
  return [for (final f in found.take(max)) f.path];
}

/// A frame of flutter_tools' stack trace: `#12  HotRunner._updateDevFS (…)`.
final _toolFrame = RegExp(r'^\s*#\d+\s');

/// Whether [details] names no cause of its own, so the compiler's errors
/// are worth looking for.
bool mayBeCompileError(String details) =>
    _hintFor(details).startsWith('HINT: usually a compile error');

String _hintFor(String message) {
  // flutter_tools copies the compiled kernel straight into the app's temp
  // directory. For a sandboxed macOS app that is inside the app's container,
  // which macOS keeps other processes out of unless the one that ran
  // `flutter run` was allowed to manage apps.
  if (message.contains('failed to create file') &&
      message.contains('/Library/Containers/')) {
    return 'HINT: not a compile error. macOS stopped the process that ran '
        '`flutter run` from writing into this sandboxed app\'s container. '
        'Allow that program (the terminal, IDE or agent app) under System '
        'Settings > Privacy & Security > App Management (or Full Disk '
        'Access), then start `flutter run` again. Until then, stop the app '
        'and launch it again after each edit.';
  }
  // An asset the build lists is gone (field test: SVGs deleted while the app
  // ran); the agent took "compile error" at its word, then rebuilt the app.
  if (message.contains('failed to copy') ||
      message.contains('Unable to load asset')) {
    return 'HINT: not a compile error. An asset the build expects is '
        'missing (deleted, moved or renamed). Restore the file or fix the '
        'assets: list in pubspec.yaml, then call hot_reload again; if it '
        'fails the same way, stop the app and run it again.';
  }
  return 'HINT: usually a compile error — run `dart analyze` on the edited '
      'files, fix, and retry. Some changes (main(), static initializers) '
      'need hot_reload(restart: true).';
}
