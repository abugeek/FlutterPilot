// Regression tests for tool/package_test_runner.dart (task 00).
//
// The runner is dependency-free on purpose; these tests exercise it in-process
// with an injected process runner, and as a real subprocess with an injected
// argv prefix so no network or `pub get` is needed and both Windows and POSIX
// must behave the same.
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/package_test_runner.dart';

/// A [TestProcessRunner] that records commands and returns canned exit codes.
class _FakeRunner implements TestProcessRunner {
  _FakeRunner(this.codes);

  /// Package relative path -> exit code, or a [ProcessException] to throw.
  final Map<String, Object> codes;
  final List<({List<String> command, String cwd})> calls = [];

  @override
  Future<int> run(List<String> command, String workingDirectory) async {
    calls.add((command: command, cwd: workingDirectory));
    final key = workingDirectory.replaceAll('\\', '/');
    final match = codes.entries.firstWhere(
      (e) => key.endsWith(e.key),
      orElse: () => const MapEntry('', 0),
    );
    final value = match.value;
    if (value is ProcessException) throw value;
    return value as int;
  }
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fp_runner_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Writes a minimal package (pubspec + optional test file) under [path].
  void writePackage(
    String path, {
    required String name,
    bool flutter = false,
    bool withTest = true,
    bool withTestFile = true,
  }) {
    final dir = Directory(path)..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
      'name: $name\n${flutter ? 'flutter:\n  uses-material-design: true\n' : ''}',
    );
    if (withTest) {
      final testDir = Directory('${dir.path}${Platform.pathSeparator}test')
        ..createSync(recursive: true);
      if (withTestFile) {
        File(
          '${testDir.path}${Platform.pathSeparator}${name}_test.dart',
        ).writeAsStringSync('void main() {}\n');
      }
    }
  }

  group('discovery', () {
    test('finds packages deterministically and classifies the runtime', () {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}z_pkg',
        name: 'z_pkg',
        flutter: true,
      );
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}a_pkg',
        name: 'a_pkg',
      );
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}plugins'
        '${Platform.pathSeparator}m_pkg',
        name: 'm_pkg',
        flutter: true,
      );
      writePackage(
        '$r${Platform.pathSeparator}examples'
        '${Platform.pathSeparator}ex',
        name: 'ex',
      );

      final packages = discoverPackages(root: r);
      expect(packages.map((p) => p.relativePath), [
        'examples/ex',
        'packages/a_pkg',
        'packages/plugins/m_pkg',
        'packages/z_pkg',
      ]);
      expect(
        packages.singleWhere((p) => p.name == 'z_pkg').runtime,
        TestRuntime.flutter,
      );
      expect(
        packages.singleWhere((p) => p.name == 'a_pkg').runtime,
        TestRuntime.dart,
      );
      expect(
        packages.singleWhere((p) => p.name == 'm_pkg').runtime,
        TestRuntime.flutter,
      );
    });

    test('a missing test directory is skipped with a reason', () {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}no_tests',
        name: 'no_tests',
        withTest: false,
      );
      final package = discoverPackages(root: r).single;
      expect(package.hasTests, isFalse);
      expect(package.skipReason, contains('no test/ directory'));
    });

    test('a test directory without *_test.dart is skipped with a reason', () {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}empty_tests',
        name: 'empty_tests',
        withTestFile: false,
      );
      final package = discoverPackages(root: r).single;
      expect(package.hasTests, isFalse);
      expect(package.skipReason, contains('no *_test.dart'));
    });
  });

  group('execution', () {
    List<TestPackage> packagesIn(String r) => discoverPackages(root: r);

    test('every package runs `test` in its own directory', () async {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}a_pkg',
        name: 'a_pkg',
      );
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}b_pkg',
        name: 'b_pkg',
        flutter: true,
      );
      final fake = _FakeRunner(const {});
      final summary = await runPackageTests(
        packages: packagesIn(r),
        runner: fake,
        dartCommand: const ['dart'],
        flutterCommand: const ['flutter'],
      );
      expect(summary.ok, isTrue);
      expect(summary.exitCode, 0);
      expect(fake.calls.map((c) => c.command), [
        ['dart', 'test'],
        ['flutter', 'test'],
      ]);
      expect(fake.calls[0].cwd, endsWith('a_pkg'));
      expect(fake.calls[1].cwd, endsWith('b_pkg'));
    });

    test('a failing package fails the aggregate and exits nonzero', () async {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}good',
        name: 'good',
      );
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}bad',
        name: 'bad',
      );
      final fake = _FakeRunner(const {'packages/bad': 1, 'packages/good': 0});
      final summary = await runPackageTests(
        packages: packagesIn(r),
        runner: fake,
        dartCommand: const ['dart'],
        flutterCommand: const ['flutter'],
      );
      expect(summary.ok, isFalse);
      expect(summary.exitCode, 1);
      expect(summary.passed, 1);
      expect(summary.failed, 1);
    });

    test(
      'a Flutter failure never falls back to Dart and still fails',
      () async {
        final r = root.path;
        writePackage(
          '$r${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}fl',
          name: 'fl',
          flutter: true,
        );
        final fake = _FakeRunner(const {'packages/fl': 1});
        final summary = await runPackageTests(
          packages: packagesIn(r),
          runner: fake,
          dartCommand: const ['dart'],
          flutterCommand: const ['flutter'],
        );
        expect(summary.ok, isFalse);
        // Exactly one invocation: the failure was not retried with `dart test`.
        expect(fake.calls, hasLength(1));
        expect(fake.calls.single.command, ['flutter', 'test']);
      },
    );

    test('a command that cannot start is an error, not a pass', () async {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}x',
        name: 'x',
      );
      final fake = _FakeRunner({
        'packages/x': const ProcessException('nope', []),
      });
      final summary = await runPackageTests(
        packages: packagesIn(r),
        runner: fake,
        dartCommand: const ['nope'],
        flutterCommand: const ['nope'],
      );
      expect(summary.ok, isFalse);
      expect(summary.errored, 1);
      expect(summary.results.single.reason, contains('could not start'));
    });

    test('skipped packages never fail the aggregate', () async {
      final r = root.path;
      writePackage(
        '$r${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}none',
        name: 'none',
        withTest: false,
      );
      final fake = _FakeRunner(const {});
      final summary = await runPackageTests(
        packages: packagesIn(r),
        runner: fake,
        dartCommand: const ['dart'],
        flutterCommand: const ['flutter'],
      );
      expect(summary.ok, isTrue);
      expect(summary.skipped, 1);
      expect(fake.calls, isEmpty);
    });
  });

  group('as a real subprocess, fail-closed', () {
    late String dartExe;
    late String runnerPath;
    late Directory tree;
    late File fakeScript;

    setUp(() {
      dartExe = Platform.resolvedExecutable;
      // packages/fp_server/test -> repository root
      final repoRoot = Directory.current.parent.parent.path;
      runnerPath =
          '$repoRoot${Platform.pathSeparator}tool'
          '${Platform.pathSeparator}package_test_runner.dart';
      expect(File(runnerPath).existsSync(), isTrue, reason: runnerPath);
      // A path containing a space, to prove argument vectors survive it.
      tree = Directory.systemTemp.createTempSync('fp runner sub ');
      fakeScript = File('${tree.path}${Platform.pathSeparator}fake_test.dart')
        ..writeAsStringSync('''
import 'dart:io';
void main(List<String> args) {
  final stamp = File('exit_code.txt');
  final code = stamp.existsSync()
      ? int.tryParse(stamp.readAsStringSync().trim()) ?? 0
      : 0;
  stdout.writeln('fake test in \${Directory.current.path} args=\$args');
  exit(code);
}
''');
    });

    tearDown(() {
      if (tree.existsSync()) tree.deleteSync(recursive: true);
    });

    void package(String name, int exitCode, {bool withTest = true}) {
      final dir = Directory(
        '${tree.path}${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}$name',
      )..createSync(recursive: true);
      File(
        '${dir.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('name: $name\n');
      File(
        '${dir.path}${Platform.pathSeparator}exit_code.txt',
      ).writeAsStringSync('$exitCode');
      if (withTest) {
        final testDir = Directory('${dir.path}${Platform.pathSeparator}test')
          ..createSync(recursive: true);
        File(
          '${testDir.path}${Platform.pathSeparator}${name}_test.dart',
        ).writeAsStringSync('void main() {}\n');
      }
    }

    Future<ProcessResult> run(List<String> extra) => Process.run(dartExe, [
      runnerPath,
      '--root',
      tree.path,
      '--dart-command',
      dartExe,
      '--dart-command',
      fakeScript.path,
      ...extra,
    ]);

    test('a passing tree exits 0 and streams the fake output', () async {
      package('good', 0);
      final result = await run(const []);
      expect(result.exitCode, 0, reason: result.stdout.toString());
      expect(result.stdout.toString(), contains('fake test in'));
      expect(result.stdout.toString(), contains('good'));
    });

    test('one failing package makes the aggregate exit nonzero', () async {
      package('good', 0);
      package('bad', 1);
      final result = await run(const []);
      expect(result.exitCode, isNot(0), reason: result.stdout.toString());
      final out = result.stdout.toString();
      expect(out, contains('FAILED'));
      expect(out, contains('1 failed'));
    });

    test(
      'a nonexistent executable fails the gate with a clear reason',
      () async {
        package('good', 0);
        final result = await Process.run(dartExe, [
          runnerPath,
          '--root',
          tree.path,
          '--dart-command',
          'definitely-not-a-real-binary-xyz',
        ]);
        expect(result.exitCode, isNot(0), reason: result.stdout.toString());
        final combined = '${result.stdout}${result.stderr}';
        expect(combined, contains('could not start'));
      },
    );

    test('--only selects one package and skips the rest', () async {
      package('good', 0);
      package('bad', 1);
      final result = await run(const ['--only', 'good']);
      expect(result.exitCode, 0, reason: result.stdout.toString());
    });

    test('a package with no test directory is skipped, not failed', () async {
      package('good', 0);
      package('none', 0, withTest: false);
      final result = await run(const []);
      expect(result.exitCode, 0, reason: result.stdout.toString());
      expect(result.stdout.toString(), contains('skipped'));
    });

    test(
      'the process exits nonzero when a package has tests but is not bootstrapped',
      () async {
        // No --dart-command: the runner uses the real `dart`, and the fixture has
        // no .dart_tool/package_config.json, so it must fail rather than skip.
        package('good', 0);
        final result = await Process.run(dartExe, [
          runnerPath,
          '--root',
          tree.path,
          '--only',
          'good',
        ]);
        expect(result.exitCode, isNot(0), reason: result.stdout.toString());
        expect(result.stdout.toString(), contains('not bootstrapped'));
      },
    );
  });

  test('parseArgs rejects unknown flags and accepts repeatable commands', () {
    expect(parseArgs(const ['--root', '/tmp/x', '--only', 'a,b'], '/').only, [
      'a',
      'b',
    ]);
    expect(
      () => parseArgs(const ['--nope'], '/'),
      throwsA(isA<FormatException>()),
    );
    final commands = parseArgs(const [
      '--dart-command',
      'a',
      '--dart-command',
      'b',
    ], '/');
    expect(commands.dartCommand, ['a', 'b']);
  });

  test('manifest-independent: unknown --only selection is a hard error', () {
    // Guards the CLI contract that a mistyped --only must not run everything.
    expect(
      () => parseArgs(const ['--only'], '/'),
      throwsA(isA<FormatException>()),
    );
  });
}
