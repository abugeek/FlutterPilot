// Portable, fail-closed aggregate test runner for the FlutterPilot monorepo
// (task 00).
//
// `melos run test` used to run
//   test -d test && (flutter test || dart test) || echo 'No tests'
// per package. In a POSIX shell a failing `flutter test` fell through to
// `dart test`, and a failure at the very end of a chain could still reach the
// successful `echo`; the syntax is also not portable to PowerShell. A green
// aggregate therefore did not prove every suite passed.
//
// This runner is the replacement. It is deliberately dependency-free (only
// `dart:` libraries) so it starts without `pub get`:
//
//   * it discovers test-bearing packages under `packages/` and `examples/`
//     deterministically (sorted by path);
//   * it decides Dart versus Flutter once, from package metadata, and never
//     falls back from a failed Flutter run to Dart;
//   * it runs each suite with an argument vector in the package's own working
//     directory and propagates every nonzero exit;
//   * a missing executable, an un-bootstrapped package, or any other setup
//     problem is a failure, not a skip;
//   * only a genuinely missing `test/` directory (or a `test/` directory with
//     no `*_test.dart`) is skipped, and the reason is printed.
//
// Run from the repository root:
//   dart run tool/package_test_runner.dart
//   dart run tool/package_test_runner.dart --only fp_server,fp_sdk
//   dart run tool/package_test_runner.dart --list
//
// The `--dart-command` / `--flutter-command` flags are repeatable argv
// prefixes used by the runner's own regression tests; they are not needed in
// normal use.
library;

import 'dart:async';
import 'dart:io';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Which test tool drives a package.
enum TestRuntime {
  dart('dart'),
  flutter('flutter');

  const TestRuntime(this.label);

  /// The name printed in the report.
  final String label;
}

/// What happened to a package.
enum PackageStatus {
  passed,
  failed,
  skipped,
  error;

  bool get isFailure => this == failed || this == error;
}

/// One package the runner considered.
class TestPackage {
  TestPackage({
    required this.name,
    required this.directory,
    required this.relativePath,
    required this.runtime,
    required this.hasTests,
    this.skipReason,
  });

  /// The pubspec `name:`.
  final String name;

  /// Absolute package directory.
  final String directory;

  /// Path relative to the repository root, for display and sorting.
  final String relativePath;

  final TestRuntime runtime;

  /// Whether a `test/` directory with at least one `*_test.dart` exists.
  final bool hasTests;

  /// Why the package was skipped, when [hasTests] is false.
  final String? skipReason;
}

/// The outcome of running (or skipping) one package.
class PackageResult {
  PackageResult({
    required this.package,
    required this.status,
    this.exitCode,
    this.reason,
    this.duration,
  });

  final TestPackage package;
  final PackageStatus status;
  final int? exitCode;
  final String? reason;
  final Duration? duration;
}

/// Everything the run found, in discovery order.
class RunSummary {
  RunSummary(this.results);

  final List<PackageResult> results;

  /// True only when every package either passed or was genuinely skipped for a
  /// missing test directory. A setup problem is never a pass.
  bool get ok => !results.any((r) => r.status.isFailure);

  int get passed =>
      results.where((r) => r.status == PackageStatus.passed).length;
  int get failed =>
      results.where((r) => r.status == PackageStatus.failed).length;
  int get errored =>
      results.where((r) => r.status == PackageStatus.error).length;
  int get skipped =>
      results.where((r) => r.status == PackageStatus.skipped).length;

  /// The process exit code the runner's `main` uses.
  int get exitCode => ok ? 0 : 1;
}

/// A declared executable could not be found.
class ExecutableNotFoundException implements Exception {
  ExecutableNotFoundException(this.executable, [this.searched]);

  final String executable;
  final List<String>? searched;

  @override
  String toString() =>
      'Executable "$executable" was not found'
      '${searched == null ? '' : ' on PATH (${searched!.join(', ')})'}. '
      'Install it, or pass --dart-command/--flutter-command.';
}

// ---------------------------------------------------------------------------
// Process abstraction (so tests can run without spawning)
// ---------------------------------------------------------------------------

/// Runs a test command and returns its exit code.
abstract class TestProcessRunner {
  /// Runs [command] with [workingDirectory] as cwd, streaming output to the
  /// parent, and resolves to the process exit code.
  Future<int> run(List<String> command, String workingDirectory);
}

/// The production runner: `Process.start`, inherited stdio, exit code.
class StreamingProcessRunner implements TestProcessRunner {
  const StreamingProcessRunner();

  @override
  Future<int> run(List<String> command, String workingDirectory) async {
    final process = await Process.start(
      command.first,
      command.sublist(1),
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.normal,
    );
    // Copy both streams to ours. `pipe` is not used: it closes the sink when
    // the child's stream ends, which would close the runner's own stdout.
    final stdoutDone = process.stdout.listen(stdout.add).asFuture<void>();
    final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();
    final code = await process.exitCode;
    await stdoutDone;
    await stderrDone;
    return code;
  }
}

// ---------------------------------------------------------------------------
// Discovery and classification
// ---------------------------------------------------------------------------

/// Directories never walked while discovering packages.
const _skippedDirs = {
  '.dart_tool',
  '.git',
  '.idea',
  'build',
  'node_modules',
  'Pods',
  '.symlinks',
};

/// Packages that are deliberately not part of the aggregate suite.
const _excluded = <String>{};

/// Finds every package with a `pubspec.yaml` under [root]'s `packages/` and
/// `examples/` (or under [roots] when given), sorted by relative path.
///
/// [roots] are resolved against [root] when relative. Deterministic: the walk
/// sorts each directory before descending.
List<TestPackage> discoverPackages({
  required String root,
  List<String>? roots,
}) {
  final searchRoots = (roots ?? const ['packages', 'examples'])
      .map((r) => _isAbsolute(r) ? r : '$root${Platform.pathSeparator}$r')
      .toList();
  final found = <TestPackage>[];
  for (final searchRoot in searchRoots) {
    final dir = Directory(searchRoot);
    if (!dir.existsSync()) continue;
    for (final pubspec in _findPubspecs(dir)) {
      final packageDir = pubspec.parent;
      final relative = _relative(root, packageDir.path);
      if (_excluded.contains(relative)) continue;
      final name = _pubspecName(pubspec) ?? relative;
      final runtime = _runtimeOf(packageDir);
      final reason = _skipReason(packageDir);
      found.add(
        TestPackage(
          name: name,
          directory: packageDir.path,
          relativePath: relative,
          runtime: runtime,
          hasTests: reason == null,
          skipReason: reason,
        ),
      );
    }
  }
  found.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return found;
}

/// Every `pubspec.yaml` under [dir], depth-first with sorted children.
List<File> _findPubspecs(Directory dir) {
  final result = <File>[];
  final entries = dir.listSync(followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entry in entries) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is! Directory) continue;
    if (_skippedDirs.contains(name) || name.startsWith('.')) continue;
    final pubspec = File('${entry.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspec.existsSync()) {
      result.add(pubspec);
      // A package's own subdirectories are not searched: a nested dependency
      // package would be a different package manager's concern. The monorepo
      // layout only ever nests a package directly.
      continue;
    }
    result.addAll(_findPubspecs(entry));
  }
  return result;
}

/// The pubspec `name:` value, or null.
String? _pubspecName(File pubspec) {
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^name:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) return match.group(1);
    if (line.trim().isNotEmpty && !line.startsWith('#')) break;
  }
  return null;
}

/// Why [dir] has nothing to test, or null when it has tests.
String? _skipReason(Directory dir) {
  final testDir = Directory('${dir.path}${Platform.pathSeparator}test');
  if (!testDir.existsSync()) return 'no test/ directory';
  final hasTestFile = testDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .any((f) => f.path.endsWith('_test.dart'));
  if (!hasTestFile) return 'no *_test.dart under test/';
  return null;
}

/// Dart or Flutter, decided once, from package metadata.
///
/// The resolved `package_config.json` is authoritative when present (a Flutter
/// package always pulls in the `flutter` SDK package); otherwise the pubspec
/// text is scanned for `sdk: flutter` or a top-level `flutter:` section.
TestRuntime _runtimeOf(Directory dir) {
  final config = File(
    '${dir.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}package_config.json',
  );
  if (config.existsSync()) {
    try {
      final text = config.readAsStringSync();
      if (RegExp(r'"name"\s*:\s*"flutter"').hasMatch(text)) {
        return TestRuntime.flutter;
      }
      return TestRuntime.dart;
    } catch (_) {
      // Fall through to the pubspec.
    }
  }
  final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
  if (pubspec.existsSync()) {
    for (final line in pubspec.readAsLinesSync()) {
      if (line.trimRight() == 'flutter:') return TestRuntime.flutter;
      if (RegExp(r'^\s*sdk:\s*flutter\s*$').hasMatch(line)) {
        return TestRuntime.flutter;
      }
    }
  }
  return TestRuntime.dart;
}

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

/// Runs the discovered [packages] and returns the [RunSummary].
///
/// [dartCommand]/[flutterCommand] are the resolved argv prefixes (default
/// `['dart']` / `['flutter']`); `test` is appended. [runner] is injectable for
/// tests. A package whose command cannot start becomes an [PackageStatus.error]
/// and therefore fails the gate.
Future<RunSummary> runPackageTests({
  required List<TestPackage> packages,
  TestProcessRunner runner = const StreamingProcessRunner(),
  List<String>? dartCommand,
  List<String>? flutterCommand,
  void Function(String message)? log,
}) async {
  final results = <PackageResult>[];
  final useDefaultCommands = dartCommand == null && flutterCommand == null;
  // Resolve the declared executables once. A machine without Flutter must not
  // make a Dart-only package fail, but it must not silently pass either: the
  // packages it can't run become errors below.
  final List<String> dartPrefix;
  final List<String> flutterPrefix;
  try {
    dartPrefix = dartCommand ?? [_resolveExecutable('dart')];
    flutterPrefix = flutterCommand ?? [_resolveExecutable('flutter')];
  } on ExecutableNotFoundException catch (e) {
    for (final package in packages) {
      if (!package.hasTests) {
        results.add(
          PackageResult(
            package: package,
            status: PackageStatus.skipped,
            reason: package.skipReason,
          ),
        );
      } else {
        results.add(
          PackageResult(
            package: package,
            status: PackageStatus.error,
            reason: e.toString(),
          ),
        );
      }
    }
    return RunSummary(results);
  }

  for (final package in packages) {
    final write = log ?? stdout.writeln;
    if (!package.hasTests) {
      results.add(
        PackageResult(
          package: package,
          status: PackageStatus.skipped,
          reason: package.skipReason,
        ),
      );
      continue;
    }
    // A package with tests but no resolution cannot be tested; that is a setup
    // failure, not a skip. (Skipped when a test command is injected, because
    // an injected command may not need pub resolution.)
    if (useDefaultCommands && !_isBootstrapped(package.directory)) {
      results.add(
        PackageResult(
          package: package,
          status: PackageStatus.error,
          reason:
              'not bootstrapped (no .dart_tool/package_config.json); run '
              '`melos bootstrap` or `dart pub get` here',
        ),
      );
      continue;
    }
    final prefix = package.runtime == TestRuntime.flutter
        ? flutterPrefix
        : dartPrefix;
    final command = [...prefix, 'test'];
    write('▶ ${package.relativePath} (${package.runtime.label})');
    final stopwatch = Stopwatch()..start();
    try {
      final code = await runner.run(command, package.directory);
      stopwatch.stop();
      results.add(
        PackageResult(
          package: package,
          status: code == 0 ? PackageStatus.passed : PackageStatus.failed,
          exitCode: code,
          duration: stopwatch.elapsed,
        ),
      );
    } on ExecutableNotFoundException catch (e) {
      stopwatch.stop();
      results.add(
        PackageResult(
          package: package,
          status: PackageStatus.error,
          reason: e.toString(),
        ),
      );
    } on ProcessException catch (e) {
      stopwatch.stop();
      results.add(
        PackageResult(
          package: package,
          status: PackageStatus.error,
          reason: 'could not start ${command.first}: ${e.message}',
        ),
      );
    }
  }
  return RunSummary(results);
}

bool _isBootstrapped(String directory) => File(
  '$directory${Platform.pathSeparator}.dart_tool'
  '${Platform.pathSeparator}package_config.json',
).existsSync();

/// Resolves [name] to an absolute path on PATH, wrapping Windows batch
/// launchers explicitly so a `.bat`/`.cmd` is invoked the way the shell would.
///
/// Throws [ExecutableNotFoundException] when it is nowhere on PATH.
String _resolveExecutable(String name) {
  final fromPath = _searchPath(name);
  if (fromPath != null) return fromPath;
  // `dart` is always next to the running executable on a machine that can run
  // this script at all; use it as a last resort before failing.
  final self = Platform.resolvedExecutable;
  final selfDir = self.substring(0, self.lastIndexOf(Platform.pathSeparator));
  for (final candidate in _candidatesFor(name)) {
    final path = '$selfDir${Platform.pathSeparator}$candidate';
    if (File(path).existsSync()) return path;
  }
  throw ExecutableNotFoundException(name);
}

String? _searchPath(String name) {
  final pathVar = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  final searched = <String>[];
  for (final dir in pathVar.split(separator)) {
    if (dir.isEmpty) continue;
    for (final candidate in _candidatesFor(name)) {
      final path = '$dir${Platform.pathSeparator}$candidate';
      if (File(path).existsSync()) return path;
    }
    searched.add(dir);
  }
  return null;
}

/// Candidate filenames for [name] on this platform, most specific first.
List<String> _candidatesFor(String name) =>
    Platform.isWindows ? ['$name.bat', '$name.cmd', '$name.exe', name] : [name];

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

/// Parsed command-line options.
class RunnerOptions {
  RunnerOptions({
    required this.root,
    this.only = const [],
    this.list = false,
    this.dryRun = false,
    this.dartCommand,
    this.flutterCommand,
  });

  final String root;
  final List<String> only;
  final bool list;
  final bool dryRun;
  final List<String>? dartCommand;
  final List<String>? flutterCommand;
}

/// The process entry point. `main`'s return value is ignored by the Dart VM,
/// so the exit code is set explicitly.
Future<void> main(List<String> args) async {
  final code = await runMain(args);
  await stdout.flush();
  await stderr.flush();
  exitCode = code;
}

/// The runner body, returning the process exit code. Exposed so it can be
/// exercised without `exit`.
Future<int> runMain(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return 0;
  }
  final RunnerOptions options;
  try {
    options = parseArgs(args, Directory.current.path);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(usage);
    return 2;
  }

  final rootDir = Directory(options.root);
  if (!rootDir.existsSync()) {
    stderr.writeln('Repository root does not exist: ${options.root}');
    return 2;
  }

  var packages = discoverPackages(root: rootDir.absolute.path);
  if (options.only.isNotEmpty) {
    packages = packages
        .where(
          (p) => options.only.any(
            (needle) =>
                p.name == needle ||
                p.relativePath == needle ||
                p.relativePath.endsWith('/$needle'),
          ),
        )
        .toList();
    if (packages.isEmpty) {
      stderr.writeln('No package matched --only ${options.only.join(',')}');
      return 2;
    }
  }

  if (options.list || options.dryRun) {
    stdout.writeln('${packages.length} packages discovered:');
    for (final package in packages) {
      final what = package.hasTests
          ? '${package.runtime.label} test'
          : 'skip: ${package.skipReason}';
      stdout.writeln('  ${package.relativePath.padRight(42)} $what');
    }
    return 0;
  }

  stdout.writeln('FlutterPilot package tests');
  stdout.writeln('root: ${rootDir.absolute.path}');
  stdout.writeln();

  final summary = await runPackageTests(
    packages: packages,
    dartCommand: options.dartCommand,
    flutterCommand: options.flutterCommand,
  );

  stdout.writeln();
  for (final result in summary.results) {
    final line = switch (result.status) {
      PackageStatus.passed =>
        '✓ ${result.package.relativePath.padRight(42)} passed'
            '${_seconds(result.duration)}',
      PackageStatus.failed =>
        '✗ ${result.package.relativePath.padRight(42)} FAILED '
            '(exit ${result.exitCode})',
      PackageStatus.error =>
        '✗ ${result.package.relativePath.padRight(42)} ERROR — '
            '${result.reason}',
      PackageStatus.skipped =>
        '· ${result.package.relativePath.padRight(42)} skipped — '
            '${result.reason}',
    };
    stdout.writeln(line);
  }

  stdout.writeln();
  stdout.writeln(
    '${summary.passed} passed, ${summary.failed} failed, '
    '${summary.errored} errored, ${summary.skipped} skipped '
    '(of ${summary.results.length}).',
  );
  return summary.exitCode;
}

String _seconds(Duration? duration) {
  if (duration == null) return '';
  final s = duration.inMilliseconds / 1000;
  return ' (${s.toStringAsFixed(1)}s)';
}

/// Parses [args]. Throws [FormatException] with a message on bad input.
///
/// [defaultRoot] is used when `--root` is absent.
RunnerOptions parseArgs(List<String> args, String defaultRoot) {
  var root = defaultRoot;
  var list = false;
  var dryRun = false;
  final only = <String>[];
  final dartCommand = <String>[];
  final flutterCommand = <String>[];
  String requireValue(String flag, int i) {
    if (i + 1 >= args.length) {
      throw FormatException('$flag needs a value');
    }
    return args[i + 1];
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--root':
        root = requireValue(arg, i);
        i++;
      case '--only':
        only.addAll(requireValue(arg, i).split(',').where((s) => s.isNotEmpty));
        i++;
      case '--list':
        list = true;
      case '--dry-run':
        dryRun = true;
      case '--dart-command':
        dartCommand.add(requireValue(arg, i));
        i++;
      case '--flutter-command':
        flutterCommand.add(requireValue(arg, i));
        i++;
      case '--help':
      case '-h':
        throw const FormatException('--help is handled before parsing');
      default:
        throw FormatException('Unknown argument: $arg');
    }
  }
  return RunnerOptions(
    root: root,
    only: only,
    list: list,
    dryRun: dryRun,
    dartCommand: dartCommand.isEmpty ? null : dartCommand,
    flutterCommand: flutterCommand.isEmpty ? null : flutterCommand,
  );
}

const usage = '''
FlutterPilot aggregate package test runner (fail-closed).

Usage: dart run tool/package_test_runner.dart [options]

  --root <dir>            Repository root (default: current directory).
  --only <a,b>            Run only these packages (name or path).
  --list                  List discovered packages and exit.
  --dry-run               Alias for --list.
  --dart-command <v>      Append <v> to the Dart test argv (repeatable; tests).
  --flutter-command <v>   Append <v> to the Flutter test argv (repeatable; tests).
  -h, --help              Show this help.

Exit code is 0 only when every test-bearing package passed. A missing
executable, an un-bootstrapped package, or any other setup problem fails the
gate; only a genuinely missing test directory is skipped.
''';

// ---------------------------------------------------------------------------
// Small helpers (kept here so the file needs no packages)
// ---------------------------------------------------------------------------

bool _isAbsolute(String path) {
  if (path.startsWith('/') || path.startsWith(r'\')) return true;
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String _relative(String root, String path) {
  final normalizedRoot = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  final absolute = File(path).absolute.path;
  if (absolute.startsWith(normalizedRoot)) {
    return absolute.substring(normalizedRoot.length).replaceAll('\\', '/');
  }
  return absolute.replaceAll('\\', '/');
}
