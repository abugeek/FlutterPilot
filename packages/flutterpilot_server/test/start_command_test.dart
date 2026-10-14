import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/src/app_launcher.dart';
import 'package:flutterpilot_server/src/start_command.dart';
import 'package:test/test.dart';

void main() {
  group('resolveExecutableOnWindows', () {
    // The files of a Windows Flutter machine, so no real PATH is needed. The
    // names are the ones on disk (lower case) and `PATHEXT` is the real one
    // (upper case), which is why a resolved name keeps the appended case.
    late Set<String> files;
    const path = r'C:\WINDOWS;C:\flutter\bin';
    const pathExt = '.COM;.EXE;.BAT;.CMD';

    setUp(() {
      files = {
        r'C:\flutter\bin\flutter',
        r'C:\flutter\bin\flutter.bat',
        r'C:\flutter\bin\dart.bat',
        r'C:\WINDOWS\where.exe',
        r'C:\app\scripts\run.bat',
        r'C:\app\tools\local.bat',
      };
    });

    /// Windows matches a file name whatever its case, and the `.` segments of
    /// a path resolve before the file system is touched.
    bool exists(String path) {
      final normalized = path
          .replaceAll('/', r'\')
          .replaceAll(r'\.\', r'\')
          .toLowerCase();
      return files.any(
        (file) => file.replaceAll('/', r'\').toLowerCase() == normalized,
      );
    }

    String? resolve(String name, {String workingDirectory = r'C:\app'}) =>
        resolveExecutableOnWindows(
          name,
          path: path,
          pathExt: pathExt,
          workingDirectory: workingDirectory,
          exists: exists,
        );

    test('a bare name finds the .bat, not the extensionless script', () {
      // Flutter ships a POSIX `flutter` next to `flutter.bat`; the command
      // interpreter runs the .bat (field test #327).
      expect(resolve('flutter'), r'C:\flutter\bin\flutter.BAT');
    });

    test('PATHEXT decides between candidates, in its order', () {
      expect(resolve('where'), r'C:\WINDOWS\where.EXE');
      expect(resolve('dart'), r'C:\flutter\bin\dart.BAT');
    });

    test('the current directory is searched before PATH', () {
      expect(
        resolve(r'local.bat', workingDirectory: r'C:\app\tools'),
        r'C:\app\tools\local.bat',
      );
      expect(resolve('local.bat'), isNull);
    });

    test('a name with a directory part is not searched on PATH', () {
      expect(resolve(r'.\scripts\run.bat'), r'C:\app\.\scripts\run.bat');
      expect(resolve(r'C:\app\scripts\run.bat'), r'C:\app\scripts\run.bat');
      expect(resolve(r'.\scripts\missing.bat'), isNull);
      expect(resolve('scripts'), isNull);
    });

    test('an absolute path with an extension is taken as it is', () {
      expect(
        resolve(r'C:\flutter\bin\flutter.bat'),
        r'C:\flutter\bin\flutter.bat',
      );
    });

    test('nothing matches: null, so the caller can name what it tried', () {
      expect(resolve('adb'), isNull);
    });
  });

  group('startCommandFor', () {
    test('on Windows flutter is resolved and run through the shell', () {
      final start = startCommandFor(
        ['flutter', 'run', '-d', 'windows'],
        isWindows: true,
        path: r'C:\flutter\bin',
        pathExt: '.EXE;.BAT',
        workingDirectory: r'C:\app',
        exists: (path) => sameFile(path, r'C:\flutter\bin\flutter.bat'),
      );
      expect(start.executable, r'C:\flutter\bin\flutter.BAT');
      expect(start.arguments, ['run', '-d', 'windows']);
      expect(start.runInShell, isTrue);
    });

    test('a bare name resolved to a .exe does not go through the shell', () {
      final start = startCommandFor(
        ['tool', '--flag'],
        isWindows: true,
        path: r'C:\tools',
        pathExt: '.EXE',
        workingDirectory: r'C:\app',
        exists: (path) => sameFile(path, r'C:\tools\tool.exe'),
      );
      expect(start.executable, r'C:\tools\tool.EXE');
      expect(start.arguments, ['--flag']);
      expect(start.runInShell, isFalse);
    });

    test('a command that is nowhere keeps its name and its error', () {
      final start = startCommandFor(
        ['nope', 'x'],
        isWindows: true,
        path: '',
        pathExt: '.EXE',
        workingDirectory: r'C:\app',
        exists: (_) => false,
      );
      expect(start.executable, 'nope');
      expect(start.runInShell, isFalse);
    });

    test('another OS leaves the command alone', () {
      final start = startCommandFor([
        './scripts/run.sh',
        '-t',
        'tool/main.dart',
      ], isWindows: false);
      expect(start.executable, './scripts/run.sh');
      expect(start.arguments, ['-t', 'tool/main.dart']);
      expect(start.runInShell, isFalse);
    });

    test('an empty command is a mistake, not a crash later', () {
      expect(
        () => startCommandFor(const [], isWindows: false),
        throwsArgumentError,
      );
    });
  });

  group('running a batch file on Windows', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fp_start_');
      // A `.bat` that forwards to a Dart program, the way `flutter.bat`
      // forwards to flutter_tools with `%*`.
      File('${dir.path}/args.dart').writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  stdout.writeln('ARGS=\${jsonEncode(args)}');
  if (args.contains('hold')) {
    stdout.writeln('PID=\$pid');
    sleep(const Duration(seconds: 20));
  }
}
''');
      File('${dir.path}/echo_args.bat').writeAsStringSync(
        '@echo off\r\n'
        '"${Platform.resolvedExecutable}" "%~dp0args.dart" %*\r\n',
      );
      File('${dir.path}/hold.bat').writeAsStringSync(
        '@echo off\r\n'
        '"${Platform.resolvedExecutable}" "%~dp0args.dart" hold\r\n',
      );
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// The `ARGS=` line the batch file's Dart program printed.
    Future<List<String>> outputOf(List<String> arguments) async {
      final start = startCommandFor([
        'echo_args.bat',
        ...arguments,
      ], workingDirectory: dir.path);
      final process = await Process.start(
        start.executable,
        start.arguments,
        workingDirectory: dir.path,
        runInShell: start.runInShell,
      );
      final lines = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList()
          .timeout(const Duration(seconds: 20));
      await process.exitCode;
      final args = jsonDecode(
        lines.firstWhere((line) => line.startsWith('ARGS=')).substring(5),
      );
      return [for (final a in args as List) '$a'];
    }

    test('a dart-define with a space and & reaches the app as given', () async {
      // The example the task names: Dart quotes it for `cmd.exe`, and
      // `flutter.bat`'s `%*` forwards it whole (field test #327).
      expect(await outputOf(['--dart-define=GREETING=a b&c']), [
        '--dart-define=GREETING=a b&c',
      ]);
    });

    test('a path with spaces, a ; and a \\ survives', () async {
      const args = ['lib/main.dart', 'x y', 'semi;colon', r'C:\a b\c.dart'];
      expect(await outputOf(args), args);
    });

    test('killLaunchTree ends the shell and the build it started', () async {
      final start = startCommandFor(['hold.bat'], workingDirectory: dir.path);
      final process = await Process.start(
        start.executable,
        start.arguments,
        workingDirectory: dir.path,
        runInShell: start.runInShell,
      );
      addTearDown(() => killLaunchTree(process.pid));
      final lines = <String>[];
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) {
            lines.add(line);
            return line.startsWith('PID=');
          })
          .timeout(const Duration(seconds: 20));
      final child = lines
          .lastWhere((line) => line.startsWith('PID='))
          .substring(4);

      await killLaunchTree(process.pid);

      final gone = await _goneWithin(child, const Duration(seconds: 10));
      expect(
        gone,
        isTrue,
        reason: 'the launch\u2019s child (pid $child) survived',
      );
    });
  }, skip: Platform.isWindows ? false : 'Windows only');
}

/// Whether [a] and [b] name the same file on Windows, which matches without
/// case: `PATHEXT` is upper case and the file on disk is lower.
bool sameFile(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// Whether [pid] is gone, checked for up to [limit].
Future<bool> _goneWithin(String pid, Duration limit) async {
  final until = DateTime.now().add(limit);
  while (DateTime.now().isBefore(until)) {
    final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
    if (!'${result.stdout}'.contains(' $pid ')) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}
