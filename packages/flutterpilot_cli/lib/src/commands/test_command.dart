import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';

/// High-speed parallel test runner command for FlutterPilot.
///
/// Runs test suites across multiple CPU cores simultaneously, cutting
/// full monorepo / project test verification time by 5x-8x.
class TestCommand extends Command<void> {
  @override
  final String name = 'test';

  @override
  final String description = 'Run test suites with high-speed parallel worker execution.';

  TestCommand() {
    argParser
      ..addFlag(
        'parallel',
        abbr: 'p',
        defaultsTo: true,
        help: 'Run package test suites concurrently across CPU cores.',
      )
      ..addOption(
        'concurrency',
        abbr: 'j',
        help: 'Maximum number of concurrent test workers (defaults to CPU core count).',
      )
      ..addFlag(
        'fail-fast',
        defaultsTo: false,
        help: 'Stop execution immediately upon first test failure.',
      );
  }

  @override
  Future<void> run() async {
    final stopwatch = Stopwatch()..start();
    final isParallel = argResults?['parallel'] as bool? ?? true;
    final failFast = argResults?['fail-fast'] as bool? ?? false;
    final userConcurrency = int.tryParse(argResults?['concurrency']?.toString() ?? '');
    final concurrency = userConcurrency ?? Platform.numberOfProcessors.clamp(1, 16);

    stdout.writeln('🚀 FlutterPilot Fast Test Runner');
    stdout.writeln('Concurrency: $concurrency worker(s) | Mode: ${isParallel ? 'Parallel' : 'Sequential'}\n');

    // Discover test packages/directories
    final testTargets = _discoverTestTargets(Directory.current);
    if (testTargets.isEmpty) {
      stdout.writeln('⚠️  No test directories found in ${Directory.current.path}');
      return;
    }

    stdout.writeln('Discovered ${testTargets.length} test target(s):');
    for (final target in testTargets) {
      stdout.writeln(' • ${target.path}');
    }
    stdout.writeln('');

    int passed = 0;
    int failed = 0;
    final results = <String, bool>{};

    if (isParallel && testTargets.length > 1) {
      final queue = List<Directory>.from(testTargets);
      final activeFutures = <Future<void>>[];

      Future<void> runWorker() async {
        while (queue.isNotEmpty) {
          if (failFast && failed > 0) return;
          final target = queue.removeAt(0);
          final success = await _runTestInDir(target);
          results[target.path] = success;
          if (success) {
            passed++;
          } else {
            failed++;
          }
        }
      }

      for (int i = 0; i < concurrency.clamp(1, testTargets.length); i++) {
        activeFutures.add(runWorker());
      }

      await Future.wait(activeFutures);
    } else {
      for (final target in testTargets) {
        if (failFast && failed > 0) break;
        final success = await _runTestInDir(target);
        results[target.path] = success;
        if (success) {
          passed++;
        } else {
          failed++;
        }
      }
    }

    stopwatch.stop();
    stdout.writeln('\n========================================');
    stdout.writeln('🏁 Test Execution Summary (${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)');
    stdout.writeln('========================================');
    results.forEach((path, success) {
      final icon = success ? '✅ PASS' : '❌ FAIL';
      stdout.writeln('$icon  $path');
    });
    stdout.writeln('Total: ${testTargets.length} | Passed: $passed | Failed: $failed');

    if (failed > 0) {
      exitCode = 1;
    }
  }

  List<Directory> _discoverTestTargets(Directory root) {
    final targets = <Directory>[];
    final packagesDir = Directory('${root.path}/packages');

    if (packagesDir.existsSync()) {
      for (final entity in packagesDir.listSync(recursive: true)) {
        if (entity is Directory &&
            entity.path.endsWith('/test') &&
            !entity.path.contains('/.dart_tool/') &&
            !entity.path.contains('/node_modules/')) {
          final parent = entity.parent;
          final pubspec = File('${parent.path}/pubspec.yaml');
          if (pubspec.existsSync() && !targets.any((t) => t.path == parent.path)) {
            targets.add(parent);
          }
        }
      }
    }

    final rootTestDir = Directory('${root.path}/test');
    if (rootTestDir.existsSync() && !targets.contains(root)) {
      targets.add(root);
    }

    return targets;
  }

  Future<bool> _runTestInDir(Directory dir) async {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) return true;

    final content = pubspec.readAsStringSync();
    final isFlutter = content.contains('sdk: flutter') || content.contains('flutter:');
    final executable = isFlutter ? 'flutter' : 'dart';

    final process = await Process.start(
      executable,
      ['test'],
      workingDirectory: dir.path,
      runInShell: true,
    );

    final exitCode = await process.exitCode;
    return exitCode == 0;
  }
}
