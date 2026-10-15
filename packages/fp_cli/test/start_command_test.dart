import 'package:fp_cli/src/start_command.dart';
import 'package:test/test.dart';

void main() {
  group('startCommandFor on Windows', () {
    // The files of a Windows Flutter machine, so no real PATH is needed.
    // Windows matches a file name whatever its case, which is why the
    // resolved name keeps the case `PATHEXT` was written in.
    const files = {
      r'C:\flutter\bin\flutter',
      r'C:\flutter\bin\flutter.bat',
      r'C:\app\scripts\run.bat',
    };

    /// Windows matches a file name whatever its case, and the `.` segments of
    /// a path resolve before the file system is touched.
    bool exists(String path) => files.any(
      (file) =>
          file.replaceAll('/', r'\').toLowerCase() ==
          path.replaceAll('/', r'\').replaceAll(r'\.\', r'\').toLowerCase(),
    );

    test('flutter.bat is found and run through the shell', () {
      final start = startCommandFor(
        ['flutter', 'run', '-d', 'windows'],
        isWindows: true,
        path: r'C:\flutter\bin',
        pathExt: '.EXE;.BAT',
        workingDirectory: r'C:\app',
        exists: exists,
      );
      expect(start.executable, r'C:\flutter\bin\flutter.BAT');
      expect(start.arguments, ['run', '-d', 'windows']);
      expect(start.runInShell, isTrue);
    });

    test("a project's own .bat is resolved against the app folder", () {
      final start = startCommandFor(
        [r'./scripts/run.bat'],
        isWindows: true,
        path: '',
        pathExt: '.EXE;.BAT',
        workingDirectory: r'C:\app',
        exists: exists,
      );
      expect(start.executable, r'C:\app\.\scripts\run.bat');
      expect(start.runInShell, isTrue);
    });

    test('another OS leaves the command alone', () {
      final start = startCommandFor(['flutter', 'run'], isWindows: false);
      expect(start.executable, 'flutter');
      expect(start.runInShell, isFalse);
    });
  });
}
