// Tests for the reload-error fallback (task 10).
//
// The fallback is the only place FlutterPilot runs whole-file analysis, and it
// is reached only after a reload failure that looks like a compile error. These
// tests prove, with a fake runner and a disposable project, that it: never
// analyzes when no file changed, parses machine-format errors, stays quiet on a
// clean or failed analyzer, reports failures/timings through the **opt-in**
// counter, and is never even entered for the non-compiler hints.
library;

import 'dart:async';
import 'dart:io';

import 'package:fp_server/src/reload_failure.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  final seen = <CompileFallbackEvent>[];

  setUp(() {
    seen.clear();
    compileFallbackObserver = seen.add;
  });

  tearDown(() {
    compileFallbackObserver = null;
    if (project.existsSync()) {
      try {
        project.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Directory makeProject(List<String> libFiles) {
    final dir = Directory.systemTemp.createTempSync('fp_analyzer_');
    final lib = Directory('${dir.path}${Platform.pathSeparator}lib')
      ..createSync(recursive: true);
    for (final name in libFiles) {
      File(
        '${lib.path}${Platform.pathSeparator}$name',
      ).writeAsStringSync('void main() {}\n');
    }
    return dir;
  }

  /// A runner that records its argv and working directory, then replies with
  /// [stdout] (exit 1) without spawning anything.
  Future<ProcessResult> Function(List<String>, {String? workingDirectory})
  fakeRunner(
    String stdout, {
    List<List<String>>? argvLog,
    List<String?>? cwdLog,
  }) => (command, {workingDirectory}) async {
    argvLog?.add(command);
    cwdLog?.add(workingDirectory);
    return ProcessResult(0, 1, stdout, '');
  };

  test('no changed files: the analyzer is never launched', () async {
    project = makeProject(['a.dart']);
    var called = false;

    final result = await analyzerFallbackErrors(
      root: project.path,
      // Everything is older than this instant, so nothing counts as changed.
      since: DateTime.now().add(const Duration(minutes: 1)),
      runner: (command, {workingDirectory}) async {
        called = true;
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(result, '');
    expect(called, isFalse, reason: 'a reload with no edits must not analyze');
    expect(seen, hasLength(1));
    expect(seen.single.outcome, 'no-changed-files');
    expect(seen.single.files, 0);
    expect(seen.single.fromLog, isFalse);
  });

  test(
    'machine-format errors are parsed and reported as analyzer-errors',
    () async {
      project = makeProject(['a.dart', 'b.dart']);
      final argvLog = <List<String>>[];
      final cwdLog = <String?>[];
      final path =
          '${project.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}a.dart';

      final result = await analyzerFallbackErrors(
        root: project.path,
        since: DateTime.now().subtract(const Duration(minutes: 1)),
        runner: fakeRunner(
          'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|$path|3|5|7|'
          "Undefined name 'x'.\n",
          argvLog: argvLog,
          cwdLog: cwdLog,
        ),
      );

      expect(result, contains('lib/a.dart:3:5:'));
      expect(result, contains("Undefined name 'x'."));
      // The analyzer is asked in machine format, once, in the project root.
      expect(argvLog.single.take(3), ['dart', 'analyze', '--format=machine']);
      expect(argvLog.single.length, greaterThan(3));
      expect(cwdLog.single, project.path);
      expect(seen.single.outcome, 'analyzer-errors');
      expect(seen.single.files, 2);
      expect(seen.single.timedOut, isFalse);
    },
  );

  test('a clean analyzer run reports analyzer-clean and no errors', () async {
    project = makeProject(['a.dart']);

    final result = await analyzerFallbackErrors(
      root: project.path,
      since: DateTime.now().subtract(const Duration(minutes: 1)),
      runner: fakeRunner('INFO|NOTE|UNUSED_ELEMENT|a.dart|1|1|3|unused\n'),
    );

    expect(result, '');
    expect(seen.single.outcome, 'analyzer-clean');
  });

  test('a timeout is reported as analyzer-failed with timedOut=true', () async {
    project = makeProject(['a.dart']);

    final result = await analyzerFallbackErrors(
      root: project.path,
      since: DateTime.now().subtract(const Duration(minutes: 1)),
      // Never completes: the deadline must fire and the branch be recorded.
      runner: (command, {workingDirectory}) =>
          Completer<ProcessResult>().future,
      timeout: const Duration(milliseconds: 40),
    );

    expect(result, '');
    expect(seen.single.outcome, 'analyzer-failed');
    expect(seen.single.timedOut, isTrue);
    expect(seen.single.durationMs, greaterThanOrEqualTo(0));
  });

  test(
    'a process failure is reported without being called a timeout',
    () async {
      project = makeProject(['a.dart']);

      final result = await analyzerFallbackErrors(
        root: project.path,
        since: DateTime.now().subtract(const Duration(minutes: 1)),
        runner: (command, {workingDirectory}) async =>
            throw ProcessException('dart', const []),
      );

      expect(result, '');
      expect(seen.single.outcome, 'analyzer-failed');
      expect(seen.single.timedOut, isFalse);
    },
  );

  test(
    'with no observer installed nothing is recorded and nothing throws',
    () async {
      project = makeProject(['a.dart']);
      compileFallbackObserver = null;

      final result = await analyzerFallbackErrors(
        root: project.path,
        since: DateTime.now().subtract(const Duration(minutes: 1)),
        runner: fakeRunner(''),
      );

      expect(result, '');
      expect(seen, isEmpty);
    },
  );

  test('at most maxFiles edited files are analyzed', () async {
    project = makeProject(['a.dart', 'b.dart', 'c.dart', 'd.dart']);
    final argvLog = <List<String>>[];

    await analyzerFallbackErrors(
      root: project.path,
      since: DateTime.now().subtract(const Duration(minutes: 1)),
      runner: fakeRunner('', argvLog: argvLog),
      maxFiles: 2,
    );

    // 3 fixed argv entries precede the file list.
    expect(argvLog.single.length - 3, 2);
    expect(seen.single.files, 2);
  });

  group('log-first boundary (no unnecessary analysis)', () {
    test('a non-compiler hint never reaches the analyzer', () {
      // The sandboxed-write and missing-asset replies are named as *not* a
      // compile error, so `_compileErrors` is not even called for them.
      expect(
        mayBeCompileError(
          'Flutter failed to copy assets/a.svg to /build due to source '
          'location error. The file or directory could not be found.',
        ),
        isFalse,
      );
      expect(
        mayBeCompileError(
          'Flutter failed to create file at '
          '"/Users/me/Library/Containers/com.example.app/Data/tmp/x.dill".',
        ),
        isFalse,
      );
    });

    test('an empty reply is treated as a possible compile error', () {
      expect(mayBeCompileError(''), isTrue);
    });
  });
}
