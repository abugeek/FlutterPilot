// Startup and MCP-readiness benchmark (task 09).
//
// Measures what a user actually waits for, on one monotonic clock:
//
//   spawn → MCP initialize complete → tools/list complete → first useful read
//   (→ first connected-app read, when a live app is attached)
//
// It is **not** an approval to reorder server startup: `lib/fp_server.dart`'s
// `start()` awaits `_connectToVmService()` before connecting the stdio
// transport, and this harness exists to measure whether that ordering costs a
// user anything. The deliverable is a decision, including "no change needed".
//
// It reuses task 03's helpers: `StdoutHygiene`/`BoundedStderr`
// (`tool/support/stdio_hygiene.dart`) for strict framing and bounded redacted
// stderr, and `killProcessTree`/`isProcessAlive`
// (`tool/support/process_tree.dart`) so a timed-out probe never leaves a
// process behind and cleanup can be asserted.
//
// Run it from `packages/fp_server`:
//
//   dart run tool/benchmarks/startup_benchmark.dart --mode both --case no-app
//   dart run tool/benchmarks/startup_benchmark.dart --case unavailable
//   dart run tool/benchmarks/startup_benchmark.dart --case connected --uri <vm-uri>
//
// Results (metadata only) are written under a gitignored `benchmark-results/`.
// Exit code is 0 when every measured trial of every case succeeded, 1 otherwise.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';

import '../support/metrics.dart';
import '../support/process_tree.dart';
import '../support/stdio_hygiene.dart';

/// Which server build a trial launches.
enum LaunchMode {
  /// `dart run bin/fp_server.dart` (JIT, source).
  source,

  /// The AOT executable `dart compile exe` produced.
  aot;

  static LaunchMode? byName(String name) => switch (name) {
    'source' => source,
    'aot' => aot,
    _ => null,
  };
}

/// The app state a case measures.
enum AppState {
  /// No running app; explicit project-root discovery finds nothing.
  noApp,

  /// An explicitly configured VM endpoint where nothing answers.
  unavailable,

  /// A healthy pre-running fixture, addressed by its VM Service URI.
  connected;

  static AppState? byName(String name) => switch (name) {
    'no-app' => noApp,
    'unavailable' => unavailable,
    'connected' => connected,
    _ => null,
  };

  String get id => switch (this) {
    AppState.noApp => 'no-app',
    AppState.unavailable => 'unavailable',
    AppState.connected => 'connected',
  };
}

/// How to start one server process.
class LaunchSpec {
  const LaunchSpec({
    required this.label,
    required this.executable,
    required this.args,
    this.workingDirectory,
    this.environment = const {},
  });

  /// A short identity for reports, e.g. `source` or `aot`.
  final String label;
  final String executable;
  final List<String> args;
  final String? workingDirectory;

  /// Extra environment entries merged over the parent environment.
  final Map<String, String> environment;

  /// The argv a human would type, for the report (paths redacted later).
  List<String> get displayArgv => [executable, ...args];

  /// A copy with a different [label] (used when comparing builds).
  LaunchSpec relabelled(String label) => LaunchSpec(
    label: label,
    executable: executable,
    args: args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

/// The one monotonic measurement of a single launch: all timings are
/// milliseconds since immediately before the process was spawned.
class TrialTimings {
  TrialTimings({
    required this.index,
    required this.cacheState,
    required this.ok,
    required this.timedOut,
    this.timedOutStage,
    this.error,
    this.protocolVersion,
    this.toolCount,
    this.readUsable,
    this.hygieneClean,
    this.stdoutLines,
    this.exited,
    this.cleanupConfirmed,
    this.spawnToInitializeMs,
    this.spawnToToolsListMs,
    this.spawnToReadMs,
    this.spawnToConnectedReadMs,
    this.totalMs,
    this.stderrTail = '',
  });

  final int index;

  /// `cold` (no warm-up), `first-trial` (the first measured launch after a
  /// warm-up), `warmup` (unmeasured) or `warm`.
  final String cacheState;
  final bool ok;
  final bool timedOut;
  final String? timedOutStage;
  final String? error;
  final String? protocolVersion;
  final int? toolCount;

  /// Whether the representative read returned a usable (non-error) result.
  final bool? readUsable;
  final bool? hygieneClean;
  final int? stdoutLines;
  final bool? exited;
  final bool? cleanupConfirmed;
  final int? spawnToInitializeMs;
  final int? spawnToToolsListMs;
  final int? spawnToReadMs;
  final int? spawnToConnectedReadMs;
  final int? totalMs;

  /// The last bounded, redacted stderr line (diagnosis only).
  final String stderrTail;

  Map<String, dynamic> toJson() => {
    'index': index,
    'cacheState': cacheState,
    'ok': ok,
    'timedOut': timedOut,
    'timedOutStage': timedOutStage,
    'error': error,
    'protocolVersion': protocolVersion,
    'toolCount': toolCount,
    'readUsable': readUsable,
    'hygieneClean': hygieneClean,
    'stdoutLines': stdoutLines,
    'exited': exited,
    'cleanupConfirmed': cleanupConfirmed,
    'timings': {
      'spawnToInitializeMs': spawnToInitializeMs,
      'spawnToToolsListMs': spawnToToolsListMs,
      'spawnToReadMs': spawnToReadMs,
      'spawnToConnectedReadMs': spawnToConnectedReadMs,
      'totalMs': totalMs,
    },
    'stderrTail': stderrTail,
  };
}

/// A live server subprocess spoken to over stdio, on one clock started
/// immediately before the process was spawned.
class StdioBenchmarkSession {
  StdioBenchmarkSession._(this._process, this._clock) {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdout);
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderr.add);
    _exitFuture = _process.exitCode.then((value) {
      _exitCode = value;
      _exited = true;
      return value;
    });
    // A process that dies before any reply must not hang a waiting request.
    unawaited(_exitFuture.then((_) => _failPending()));
  }

  /// Starts [spec] and begins the clock immediately before the spawn.
  static Future<StdioBenchmarkSession> start(LaunchSpec spec) async {
    final clock = Stopwatch()..start();
    final process = await Process.start(
      spec.executable,
      spec.args,
      workingDirectory: spec.workingDirectory,
      environment: spec.environment,
      includeParentEnvironment: true,
    );
    return StdioBenchmarkSession._(process, clock);
  }

  final Process _process;
  final Stopwatch _clock;
  late final StreamSubscription<String> _stdoutSub;
  late final StreamSubscription<String> _stderrSub;
  late final Future<int> _exitFuture;

  /// Strict stdout framing (task 03): a banner or malformed line is recorded.
  final StdoutHygiene hygiene = StdoutHygiene();

  /// A bounded, redacted copy of stderr, for diagnosis only.
  final BoundedStderr stderr = BoundedStderr();

  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;
  bool _exited = false;
  int? _exitCode;

  int get pid => _process.pid;
  bool get exited => _exited;
  int? get exitCode => _exitCode;

  /// Milliseconds since immediately before the spawn.
  int get elapsedMs => _clock.elapsedMilliseconds;

  /// Sends `initialize` and the `notifications/initialized` follow-up; returns
  /// the initialize response.
  Future<Map<String, dynamic>> initialize(Duration deadline) async {
    final response = await request('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': {
        'roots': <String, dynamic>{},
        'sampling': <String, dynamic>{},
      },
      'clientInfo': {
        'name': 'flutterpilot-startup-benchmark',
        'version': '1.0.0',
      },
    }, deadline);
    _write({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    return response;
  }

  /// Sends a request and completes with its JSON-RPC response, or throws a
  /// [TimeoutException] after [deadline].
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
    Duration deadline,
  ) {
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return completer.future.timeout(deadline);
  }

  /// The whole `tools/call` response for [name].
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments,
    Duration deadline,
  ) => request('tools/call', {'name': name, 'arguments': arguments}, deadline);

  /// Closes the transport and kills the whole process tree; resolves once the
  /// process has exited (so cleanup is confirmed, not assumed).
  Future<void> kill() async {
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    if (!_exited) {
      await killProcessTree(_process);
    }
    await _exitFuture;
  }

  void _onStdout(String line) {
    final decoded = hygiene.add(line);
    if (decoded == null) return;
    final id = decoded['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(decoded);
        return;
      }
    }
    // The server's own roots/list request: answer it so it is not left waiting.
    if (decoded.containsKey('method') && id != null) {
      _write({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'roots': <Object>[]},
      });
    }
  }

  void _failPending() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('server exited before replying'));
      }
    }
    _pending.clear();
  }

  void _write(Map<String, dynamic> message) =>
      _process.stdin.writeln(jsonEncode(message));
}

/// Runs one timed trial of [launch], reading [readTool] as the representative
/// request and optionally [connectedReadTool] once a live app is attached.
Future<TrialTimings> runTrial({
  required LaunchSpec launch,
  required String readTool,
  String? connectedReadTool,
  Duration initializeTimeout = const Duration(seconds: 30),
  Duration requestTimeout = const Duration(seconds: 30),
  Duration totalTimeout = const Duration(seconds: 90),
  int index = 0,
  String cacheState = 'warm',
}) async {
  final session = await StdioBenchmarkSession.start(launch);
  int? tInit;
  int? tTools;
  int? tRead;
  int? tConnected;
  var timedOut = false;
  String? timedOutStage;
  String? error;
  String? protocolVersion;
  int? toolCount;
  bool? readUsable;

  Duration remaining(Duration stage) {
    final left = totalTimeout - Duration(milliseconds: session.elapsedMs);
    if (left <= Duration.zero) return const Duration(milliseconds: 1);
    return left < stage ? left : stage;
  }

  var stage = 'initialize';
  try {
    final init = await session.initialize(remaining(initializeTimeout));
    tInit = session.elapsedMs;
    protocolVersion = '${(init['result'] as Map?)?['protocolVersion']}';

    stage = 'tools/list';
    final tools = await session.request(
      'tools/list',
      null,
      remaining(requestTimeout),
    );
    tTools = session.elapsedMs;
    toolCount = ((tools['result'] as Map?)?['tools'] as List?)?.length;

    stage = 'read';
    final read = await session.callTool(
      readTool,
      const {},
      remaining(requestTimeout),
    );
    tRead = session.elapsedMs;
    readUsable = (read['result'] as Map?)?['isError'] != true;

    if (connectedReadTool != null) {
      stage = 'connected read';
      final connected = await session.callTool(
        connectedReadTool,
        const {},
        remaining(requestTimeout),
      );
      tConnected = session.elapsedMs;
      readUsable =
          readUsable && (connected['result'] as Map?)?['isError'] != true;
    }
  } on TimeoutException {
    timedOut = true;
    timedOutStage = stage;
  } catch (e) {
    error = e.toString();
  }

  final total = session.elapsedMs;
  final exited = session.exited;
  await session.kill();
  final cleanupConfirmed = !(await isProcessAlive(session.pid));
  final stderrTail = session.stderr.lines.isEmpty
      ? ''
      : session.stderr.lines.last;

  final ok =
      !timedOut && error == null && readUsable == true && session.hygiene.clean;
  return TrialTimings(
    index: index,
    cacheState: cacheState,
    ok: ok,
    timedOut: timedOut,
    timedOutStage: timedOutStage,
    error: error,
    protocolVersion: protocolVersion,
    toolCount: toolCount,
    readUsable: readUsable,
    hygieneClean: session.hygiene.clean,
    stdoutLines: session.hygiene.lines,
    exited: exited,
    cleanupConfirmed: cleanupConfirmed,
    spawnToInitializeMs: tInit,
    spawnToToolsListMs: tTools,
    spawnToReadMs: tRead,
    spawnToConnectedReadMs: tConnected,
    totalMs: total,
    stderrTail: stderrTail,
  );
}

/// One case's trials (all the same launch mode, app state and options).
class TrialSet {
  TrialSet({
    required this.caseId,
    required this.launchMode,
    required this.appState,
    required this.staticTools,
    required this.trials,
  });

  final String caseId;
  final LaunchMode launchMode;
  final AppState appState;
  final bool staticTools;
  final List<TrialTimings> trials;

  /// The metrics a report aggregates, in order.
  static const metricNames = [
    'spawnToInitializeMs',
    'spawnToToolsListMs',
    'spawnToReadMs',
    'spawnToConnectedReadMs',
    'totalMs',
  ];

  /// The warm trials (the first measured trial is reported separately).
  List<TrialTimings> get warmTrials =>
      trials.where((t) => t.cacheState == 'warm').toList();

  /// The first measured (cold-ish) trial, when there was one.
  TrialTimings? get firstTrial => _firstOrNull(
    trials.where(
      (t) => t.cacheState == 'first-trial' || t.cacheState == 'cold',
    ),
  );

  Map<String, dynamic> toJson() => {
    'caseId': caseId,
    'launchMode': launchMode.name,
    'appState': appState.id,
    'staticTools': staticTools,
    'count': trials.length,
    'ok': trials.where((t) => t.ok).length,
    'timedOut': trials.where((t) => t.timedOut).length,
    'errors': trials.where((t) => t.error != null).length,
    'timeoutRate': _rate(trials.where((t) => t.timedOut).length),
    'errorRate': _rate(trials.where((t) => t.error != null).length),
    'firstTrial': firstTrial?.toJson(),
    'metrics': {
      for (final name in metricNames)
        name: _metric(
          warmTrials.map((t) => _metricOf(t, name)).whereType<int>().toList(),
        ),
    },
    'trials': [for (final trial in trials) trial.toJson()],
  };

  double _rate(int count) => trials.isEmpty ? 0 : count / trials.length;

  static int? _metricOf(TrialTimings trial, String name) => switch (name) {
    'spawnToInitializeMs' => trial.spawnToInitializeMs,
    'spawnToToolsListMs' => trial.spawnToToolsListMs,
    'spawnToReadMs' => trial.spawnToReadMs,
    'spawnToConnectedReadMs' => trial.spawnToConnectedReadMs,
    'totalMs' => trial.totalMs,
    _ => null,
  };

  /// Median, p95 (nearest rank) and range for [values]; `{n: 0}` when empty.
  static Map<String, dynamic> _metric(List<int> values) => summarizeMs(values);
}

// ---------------------------------------------------------------------------
// Report metadata
// ---------------------------------------------------------------------------

/// Environment and server identities for the report, with paths redacted.
Future<Map<String, dynamic>> reportMetadata({
  required String packageRoot,
  required LaunchSpec sourceLaunch,
  LaunchSpec? aotLaunch,
  String? fixtureId,
}) async {
  return {
    'environment': {
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'dart': await _firstLine([Platform.resolvedExecutable, '--version']),
      'flutter': await _flutterVersion(),
    },
    'server': {
      'revision': await _firstLine([
        'git',
        'rev-parse',
        '--short',
        'HEAD',
      ], workingDirectory: packageRoot),
      'libHash': await _sourceHash(packageRoot),
      'sourceFreshness': await _sourceFreshness(packageRoot),
      'sourceArgv': _redactArgv(sourceLaunch.displayArgv, packageRoot),
      'aotArgv': aotLaunch == null
          ? null
          : _redactArgv(aotLaunch.displayArgv, packageRoot),
      'aotExecutableHash': aotLaunch == null
          ? null
          : await _fileHash(aotLaunch.executable),
      'aotCompilerFlags': aotLaunch == null ? null : 'dart compile exe',
      'workingDirectory': _scrubPath(packageRoot, packageRoot),
    },
    'fixture': {'id': fixtureId ?? 'none'},
  };
}

/// A sha256 over the contents of every Dart file under `bin/` and `lib/`, so a
/// report names the exact source it measured. Sorted for determinism.
Future<String?> _sourceHash(String packageRoot) async {
  try {
    final dirs = ['bin', 'lib']
        .map((d) => Directory('$packageRoot${Platform.pathSeparator}$d'))
        .where((d) => d.existsSync())
        .toList();
    final files = [
      for (final dir in dirs)
        ...dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ]..sort((a, b) => a.path.compareTo(b.path));
    final bytes = BytesBuilder(copy: false);
    for (final file in files) {
      bytes
        ..add(utf8.encode(file.path))
        ..add([0])
        ..add(await file.readAsBytes())
        ..add([0]);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  } catch (_) {
    return null;
  }
}

/// Whether `lib/` or `bin/` has uncommitted changes: a dirty tree means the
/// measured source is not exactly the reported revision.
Future<String> _sourceFreshness(String packageRoot) async {
  try {
    final result = await Process.run('git', [
      'status',
      '--porcelain',
      '--',
      'lib',
      'bin',
    ], workingDirectory: packageRoot);
    final dirty = '${result.stdout}'.trim().isNotEmpty;
    return dirty ? 'dirty (uncommitted changes under lib/ or bin/)' : 'clean';
  } catch (_) {
    return 'unknown';
  }
}

Future<String?> _fileHash(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  } catch (_) {
    return null;
  }
}

/// Replaces the user's home directory with `~`, so a report never carries a
/// private path.
String redactPath(String path) {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty && path.startsWith(home)) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

/// Redacts a VM Service URI's authentication token (the path segment after the
/// port). Anything that is not a URI passes through [redactPath].
String redactVmUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    return redactPath(value);
  }
  final segments = uri.pathSegments;
  final redacted = segments.isEmpty
      ? uri.path
      : '/${segments.first == 'ws' ? 'ws' : '<token>'}'
            '${segments.length > 1 ? '/…' : ''}';
  return '${uri.scheme}://${uri.host}:${uri.port}$redacted';
}

/// Collapses the measured package's own location to `<package>`, so a shared
/// report names the layout without the absolute path of the machine that ran it,
/// then applies the home-directory redaction.
String _scrubPath(String value, String packageRoot) {
  if (value == packageRoot) return '<package>';
  final prefix = '$packageRoot${Platform.pathSeparator}';
  if (value.startsWith(prefix)) {
    return '<package>${value.substring(packageRoot.length)}';
  }
  return redactPath(value);
}

List<String> _redactArgv(List<String> argv, String packageRoot) {
  final out = <String>[];
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (arg == '-u' || arg == '--uri') {
      out.add(arg);
      if (i + 1 < argv.length) out.add(redactVmUri(argv[++i]));
      continue;
    }
    out.add(
      arg.contains(Platform.pathSeparator) ? _scrubPath(arg, packageRoot) : arg,
    );
  }
  return out;
}

/// `flutter` is a batch file on Windows, which `Process.run` cannot execute by
/// name; try the executable and then the `.bat` shim.
Future<String> _flutterVersion() async {
  final value = await _firstLine(['flutter', '--version']);
  if (value != 'unknown') return value;
  if (Platform.isWindows) return _firstLine(['flutter.bat', '--version']);
  return value;
}

Future<String> _firstLine(
  List<String> command, {
  String? workingDirectory,
  String fallback = 'unknown',
}) async {
  try {
    final result = await Process.run(
      command.first,
      command.sublist(1),
      workingDirectory: workingDirectory,
      // Decode tool output as UTF-8; the system codepage mangles `•`.
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 60));
    final text = '${result.stdout}${result.stderr}'.trim();
    return text.isEmpty ? fallback : text.split('\n').first.trim();
  } catch (_) {
    return fallback;
  }
}

/// The decision this task exists to produce, computed from the case summaries.
///
/// It only *recommends*; reordering startup needs separate approval and a
/// repeat of identical trials.
Map<String, dynamic> computeDecision(List<TrialSet> sets) {
  num? metricOf(String caseId, String metric, String key) {
    final set = _firstOrNull(sets.where((s) => s.caseId == caseId));
    final value =
        (set?.toJson()['metrics'] as Map?)?[metric] as Map<String, dynamic>?;
    return value?[key] as num?;
  }

  final noApp =
      metricOf('no-app/source', 'spawnToToolsListMs', 'median') ??
      metricOf('no-app/aot', 'spawnToToolsListMs', 'median');
  final unavailable =
      metricOf('unavailable/source', 'spawnToToolsListMs', 'median') ??
      metricOf('unavailable/aot', 'spawnToToolsListMs', 'median');

  String bottleneck;
  bool recommend = false;
  String rationale;
  if (noApp == null || unavailable == null) {
    bottleneck = 'insufficient data';
    rationale =
        'The no-app and unavailable cases did not both produce usable medians, '
        'so no readiness comparison can be made.';
  } else {
    final delta = unavailable - noApp;
    final ratio = noApp == 0 ? double.infinity : delta / noApp;
    if (delta >= 200 && ratio >= 0.20) {
      bottleneck =
          'discovery/VM connection dominates MCP readiness '
          '(+${delta.toStringAsFixed(0)} ms, '
          '${(ratio * 100).toStringAsFixed(0)}%)';
      recommend = true;
      rationale =
          'An unreachable VM endpoint delays spawn-to-tools/list by '
          '${delta.toStringAsFixed(0)} ms over the no-app median. This is a '
          'candidate for a separately approved change to start MCP before '
          'background discovery, but the change must not weaken first-result '
          'honesty, reconnect races, process cleanup or client compatibility.';
    } else {
      bottleneck = 'MCP readiness is not dominated by the connection';
      rationale =
          'The unavailable-endpoint median is within ${delta.toStringAsFixed(0)}'
          ' ms (${(ratio * 100).toStringAsFixed(0)}%) of the no-app median: '
          'below the proposed review threshold (200 ms and 20%), so the current '
          'startup ordering is acceptable and no change is recommended.';
    }
  }

  return {
    'question': 'Does discovery/VM connection dominate MCP readiness?',
    'spawnToToolsListMedianMs': {'no-app': noApp, 'unavailable': unavailable},
    'spawnToInitializeMedianMs': {
      'no-app': metricOf('no-app/source', 'spawnToInitializeMs', 'median'),
      'unavailable': metricOf(
        'unavailable/source',
        'spawnToInitializeMs',
        'median',
      ),
    },
    'thresholdMs': 200,
    'thresholdRatio': 0.20,
    'bottleneck': bottleneck,
    'startupOrderingChangeRecommended': recommend,
    'rationale': rationale,
  };
}

// ---------------------------------------------------------------------------
// The CLI
// ---------------------------------------------------------------------------

const _schemaVersion = 1;

Future<void> main(List<String> args) async {
  final modeArg = _valueOf(args, '--mode') ?? 'both';
  final caseArg = _valueOf(args, '--case') ?? 'no-app';
  final trials = int.tryParse(_valueOf(args, '--trials') ?? '') ?? 20;
  final warmup = int.tryParse(_valueOf(args, '--warmup') ?? '') ?? 1;
  final rootArg = _valueOf(args, '--root');
  final uriArg = _valueOf(args, '--uri');
  final fixtureId = _valueOf(args, '--fixture-id');
  final outArg = _valueOf(args, '--out');
  final aotArg = _valueOf(args, '--aot');
  final asJson = args.contains('--json');
  final listAll = args.contains('--list-all');
  final staticTools = args.contains('--static-tools');
  final initializeTimeout = Duration(
    seconds: int.tryParse(_valueOf(args, '--initialize-timeout') ?? '') ?? 30,
  );
  final requestTimeout = Duration(
    seconds: int.tryParse(_valueOf(args, '--request-timeout') ?? '') ?? 30,
  );

  if (!File('bin/fp_server.dart').existsSync()) {
    stderr.writeln(
      'startup_benchmark: run this from packages/fp_server '
      '(no bin/fp_server.dart in ${Directory.current.path}).',
    );
    exitCode = 1;
    return;
  }

  final modes = modeArg == 'both'
      ? [LaunchMode.source, LaunchMode.aot]
      : [LaunchMode.byName(modeArg) ?? LaunchMode.source];
  final List<AppState> states;
  if (caseArg == 'all') {
    states = [AppState.noApp, AppState.unavailable];
  } else {
    final parsed = AppState.byName(caseArg);
    if (parsed == null) {
      stderr.writeln('startup_benchmark: unknown --case $caseArg');
      exitCode = 1;
      return;
    }
    states = [parsed];
  }
  if (states.contains(AppState.connected) && uriArg == null) {
    stderr.writeln(
      'startup_benchmark: --case connected needs --uri <vm-service-uri> from a '
      'pre-running FlutterPilot app.',
    );
    exitCode = 1;
    return;
  }

  final packageRoot = Directory.current.path;
  final resultsDir =
      outArg ?? '$packageRoot${Platform.pathSeparator}benchmark-results';
  final root = rootArg ?? _emptyRoot(resultsDir);
  final unavailableUri = await _reservedUri();
  final dartExe = Platform.resolvedExecutable;

  LaunchSpec spec(LaunchMode mode, AppState state, {String? aotExe}) => _spec(
    mode: mode,
    executable: mode == LaunchMode.source ? dartExe : aotExe!,
    packageRoot: packageRoot,
    state: state,
    root: root,
    unavailableUri: unavailableUri,
    uri: uriArg,
    staticTools: staticTools,
    listAll: listAll,
  );

  // Compile the AOT executable once, outside every timed trial.
  String? aotExe;
  if (modes.contains(LaunchMode.aot)) {
    aotExe =
        aotArg ??
        '$resultsDir${Platform.pathSeparator}build'
            '${Platform.pathSeparator}fp_server'
            '${Platform.isWindows ? '.exe' : ''}';
    if (aotArg != null && !File(aotArg).existsSync()) {
      stderr.writeln('startup_benchmark: --aot not found: $aotArg');
      exitCode = 1;
      return;
    }
    if (aotArg == null) {
      // Progress goes to stderr so `--json` keeps stdout a single JSON document.
      stderr.writeln('Compiling the server (dart compile exe, not timed)…');
      // `dart compile exe -o` does not create the output directory.
      Directory(File(aotExe).parent.path).createSync(recursive: true);
      final compiled = await Process.run(dartExe, [
        'compile',
        'exe',
        'bin/fp_server.dart',
        '-o',
        aotExe,
      ], workingDirectory: packageRoot);
      if (compiled.exitCode != 0) {
        stderr
          ..writeln('startup_benchmark: compilation failed')
          ..writeln('${compiled.stdout}${compiled.stderr}');
        exitCode = 1;
        return;
      }
    }
  }

  final baselineSource = spec(LaunchMode.source, AppState.noApp);
  final baselineAot = aotExe == null
      ? null
      : spec(LaunchMode.aot, AppState.noApp, aotExe: aotExe);

  final sets = <TrialSet>[];
  var anyFailure = false;
  final report = <String, dynamic>{
    'schemaVersion': _schemaVersion,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'conditions': {
      'trialsPerCase': trials,
      'warmupPerCase': warmup,
      'interleavedAcrossLaunchModes': modes.length > 1,
      'cacheStateLabeling':
          'first measured trial is "first-trial" (a warm-up ran before it); '
          '"cold" only when --warmup 0',
      'initializeTimeoutSec': initializeTimeout.inSeconds,
      'requestTimeoutSec': requestTimeout.inSeconds,
      'listAllTools': listAll,
      'staticTools': staticTools,
      'unavailableEndpoint': redactVmUri(unavailableUri),
    },
    'metadata': await reportMetadata(
      packageRoot: packageRoot,
      sourceLaunch: baselineSource,
      aotLaunch: baselineAot,
      fixtureId: fixtureId,
    ),
    'cases': <Map<String, dynamic>>[],
    'decision': <String, dynamic>{},
  };

  try {
    for (final state in states) {
      final readTool = state == AppState.connected
          ? 'get_app_summary'
          : 'list_connected_devices';
      final connectedReadTool = state == AppState.connected
          ? 'get_app_summary'
          : null;

      final perMode = <LaunchMode, List<TrialTimings>>{
        for (final mode in modes) mode: <TrialTimings>[],
      };

      // Warm-up first (unmeasured), interleaving launch modes so OS scheduling
      // drifts do not favour one build.
      for (final mode in modes) {
        final launch = spec(mode, state, aotExe: aotExe);
        for (var i = 0; i < warmup; i++) {
          final trial = await runTrial(
            launch: launch,
            readTool: readTool,
            connectedReadTool: connectedReadTool,
            initializeTimeout: initializeTimeout,
            requestTimeout: requestTimeout,
            index: -1,
            cacheState: 'warmup',
          );
          if (!trial.ok) {
            stderr.writeln(
              'startup_benchmark: warm-up failed for ${state.id}/${mode.name}: '
              '${trial.timedOut ? "timeout at ${trial.timedOutStage}" : trial.error}. '
              'Aborting before the measured trials (a broken fixture must not '
              'be run $trials times).',
            );
            exitCode = 1;
            return;
          }
        }
      }
      for (var i = 0; i < trials; i++) {
        for (final mode in modes) {
          final launch = spec(mode, state, aotExe: aotExe);
          final trial = await runTrial(
            launch: launch,
            readTool: readTool,
            connectedReadTool: connectedReadTool,
            initializeTimeout: initializeTimeout,
            requestTimeout: requestTimeout,
            index: i,
            cacheState: i == 0 ? (warmup > 0 ? 'first-trial' : 'cold') : 'warm',
          );
          perMode[mode]!.add(trial);
          if (!trial.ok) anyFailure = true;
        }
      }
      for (final mode in modes) {
        final set = TrialSet(
          caseId: '${state.id}/${mode.name}',
          launchMode: mode,
          appState: state,
          staticTools: staticTools,
          trials: perMode[mode]!,
        );
        sets.add(set);
        report['cases'] = [...(report['cases'] as List), set.toJson()];
      }
    }
  } finally {
    try {
      if (rootArg == null && Directory(root).existsSync()) {
        Directory(root).deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  report['decision'] = computeDecision(sets);

  Directory(resultsDir).createSync(recursive: true);
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '');
  final reportPath = '$resultsDir${Platform.pathSeparator}startup-$stamp.json';
  File(
    reportPath,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));

  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else {
    _printHuman(report, reportPath);
  }
  exitCode = anyFailure ? 1 : 0;
}

/// Builds one launch spec for [mode] in app state [state].
LaunchSpec _spec({
  required LaunchMode mode,
  required String executable,
  required String packageRoot,
  required AppState state,
  required String root,
  required String unavailableUri,
  String? uri,
  required bool staticTools,
  required bool listAll,
}) {
  return LaunchSpec(
    label: mode.name,
    executable: executable,
    args: [
      if (mode == LaunchMode.source) ...['run', 'bin/fp_server.dart'],
      '--log-level',
      'severe',
      '--no-call-log',
      if (staticTools) '--static-tools',
      // Explicit project-root discovery vs explicit URI, kept separate so
      // discovery cost is never confused with VM handshake cost.
      ...switch (state) {
        AppState.noApp => ['-p', root],
        AppState.unavailable => ['-p', root, '-u', unavailableUri],
        AppState.connected => ['-u', uri!],
      },
    ],
    workingDirectory: packageRoot,
    environment: {if (listAll) 'FLUTTERPILOT_LIST_ALL_TOOLS': '1'},
  );
}

/// An empty directory used as the explicit project root, so discovery is cheap
/// and isolated from unrelated apps.
String _emptyRoot(String resultsDir) {
  final dir = '$resultsDir${Platform.pathSeparator}empty-root';
  Directory(dir).createSync(recursive: true);
  return dir;
}

/// A reserved local endpoint nothing listens on: bind a port, read it, close
/// the socket, and return an `http://` VM-service-shaped URI for that port.
Future<String> _reservedUri() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  final token = math.Random().nextInt(1 << 32).toRadixString(16);
  return 'http://127.0.0.1:$port/$token/';
}

String? _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

void _printHuman(Map<String, dynamic> report, String reportPath) {
  final metadata = report['metadata'] as Map<String, dynamic>;
  final server = metadata['server'] as Map<String, dynamic>;
  final env = metadata['environment'] as Map<String, dynamic>;
  stdout.writeln(
    'FlutterPilot startup benchmark · ${server['revision']} '
    '(${env['os']}, ${env['dart']})',
  );
  stdout.writeln('source freshness: ${server['sourceFreshness']}');
  for (final entry in report['cases'] as List) {
    final c = entry as Map<String, dynamic>;
    final metrics = c['metrics'] as Map<String, dynamic>;
    final ready = metrics['spawnToToolsListMs'] as Map<String, dynamic>;
    final read = metrics['spawnToReadMs'] as Map<String, dynamic>;
    stdout.writeln(
      '${c['caseId']}: MCP-ready ${_fmt(ready)} ms, first read ${_fmt(read)} ms '
      '(ok ${c['ok']}/${c['count']}, timeouts ${c['timedOut']}, '
      'errors ${c['errors']}, tools ${_toolsOf(c)})',
    );
  }
  final decision = report['decision'] as Map<String, dynamic>;
  stdout.writeln('bottleneck: ${decision['bottleneck']}');
  stdout.writeln(
    'startup ordering change recommended: '
    '${decision['startupOrderingChangeRecommended']}',
  );
  stdout.writeln('report: $reportPath');
}

String _fmt(Map<String, dynamic> metric) {
  if ((metric['n'] as int? ?? 0) == 0) return 'n/a';
  return '${(metric['median'] as num).toStringAsFixed(0)}'
      '(p95 ${metric['p95']})';
}

int? _toolsOf(Map<String, dynamic> c) {
  for (final trial in c['trials'] as List) {
    final count = (trial as Map)['toolCount'];
    if (count != null) return count as int;
  }
  return null;
}
