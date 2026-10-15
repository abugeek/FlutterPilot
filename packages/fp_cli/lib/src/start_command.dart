// Keep in step with packages/fp_server/lib/src/start_command.dart
// (the CLI doesn't depend on the server).
/// Starting a program the way a shell would, so `flutter` is found and run:
/// on Windows it is `flutter.bat`, and `Process.start('flutter', …)` fails
/// with "The system cannot find the file specified" (field test #327).
library;

import 'dart:io';

/// A program ready for `Process.start`.
class StartCommand {
  const StartCommand(
    this.executable,
    this.arguments, {
    required this.runInShell,
  });

  /// The program: a full path on Windows once it was found on `PATH`.
  final String executable;

  final List<String> arguments;

  /// Whether Windows has to start it through the command interpreter, because
  /// `CreateProcess` cannot run a `.bat`/`.cmd` itself.
  final bool runInShell;

  @override
  String toString() => [executable, ...arguments].join(' ');
}

/// The extensions Windows tries for a bare program name, when `PATHEXT` is
/// not set.
const _defaultPathExt = '.COM;.EXE;.BAT;.CMD';

/// Whether [path] is a batch file, which only the command interpreter runs.
bool isBatchFile(String path) {
  final extension = _extension(path);
  return extension == '.bat' || extension == '.cmd';
}

/// [command] ready for `Process.start`: on Windows the program is looked up
/// on `PATH` with `PATHEXT` (`flutter` finds `flutter.bat`) and a batch file
/// runs through the shell. Everywhere else [command] is left as it is.
///
/// The arguments reach the shell as they are, and `cmd.exe` re-parses the
/// line `flutter.bat` forwards with `%*`: an argument with no space in it
/// (Dart quotes only those) loses a bare `&`, `|`, `<`, `>` or `^`, and a
/// `%NAME%` that names a variable is expanded (field tests #327, #343).
/// Spaces, `;`, `=`, `,` and parentheses come through, and `flutter run`
/// typed into cmd has the same limits.
StartCommand startCommandFor(
  List<String> command, {
  String? workingDirectory,
  String? path,
  String? pathExt,
  bool? isWindows,
  bool Function(String)? exists,
}) {
  if (command.isEmpty) {
    throw ArgumentError.value(command, 'command', 'needs a program to start');
  }
  final arguments = command.sublist(1);
  if (!(isWindows ?? Platform.isWindows)) {
    return StartCommand(command.first, arguments, runInShell: false);
  }
  final resolved = resolveExecutableOnWindows(
    command.first,
    path: path ?? Platform.environment['PATH'] ?? '',
    pathExt: pathExt ?? Platform.environment['PATHEXT'] ?? _defaultPathExt,
    workingDirectory: workingDirectory ?? Directory.current.path,
    exists: exists ?? _fileExists,
  );
  final executable = resolved ?? command.first;
  return StartCommand(
    executable,
    arguments,
    runInShell: isBatchFile(executable),
  );
}

/// `Process.run` of [command], resolved by [startCommandFor].
Future<ProcessResult> runProgram(
  List<String> command, {
  String? workingDirectory,
}) {
  final start = startCommandFor(command, workingDirectory: workingDirectory);
  return Process.run(
    start.executable,
    start.arguments,
    workingDirectory: workingDirectory,
    runInShell: start.runInShell,
  );
}

/// `Process.start` of [command], resolved by [startCommandFor].
Future<Process> startProgram(
  List<String> command, {
  String? workingDirectory,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  final start = startCommandFor(command, workingDirectory: workingDirectory);
  return Process.start(
    start.executable,
    start.arguments,
    workingDirectory: workingDirectory,
    runInShell: start.runInShell,
    mode: mode,
  );
}

/// The file Windows runs for [name], the way the command interpreter finds
/// it: a name with a directory part is resolved against [workingDirectory], a
/// bare one against [path]; `PATHEXT` extensions are tried first, so
/// `flutter` finds `flutter.bat` and not the POSIX `flutter` script Flutter
/// ships beside it. Null when nothing matches.
String? resolveExecutableOnWindows(
  String name, {
  required String path,
  required String pathExt,
  required String workingDirectory,
  required bool Function(String) exists,
}) {
  final extensions = [
    for (final extension in pathExt.split(';'))
      if (extension.trim().isNotEmpty)
        extension.trim().startsWith('.')
            ? extension.trim()
            : '.${extension.trim()}',
  ];
  final hasDirectory =
      name.contains('/') || name.contains(r'\') || name.contains(':');
  final bases = <String>[
    if (hasDirectory)
      _windowsPath(
        _isAbsoluteOnWindows(name) ? name : '$workingDirectory\\$name',
      )
    else ...[
      // The command interpreter looks in the current directory first, then
      // walks PATH.
      _windowsPath('$workingDirectory\\$name'),
      for (final folder in path.split(';'))
        if (folder.isNotEmpty) _windowsPath('$folder\\$name'),
    ],
  ];
  // A name without an extension may also be an executable itself (a `.cmd`
  // piped through git bash, a real binary): those are tried last, so a
  // `PATHEXT` match in any `PATH` folder wins over an extensionless one.
  final extended = <String>[];
  final bare = <String>[];
  for (final base in bases) {
    if (_extension(base).isEmpty) {
      extended.addAll(extensions.map((e) => '$base$e'));
      bare.add(base);
    } else {
      extended.add(base);
    }
  }
  for (final candidate in [...extended, ...bare]) {
    if (exists(candidate)) return candidate;
  }
  return null;
}

bool _fileExists(String path) => File(path).existsSync();

String _windowsPath(String path) => path.replaceAll('/', r'\');

bool _isAbsoluteOnWindows(String path) =>
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
    path.startsWith(r'\\') ||
    path.startsWith('/');

String _extension(String path) {
  final name = path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}
