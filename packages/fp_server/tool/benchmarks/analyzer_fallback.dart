// Reload-error fallback measurement (task 10).
//
// FlutterPilot analyses whole files in exactly one place: after a reload fails
// in a way that looks like a compile error and the supervised `flutter run` log
// held no errors, `_compileErrors` runs `dart analyze --format=machine` on the
// files edited since the last good reload. Task 10 asks whether that fallback is
// frequent and slow enough to justify reusing a persistent analysis process.
//
// This harness measures the fallback's real components on a disposable Dart
// package, with no app, device or network: the changed-file scan, the log
// extraction, and one-shot `dart analyze` cold vs warm under identical files.
// It is a measurement + decision tool; it never changes server startup, adds a
// daemon, or edits product code.
//
// Run it from `packages/fp_server`:
//
//   dart run tool/benchmarks/analyzer_fallback.dart
//   dart run tool/benchmarks/analyzer_fallback.dart --trials 15 --json
//
// Results (metadata only) are written under the git-ignored
// `benchmark-results/`, alongside the task-09 startup report.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fp_server/src/reload_failure.dart';

import '../support/metrics.dart';

const _schemaVersion = 1;

/// One `dart analyze --format=machine` invocation's total wall time.
class AnalyzeTrial {
  AnalyzeTrial({
    required this.index,
    required this.cacheState,
    required this.totalMs,
    required this.ok,
    required this.errorCount,
    this.timedOut = false,
    this.error,
  });

  final int index;

  /// `cold` (the first run after the fixture was written) or `warm`.
  final String cacheState;
  final int totalMs;
  final bool ok;

  /// ERROR-severity findings parsed from the machine output.
  final int errorCount;
  final bool timedOut;
  final String? error;

  Map<String, dynamic> toJson() => {
    'index': index,
    'cacheState': cacheState,
    'totalMs': totalMs,
    'ok': ok,
    'errorCount': errorCount,
    'timedOut': timedOut,
    'error': error,
  };
}

Future<void> main(List<String> args) async {
  if (!File('bin/fp_server.dart').existsSync()) {
    stderr.writeln(
      'analyzer_fallback: run this from packages/fp_server '
      '(no bin/fp_server.dart in ${Directory.current.path}).',
    );
    exitCode = 1;
    return;
  }

  final trials = _intArg(args, '--trials', 15);
  final asJson = args.contains('--json');
  final resultsDir =
      _valueOf(args, '--out') ??
      '${Directory.current.path}${Platform.pathSeparator}benchmark-results';
  final fixtureRoot = '$resultsDir${Platform.pathSeparator}analyzer-fixture';

  stdout.writeln('Preparing a disposable analysis fixture (not timed)…');
  final fixture = _prepareFixture(fixtureRoot);

  try {
    // Fixed-cost components, measured in isolation.
    final since = DateTime.now().subtract(const Duration(hours: 1));
    final scan = _time(() {
      final files = dartFilesChangedSince(fixture.root, since);
      return files.length;
    }, trials);
    final logExtraction = _time(() {
      return compileErrorsIn(_sampleFlutterRunLog).length;
    }, trials);

    final clean = await _measureAnalyze(
      label: 'analyze-clean',
      executable: Platform.resolvedExecutable,
      root: fixture.root,
      files: fixture.cleanFiles,
      trials: trials,
      expectErrors: false,
    );
    final error = await _measureAnalyze(
      label: 'analyze-error',
      executable: Platform.resolvedExecutable,
      root: fixture.root,
      files: [...fixture.cleanFiles, fixture.brokenFile],
      trials: trials,
      expectErrors: true,
    );

    final cases = [clean, error];
    final decision = _decision(cases);

    final report = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'conditions': {
        'trialsPerCase': trials,
        'cacheStateLabeling':
            'the first analyze run after the fixture was written is "cold"; '
            'the rest are "warm"',
        'analyzedFiles': fixture.cleanFiles.length,
        'dart':
            '${Platform.resolvedExecutable} analyze --format=machine <files>',
      },
      'metadata': {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'fixture': {'files': fixture.cleanFiles.length, 'brokenFile': true},
        // Honest gap: peak resident memory of a one-shot `dart analyze` is not
        // measured here; only the process count (one per run, none retained).
        'memoryMeasured': false,
      },
      'fixedCosts': {
        'changedFileScanMs': scan,
        'logExtractionMs': logExtraction,
      },
      'cases': [for (final c in cases) c],
      'decision': decision,
    };

    Directory(resultsDir).createSync(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final path =
        '$resultsDir${Platform.pathSeparator}analyzer-fallback-$stamp.json';
    File(
      path,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));

    if (asJson) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    } else {
      _printHuman(report, path);
    }
    exitCode = cases.any((c) => c['ok'] != c['count']) ? 1 : 0;
  } finally {
    try {
      if (Directory(fixtureRoot).existsSync()) {
        Directory(fixtureRoot).deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

/// Runs `body` [times] and returns the min/median/p95 of each run in ms.
Map<String, dynamic> _time(int Function() body, int times) {
  final samples = <int>[];
  for (var i = 0; i < times; i++) {
    final clock = Stopwatch()..start();
    body();
    samples.add(clock.elapsedMilliseconds);
  }
  return summarizeMs(samples);
}

Future<Map<String, dynamic>> _measureAnalyze({
  required String label,
  required String executable,
  required String root,
  required List<String> files,
  required int trials,
  required bool expectErrors,
}) async {
  final results = <AnalyzeTrial>[];
  for (var i = 0; i < trials; i++) {
    final clock = Stopwatch()..start();
    ProcessResult result;
    var timedOut = false;
    String? error;
    try {
      result = await Process.run(executable, [
        'analyze',
        '--format=machine',
        ...files,
      ], workingDirectory: root).timeout(const Duration(seconds: 60));
    } on TimeoutException catch (e) {
      timedOut = true;
      error = e.toString();
      result = ProcessResult(0, -1, '', '');
    } catch (e) {
      error = e.toString();
      result = ProcessResult(0, -1, '', '');
    }
    final totalMs = clock.elapsedMilliseconds;
    final text = '${result.stdout}\n${result.stderr}';
    final errorCount = _machineErrorCount(text);
    final ok =
        !timedOut &&
        error == null &&
        (expectErrors ? errorCount > 0 : errorCount == 0);
    results.add(
      AnalyzeTrial(
        index: i,
        // The first run has no analyzer cache from the fixture's own files.
        cacheState: i == 0 ? 'cold' : 'warm',
        totalMs: totalMs,
        ok: ok,
        errorCount: errorCount,
        timedOut: timedOut,
        error: error,
      ),
    );
  }

  final cold = results.where((t) => t.cacheState == 'cold').toList();
  final warm = results.where((t) => t.cacheState == 'warm').toList();
  return {
    'caseId': label,
    'expectErrors': expectErrors,
    'count': results.length,
    'ok': results.where((t) => t.ok).length,
    'timedOut': results.where((t) => t.timedOut).length,
    'errors': results.where((t) => t.error != null).length,
    'coldMs': summarizeMs([for (final t in cold) t.totalMs]),
    'warmMs': summarizeMs([for (final t in warm) t.totalMs]),
    'allMs': summarizeMs([for (final t in results) t.totalMs]),
    'trials': [for (final t in results) t.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Decision
// ---------------------------------------------------------------------------

/// The proposed adoption gate (task 10 step 11): a reuse *prototype* must
/// improve the affected end-to-end median by at least 30% **and** 250 ms, with
/// no stale diagnostics and no unacceptable memory/process growth.
///
/// This harness can only time the current one-shot invocation and show whether
/// simply repeating it warms anything. It does **not** build a persistent
/// process (out of scope), so it reports the affected-path cost and a
/// not-claimed gate — never a reuse win it did not measure.
Map<String, dynamic> _decision(List<Map<String, dynamic>> cases) {
  final affected = summarizeMs([
    for (final c in cases)
      ...(c['trials'] as List).map((t) => (t as Map)['totalMs'] as int),
  ]);

  num? warmMedian(Map<String, dynamic> c) =>
      (c['warmMs'] as Map)['median'] as num?;
  num? coldMedian(Map<String, dynamic> c) =>
      (c['coldMs'] as Map)['median'] as num?;

  num? bestGain;
  double bestRatio = 0;
  String? bestCase;
  for (final c in cases) {
    final cold = coldMedian(c);
    final warm = warmMedian(c);
    if (cold == null || warm == null || cold == 0) continue;
    final gain = cold - warm;
    final ratio = gain / cold;
    if (gain > (bestGain ?? -1)) {
      bestGain = gain;
      bestRatio = ratio;
      bestCase = c['caseId'] as String;
    }
  }

  const gateMs = 250;
  const gateRatio = 0.30;
  final gain = bestGain ?? 0;

  return {
    'question':
        'Does reload-error analysis happen often and slowly enough to justify '
        'reusing a persistent analysis process?',
    'affectedPath':
        'dart analyze --format=machine on files changed by a '
        'compile-looking reload failure whose supervised log was silent',
    'affectedPathMedianMs': affected['median'],
    'oneShotColdToWarmGainMs': bestGain,
    'oneShotColdToWarmGainRatio': bestRatio,
    'oneShotWarmCase': bestCase,
    'oneShotWarmNote':
        'Repeating the current one-shot invocation does not warm it '
        '(${gain}ms, ${(bestRatio * 100).toStringAsFixed(0)}% cold-to-warm '
        'gap), so any reuse win would have to come from a persistent '
        'in-process analysis session — which this harness did not build or '
        'measure.',
    'gateMs': gateMs,
    'gateRatio': gateRatio,
    'reusePrototypeMeasured': false,
    'reuseGateClaimed': false,
    'incidenceMeasured': false,
    'incidenceNote':
        'Fallback incidence needs a running app and a reproducible edit/failure '
        'sequence; no app was available on this workstation, so only the '
        'affected-path cost is measured, not how often it is paid (both '
        'denominators are unmeasured).',
    'bottleneck':
        'The fallback costs one ~${affected['median']}ms cold analysis per '
        'compile-looking reload failure whose log was silent; the one-shot '
        'invocation does not warm, and how often it runs was not measurable '
        'here.',
    'recommendation':
        'Retain log-first with the bounded one-shot analyzer fallback and '
        'improve guidance toward the companion `dart mcp-server` analysis '
        'tools. Do not add a FlutterPilot-owned analysis daemon: the reuse gate '
        'is not claimed (no prototype measured), the fallback is rare, and the '
        'companion already owns this surface.',
    'companionOverlap':
        'The installed `dart mcp-server` already exposes an `analyze_files` '
        'feature and an `lsp` feature (verified by tools/list, the schemas are '
        'authoritative). A handoff/guidance path avoids a duplicate daemon.',
  };
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

class _Fixture {
  _Fixture(this.root, this.cleanFiles, this.brokenFile);
  final String root;
  final List<String> cleanFiles;
  final String brokenFile;
}

_Fixture _prepareFixture(String root) {
  final dir = Directory(root);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  Directory('$root${Platform.pathSeparator}lib').createSync(recursive: true);
  File('$root${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
    'name: fp_analyzer_fixture\n'
    'environment:\n'
    "  sdk: '>=3.0.0 <4.0.0'\n",
  );
  final clean = <String>[];
  for (var i = 0; i < 20; i++) {
    final path =
        '$root${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}f$i.dart';
    File(path).writeAsStringSync('int f$i() => $i;\n');
    clean.add(path);
  }
  final broken =
      '$root${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}broken.dart';
  File(broken).writeAsStringSync('int broken() => undefinedIdentifier;\n');
  return _Fixture(root, clean, broken);
}

/// A representative `flutter run` compile-error block (what `compileErrorsIn`
/// extracts), used to time the pure extraction step.
const _sampleFlutterRunLog = '''
Building flutter tool...
lib/main.dart:42:5: Error: Undefined name 'counterr'.
  counterr++;
  ^^^^^^^^
lib/main.dart:43:3: Error: Method not found: 'setState'.
  setState(() {});
  ^^^^^^^^
Error: Failed to recompile.
''';

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/// Number of ERROR-severity findings in `dart analyze --format=machine` output,
/// mirroring what [analyzerErrorsIn] reduces to actionable errors.
int _machineErrorCount(String output) {
  var count = 0;
  for (final line in output.split('\n')) {
    final parts = line.split('|');
    if (parts.length >= 8 && parts[0] == 'ERROR') count++;
  }
  return count;
}

String? _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

int _intArg(List<String> args, String flag, int fallback) =>
    int.tryParse(_valueOf(args, flag) ?? '') ?? fallback;

void _printHuman(Map<String, dynamic> report, String path) {
  final env = report['metadata'] as Map<String, dynamic>;
  final fixed = report['fixedCosts'] as Map<String, dynamic>;
  stdout.writeln('FlutterPilot analyzer-fallback measurement · ${env['os']}');
  stdout.writeln(
    'changed-file scan: ${_fmt(fixed['changedFileScanMs'] as Map)} ms; '
    'log extraction: ${_fmt(fixed['logExtractionMs'] as Map)} ms',
  );
  for (final c in report['cases'] as List) {
    final m = c as Map<String, dynamic>;
    stdout.writeln(
      '${m['caseId']}: cold ${_fmt(m['coldMs'] as Map)} ms, '
      'warm ${_fmt(m['warmMs'] as Map)} ms '
      '(ok ${m['ok']}/${m['count']}, timeouts ${m['timedOut']})',
    );
  }
  final d = report['decision'] as Map<String, dynamic>;
  stdout.writeln('affected-path median: ${d['affectedPathMedianMs']} ms');
  stdout.writeln('reuse-gate claimed: ${d['reuseGateClaimed']}');
  stdout.writeln('bottleneck: ${d['bottleneck']}');
  stdout.writeln('recommendation: ${d['recommendation']}');
  stdout.writeln('report: $path');
}

String _fmt(Map metric) {
  if ((metric['n'] as int? ?? 0) == 0) return 'n/a';
  return '${(metric['median'] as num).toStringAsFixed(0)}'
      '(p95 ${metric['p95']})';
}
