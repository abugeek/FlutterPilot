// Entry point for the agent evals (task 01; task 04 hardening). Answers "given
// only FlutterPilot's tools, does a model finish realistic Flutter tasks, and at
// what call, token and time cost?" It is run by hand before and after surface
// changes; it calls a paid API, so it never runs in CI.
//
//   cd packages/fp_server
//   dart run tool/eval/run_evals.dart --repeat 3
//
// The app must already be running (`flutter run -d windows` in the lab app);
// see tool/eval/README.md for cost, budgets and setup.
//
// Task 04 makes the instrument trustworthy before anything is measured with
// it: distinct outcomes, a versioned report carrying a run identity, explicit
// pricing, a policy wrapper that keeps setup privileges away from the model,
// bounded I/O with deadlines, and a comparison that refuses to compare two
// different measurements. Exit codes: 0 success, 1 regression, 2 invalid
// configuration, 3 an incomplete or untrustworthy run.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fp_server/src/redaction.dart';

import 'src/agent.dart';
import 'src/anthropic_runner.dart';
import 'src/fixtures.dart';
import 'src/identity.dart';
import 'src/inspection.dart';
import 'src/mcp_session.dart';
import 'src/policy.dart';
import 'src/pricing.dart';
import 'src/report.dart';
import 'src/tasks.dart';

/// The reset operations the runner must be able to run before a case is valid.
/// A missing one is a failure; the optional set below may be absent and is then
/// declared, not silently skipped (task 04 §4).
const _requiredResets = <({String name, Map<String, dynamic> arguments})>[
  (
    name: 'set_app_settings',
    arguments: {
      'theme': 'light',
      'locale': 'system',
      'textScale': 0,
      'keyboardInset': 0,
    },
  ),
  (name: 'simulate_network', arguments: {'condition': 'normal'}),
];

const _optionalResets = <({String name, Map<String, dynamic> arguments})>[
  (name: 'mock_platform_channel', arguments: {'clear': true}),
  (name: 'get_debug_logs', arguments: {'clear': true}),
  (name: 'get_state', arguments: {'history': true, 'clear': true}),
  (name: 'get_http_profile', arguments: {'clear': true}),
];

/// The read-only inspection suite resets less: `simulate_network` is only
/// present when the app wires connectivity simulation (the notes lab does not),
/// so an inspection case must not depend on it — it is optional here and
/// declared, never a required-reset failure (task 05 §4).
const _inspectionRequiredResets =
    <({String name, Map<String, dynamic> arguments})>[
      (
        name: 'set_app_settings',
        arguments: {
          'theme': 'light',
          'locale': 'system',
          'textScale': 0,
          'keyboardInset': 0,
        },
      ),
    ];

const _inspectionOptionalResets =
    <({String name, Map<String, dynamic> arguments})>[
      ..._optionalResets,
      (name: 'simulate_network', arguments: {'condition': 'normal'}),
    ];

Future<void> main(List<String> argv) async {
  try {
    await _run(argv);
  } on _Abort {
    // _abort already printed the reason and set exitCode.
  }
}

Future<void> _run(List<String> argv) async {
  final evalDir = File.fromUri(Platform.script).parent.path;
  final parser = ArgParser()
    ..addOption(
      'model',
      defaultsTo: 'claude-sonnet-5-5',
      help: 'Messages API model id, pinned into the results.',
    )
    ..addOption(
      'base-url',
      help:
          'Messages API base URL (default: the ANTHROPIC_BASE_URL environment '
          'variable, else https://api.anthropic.com). Point it at a local fake '
          'instead of the paid API; the runner still needs a key-shaped value.',
    )
    ..addOption('tasks', help: 'Comma-separated task ids (default: all).')
    ..addOption(
      'suite',
      defaultsTo: 'workflows',
      allowed: ['workflows', 'inspection'],
      help:
          'Which suite to run: the workflow tasks (tasks.yaml) or the '
          'read-only inspection questions (inspection_tasks.yaml).',
    )
    ..addOption(
      'apps',
      help: 'Comma-separated lab app folder names (default: all).',
    )
    ..addOption('repeat', defaultsTo: '3', help: 'Runs per task.')
    ..addFlag(
      'launch',
      negatable: false,
      help: 'Start each app with launch_app first.',
    )
    ..addOption(
      'server-args',
      help:
          'Extra arguments appended to the server command '
          '(task 08 uses --tools core).',
    )
    ..addOption(
      'fixtures',
      help:
          'Directory holding one subdirectory per lab app (default: the '
          'parent of the repository).',
    )
    ..addOption(
      'compare',
      help:
          'A baseline summary.json to compare against; exits 1 on a regression, '
          '3 when the comparison is incomplete.',
    )
    ..addOption(
      'pricing',
      help: 'Explicit price table (default: tool/eval/pricing.json).',
    )
    ..addOption(
      'max-spend',
      defaultsTo: '0',
      help:
          'Stop the suite after this many USD. Needs an explicit price for '
          'the model; 0 disables the guard.',
    )
    ..addOption(
      'max-calls',
      defaultsTo: '0',
      help: 'Hard tool-call cap per run; 0 leaves only the turn cap.',
    )
    ..addOption(
      'max-run-seconds',
      defaultsTo: '0',
      help: 'Per-run wall-clock deadline in seconds; 0 disables it.',
    )
    ..addOption('max-turns', defaultsTo: '40', help: 'Turns per run.')
    ..addOption(
      'deadline',
      defaultsTo: '0',
      help: 'Whole-eval wall-clock deadline in seconds; 0 disables it.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    _abort('${e.message}\n\n${parser.usage}');
  }
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  // Validate repeats and numeric limits before anything else (task 04 §2).
  final repeat = _int(args['repeat'], '--repeat', min: 1);
  final maxCalls = _int(args['max-calls'], '--max-calls');
  final maxRunSeconds = _int(args['max-run-seconds'], '--max-run-seconds');
  final maxTurns = _int(args['max-turns'], '--max-turns', min: 1);
  final deadlineSeconds = _int(args['deadline'], '--deadline');
  final maxSpend = _money(args['max-spend'], '--max-spend');

  final root = _repoRoot();
  final model = '${args['model']}';
  // A local fake (tests) or a proxy: --base-url wins, then the environment,
  // then the real endpoint.
  final baseUrl =
      (args['base-url'] as String?) ??
      Platform.environment['ANTHROPIC_BASE_URL'] ??
      'https://api.anthropic.com';
  final extraServerArgs = _words(args['server-args'] as String? ?? '');

  final suiteName = '${args['suite']}';
  final suitePath = suiteName == 'inspection'
      ? '$evalDir/inspection_tasks.yaml'
      : '$evalDir/tasks.yaml';
  final InspectionSuite? inspection;
  final List<EvalTask> allTasks;
  if (suiteName == 'inspection') {
    try {
      inspection = loadInspectionSuite(suitePath);
    } on FormatException catch (e) {
      _abort(e.message);
    }
    allTasks = [for (final q in inspection.questions) q.toEvalTask()];
  } else {
    inspection = null;
    allTasks = loadTasks(suitePath);
  }
  final verifiedIds = <String, bool>{
    for (final q in inspection?.questions ?? const <InspectionQuestion>[])
      q.id: q.verified,
  };

  final ids = _csv(args['tasks'] as String? ?? '');
  var tasks = allTasks;
  if (ids.isNotEmpty) {
    final known = allTasks.map((t) => t.id).toSet();
    final unknown = ids.where((id) => !known.contains(id)).toList();
    if (unknown.isNotEmpty) {
      // A mistyped id must not silently shrink the suite (task 04 §2).
      _abort(
        'Unknown task id(s): ${unknown.join(', ')}.\n'
        'Known ids: ${(known.toList()..sort()).join(', ')}',
      );
    }
    tasks = allTasks.where((t) => ids.contains(t.id)).toList();
  }
  final appsFilter = _csv(args['apps'] as String? ?? '');
  if (appsFilter.isNotEmpty) {
    final unknownApps = appsFilter
        .where((app) => !defaultScenarios.containsKey(app))
        .toList();
    if (unknownApps.isNotEmpty) {
      _abort(
        'Unknown app(s): ${unknownApps.join(', ')}. '
        'Known apps: ${defaultScenarios.keys.join(', ')}',
      );
    }
    tasks = tasks.where((t) => appsFilter.contains(t.app)).toList();
  }
  if (tasks.isEmpty) _abort('No tasks selected.');

  // An inspection run needs verified answers: score only what was reproduced
  // through MCP, never a proposed answer (task 05 §7, §12).
  if (inspection != null) {
    final unverified = tasks
        .where((t) => verifiedIds[t.id] != true)
        .map((t) => t.id)
        .toList();
    if (unverified.isNotEmpty) {
      _abort(
        '--suite inspection: ${unverified.length} selected question(s) are not '
        'verified: ${unverified.join(', ')}.\n'
        'Solve each through MCP (tool/fp_bridge.dart), record the exact answer '
        'and evidence in $suitePath, and set verified: true before a run.',
      );
    }
  }

  final PricingConfig pricing;
  final pricingPath = (args['pricing'] as String?) ?? '$evalDir/pricing.json';
  try {
    pricing = PricingConfig.load(File(pricingPath));
  } on FormatException catch (e) {
    _abort(e.message);
  }
  if (maxSpend > 0 && !pricing.knows(model)) {
    _abort(
      '--max-spend needs an explicit price for "$model" in $pricingPath.\n'
      'Add one (raw token counts are still recorded without it); see '
      'tool/eval/README.md.',
    );
  }

  final byApp = <String, List<EvalTask>>{};
  for (final task in tasks) {
    byApp.putIfAbsent(task.app, () => []).add(task);
  }

  // Read-only preflight (task 00 §10): report every missing or mismatched
  // fixture before a paid call. A blocking issue stops the run.
  final fixturesRoot = (args['fixtures'] as String?) ?? root.parent.path;
  final FixtureManifest fixtureManifest;
  try {
    fixtureManifest = FixtureManifest.load(
      File('$evalDir/fixtures/manifest.json'),
    );
  } on FormatException catch (e) {
    _abort(e.message);
  }
  final fixtureIssues = preflightFixtures(
    fixtureManifest,
    fixturesRoot: fixturesRoot,
  );
  for (final issue in fixtureIssues) {
    stdout.writeln('fixture: $issue');
  }
  if (fixtureIssues.any((i) => i.level == FixtureIssueLevel.blocking)) {
    _abort(
      'Fixture preflight failed; fix the fixtures (--fixtures $fixturesRoot) '
      'before spending API calls. `dart run tool/eval/check_fixtures.dart` '
      'lists them.',
    );
  }

  // The paid credential is only required now, after every free check has
  // passed (task 04 §3).
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'ANTHROPIC_API_KEY is not set. The runner needs it to call the '
      'Messages API; everything up to here was free. Set it in the environment '
      '(never on the command line) and run again.\n'
      'Without a key you can still run the unit tests: '
      'dart test test/eval_runner_test.dart',
    );
    exitCode = 2;
    return;
  }

  final runner = AnthropicRunner(
    apiKey: apiKey,
    model: model,
    baseUrl: baseUrl,
    maxTurns: maxTurns,
    maxCalls: maxCalls,
    maxRunSeconds: maxRunSeconds,
  );
  final device = Platform.isWindows ? 'windows' : Platform.operatingSystem;
  final serverCommit = await _git(root.path);
  final apps = <String, AppInfo>{};
  final fixtureIdentities = <String, FixtureIdentity>{};
  final results = <TaskRun>[];

  final deadline = deadlineSeconds > 0
      ? DateTime.now().add(Duration(seconds: deadlineSeconds))
      : null;
  var spent = 0.0;
  var worstRunCost = 0.0;
  String? stopReason;

  final identity = RunIdentity(
    model: model,
    device: device,
    platform: Platform.operatingSystem,
    buildMode: 'debug',
    sdk: _sdkVersions(),
    taskSuite: taskSuiteIdentity(
      tasks,
      suiteText: File(suitePath).readAsStringSync(),
    ),
    fixtures: fixtureIdentities,
    policy: {
      'repeat': repeat,
      'suite': suiteName,
      'allowDestructive': true,
      'profile': '(default)',
      'serverArgs': extraServerArgs,
      'maxCalls': maxCalls,
      'maxTurns': maxTurns,
      'maxSpendUsd': maxSpend,
      'maxRunSeconds': maxRunSeconds,
      'deadlineSeconds': deadlineSeconds,
    },
    pricingVersion: pricing.versionTag,
  );

  for (final entry in byApp.entries) {
    final app = entry.key;
    final appDir = '${root.parent.path}/$app';

    if (stopReason != null) {
      for (final task in entry.value) {
        for (var run = 1; run <= repeat; run++) {
          results.add(TaskRun.budget(task, stopReason));
        }
      }
      continue;
    }
    if (!Directory(appDir).existsSync()) {
      _abort('Lab app not found: $appDir');
    }
    stdout.writeln('== $app ==');

    final McpSession setup;
    try {
      setup = await McpSession.start(
        entrypoint: '${root.path}/packages/fp_server/bin/fp_server.dart',
        serverArgs: ['-p', appDir, '--allow-destructive', ...extraServerArgs],
        workingDirectory: root.path,
        onStderr: _serverStderr,
      );
    } on McpException catch (e) {
      _abort('Could not start the MCP server for $app: ${e.message}');
    }
    final McpClient modelSession = suiteName == 'inspection'
        ? ReadOnlyPolicyClient(setup)
        : PolicyClient(setup);
    try {
      if (args['launch'] as bool) {
        // The device is named: `flutter run` with no `-d` refuses when a web
        // device is connected too ("More than one device connected").
        await setup.call('launch_app', {'relaunch': true, 'device': device});
      }
      await _waitForApp(setup);

      final listed = setup.tools.map((tool) => tool.name).toSet();
      final spec = fixtureManifest.byId(app);
      _checkCapabilities(app, spec, listed);

      fixtureIdentities[app] = buildFixtureIdentity(spec, appDir);
      apps[app] = AppInfo(
        commit: await _git(appDir),
        toolsListed: setup.tools.length,
        toolListChars: setup.toolListChars,
        toolListUtf8Bytes: setup.toolListUtf8Bytes,
        guidanceHash: sha256Text(setup.instructions),
        toolSchemaHash: canonicalToolSchemaHash(setup.tools),
        protocol: setup.negotiatedProtocol,
      );

      for (final task in entry.value) {
        for (var run = 1; run <= repeat; run++) {
          stopReason = _stopReason(
            deadline: deadline,
            spent: spent,
            worstRunCost: worstRunCost,
            maxSpend: maxSpend,
          );
          if (stopReason != null) {
            results.add(TaskRun.budget(task, stopReason));
            stdout.writeln('! ${task.id} $run/$repeat: $stopReason');
            continue;
          }
          final resetProblem = await _reset(
            setup,
            appDir,
            task,
            inspection: suiteName == 'inspection',
          );
          if (resetProblem != null) {
            results.add(
              TaskRun(
                task: task,
                run: AgentRun.empty(error: 'reset failed: $resetProblem'),
                passed: false,
              ),
            );
            stdout.writeln(
              '! ${task.id} $run/$repeat: reset failed: '
              '$resetProblem',
            );
            continue;
          }
          stdout.writeln('> ${task.id} $run/$repeat');
          final result = await runner.run(task, modelSession);
          final passed = runPassed(task, result);
          results.add(TaskRun(task: task, run: result, passed: passed));
          final runCost = estimateCost(model, [result], pricing);
          if (runCost.known) {
            spent += runCost.usd;
            if (runCost.usd > worstRunCost) worstRunCost = runCost.usd;
          }
          stdout.writeln(
            '  ${passed ? 'pass' : 'FAIL'}'
            '${result.isError ? ' (error: ${result.error})' : ''}'
            '${result.hitTurnLimit ? ' (turn limit)' : ''}'
            '${result.hitCallLimit ? ' (call limit)' : ''} — '
            '${result.calls.length} calls, '
            '${result.inputTokens}+${result.outputTokens} tok, '
            '${result.seconds.toStringAsFixed(1)}s, '
            'answer: ${result.answer ?? '(none)'}',
          );
        }
        // Reset after a task too, so a crash in it cannot poison the next.
        await _reset(
          setup,
          appDir,
          task,
          inspection: suiteName == 'inspection',
        );
      }
    } finally {
      await setup.close();
    }
  }

  final report = summarize(
    model: model,
    device: device,
    serverCommit: serverCommit,
    apps: apps,
    results: results,
    identity: identity,
    pricing: pricing,
  );
  final Directory resultsDir;
  try {
    resultsDir = Directory('$evalDir/results/${_timestamp()}')
      ..createSync(recursive: true);
  } on FileSystemException catch (e) {
    _abort('Could not create the results directory: ${e.message}');
  }
  File('${resultsDir.path}/runs.json').writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert([for (final result in results) _redactedRun(result)]),
  );
  File(
    '${resultsDir.path}/summary.json',
  ).writeAsStringSync(runReportToJson(report));

  stdout.writeln('\n${_summaryTable(report)}');
  stdout.writeln('Wrote ${resultsDir.path}');

  final comparePath = args['compare'] as String?;
  if (comparePath != null) {
    final RunReport baseline;
    try {
      baseline = RunReport.fromJson(
        jsonDecode(File(comparePath).readAsStringSync())
            as Map<String, dynamic>,
      );
    } on Object catch (e) {
      _abort('Could not read the baseline $comparePath: $e');
    }
    final Comparison comparison;
    try {
      comparison = compareReports(baseline, report);
    } on CompareRefused catch (e) {
      _abort('The baseline cannot be compared: ${e.message}');
    }
    stdout.writeln('\nCompared to $comparePath:');
    for (final line in comparison.lines) {
      stdout.writeln('  $line');
    }
    if (comparison.regressed) {
      stderr.writeln('Regression against the baseline.');
      exitCode = 1;
      return;
    }
    if (comparison.incomplete) {
      stderr.writeln(
        'The comparison is incomplete (errors, budget stops, skips or missing '
        'tasks); it cannot accept the change.',
      );
      exitCode = 3;
      return;
    }
  }

  if (!report.totals.benchmarkValid) {
    stderr.writeln(
      'The run is not a valid benchmark: ${report.totals.executed} case(s) '
      'executed, ${report.totals.errors} infrastructure error(s), '
      '${report.totals.budgetExhausted} budget stop(s), '
      '${report.totals.skipped} skip(s).',
    );
    exitCode = 3;
  }
}

/// Whether the suite must stop before the next run: a whole-eval deadline or a
/// spend guard (task 04 §9). A guard cannot undo an in-flight charge, so it
/// stops *before* the next run, using the costliest run so far as a
/// conservative estimate.
String? _stopReason({
  required DateTime? deadline,
  required double spent,
  required double worstRunCost,
  required double maxSpend,
}) {
  if (deadline != null && !DateTime.now().isBefore(deadline)) {
    return 'eval deadline reached';
  }
  if (maxSpend > 0 && (spent >= maxSpend || spent + worstRunCost > maxSpend)) {
    return 'spend guard reached (\$${spent.toStringAsFixed(4)} of '
        '\$${maxSpend.toStringAsFixed(2)})';
  }
  return null;
}

/// Warns when the fixture manifest declares capabilities the connected app did
/// not register (task 04 §3).
void _checkCapabilities(String app, FixtureSpec? spec, Set<String> listed) {
  if (spec == null || spec.expectedCapabilities.isEmpty) return;
  final missing = spec.expectedCapabilities
      .where((name) => !listed.contains(name))
      .toList();
  if (missing.isNotEmpty) {
    stdout.writeln(
      'capability: $app did not register ${missing.join(', ')} '
      '(declared by the fixture manifest)',
    );
  }
}

/// Loads the task's scenario, resets app-level settings and diagnostics, and
/// checks the scenario's route is showing from structured content. A non-null
/// return is why the reset could not be trusted (the run is then an
/// infrastructure error, not a failure).
Future<String?> _reset(
  McpSession session,
  String appDir,
  EvalTask task, {
  required bool inspection,
}) async {
  final scenario = task.scenario ?? defaultScenarios[task.app];
  if (scenario != null) {
    final load = await session.call('scenario', {'load': scenario});
    if (load.isError) return 'scenario($scenario): ${load.text}';
  }
  final listed = session.tools.map((tool) => tool.name).toSet();
  final problems = <String>[];
  for (final op in inspection ? _inspectionRequiredResets : _requiredResets) {
    if (!listed.contains(op.name)) {
      problems.add('${op.name} is not available');
      continue;
    }
    final result = await session.call(op.name, op.arguments);
    if (result.isError) problems.add('${op.name}: ${result.text}');
  }
  for (final op in inspection ? _inspectionOptionalResets : _optionalResets) {
    // Declared optional: absent is fine, present-but-failing is not.
    if (!listed.contains(op.name)) continue;
    final result = await session.call(op.name, op.arguments);
    if (result.isError) problems.add('${op.name}: ${result.text}');
  }
  if (problems.isNotEmpty) return problems.join('; ');

  if (scenario != null) {
    final route = _scenarioRoute(appDir, scenario);
    if (route != null) {
      final summary = await session.call('get_app_summary');
      if (summary.isError) return 'get_app_summary: ${summary.text}';
      final showing = summary.structured?['route'];
      if (showing is! String || showing != route) {
        return 'route $route is not showing after loading $scenario '
            '(summary route: ${showing ?? 'unknown'})';
      }
    }
  }
  return null;
}

String? _scenarioRoute(String appDir, String scenario) {
  final file = File('$appDir/flutterpilot/scenarios/$scenario.json');
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final route = json['route'];
    return route is String && route.isNotEmpty ? route : null;
  } catch (_) {
    return null;
  }
}

/// Waits until the server has found the app, so the model starts against the
/// real tool list (task 01 §1).
Future<void> _waitForApp(McpSession session) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final summary = await session.call('get_app_summary');
    if (!summary.isError) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw StateError('The app did not answer get_app_summary within 3 minutes.');
}

void _serverStderr(String line) {
  if (line.contains('SEVERE')) stderr.writeln('  [server] $line');
}

String _summaryTable(RunReport report) {
  final totals = report.totals;
  final cost = totals.costKnown
      ? '~\$${totals.costUsd.toStringAsFixed(2)}'
      : 'cost unknown';
  final buffer = StringBuffer(
    'Summary: ${totals.passed}/${totals.executed} passed '
    '(${(totals.passRate * 100).toStringAsFixed(0)}%), '
    '${totals.runs} run(s) [$cost]'
    '${totals.benchmarkValid ? '' : ' — NOT A VALID BENCHMARK'}\n',
  );
  for (final entry in report.tasks.entries) {
    final task = entry.value;
    buffer.writeln(
      '  ${entry.key}: ${task.passed}/${task.executed} '
      '(fail ${task.failed}, err ${task.errors}, budget '
      '${task.budgetExhausted}, skip ${task.skipped})  '
      'calls ${task.callsMedian}  '
      'in ${task.inputTokensMedian}  '
      'out ${task.outputTokensMedian}  '
      '${task.secondsMedian}s',
    );
  }
  return buffer.toString().trimRight();
}

/// A bounded, redacted run record: no credentials, no unrestricted response
/// body (task 04 §16).
Map<String, Object?> _redactedRun(TaskRun result) {
  final json = result.run.toJson();
  json['finalText'] = _cap(Redaction.text('${json['finalText']}'), 20000);
  final answer = json['answer'];
  if (answer is String) json['answer'] = Redaction.text(answer);
  final error = json['error'];
  if (error is String) json['error'] = Redaction.text(error);
  return {
    'task': result.task.id,
    'outcome': result.outcome.name,
    if (result.reason != null) 'reason': Redaction.text(result.reason!),
    'passed': result.passed,
    ...json,
  };
}

String _cap(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…[truncated]';

/// The repo root, found by walking up from the current directory to `.git`.
Directory _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/.git').existsSync() ||
        Directory('${dir.path}/.git').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not find the repo root from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

Future<String> _git(String dir) async {
  final result = await Process.run('git', [
    '-C',
    dir,
    'rev-parse',
    '--short',
    'HEAD',
  ], runInShell: true);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : 'unknown';
}

/// `dart`, `flutter` and OS versions for the run identity (task 04 §12).
Map<String, String> _sdkVersions() => {
  'dart': _commandVersion('dart', ['--version']),
  'flutter': _commandVersion('flutter', ['--version']),
  'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
};

String _commandVersion(String exe, List<String> args) {
  try {
    final result = Process.runSync(exe, args, runInShell: true);
    final all = '${result.stdout}\n${result.stderr}'.trim();
    for (final line in all.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return 'unknown';
  } catch (_) {
    return 'unknown';
  }
}

String _timestamp() {
  final now = DateTime.now().toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}T'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}Z';
}

List<String> _csv(String value) => [
  for (final part in value.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

List<String> _words(String value) => [
  for (final part in value.split(RegExp(r'\s+')))
    if (part.isNotEmpty) part,
];

int _int(Object? raw, String option, {int min = 0}) {
  final value = int.tryParse('$raw'.trim());
  if (value == null || value < min) {
    _abort('$option must be an integer >= $min (got "$raw").');
  }
  return value;
}

double _money(Object? raw, String option) {
  final value = double.tryParse('$raw'.trim());
  if (value == null || value < 0) {
    _abort('$option must be a non-negative number (got "$raw").');
  }
  return value;
}

class _Abort implements Exception {
  const _Abort();
}

/// Prints [message] to stderr, sets the invalid-configuration exit code, and
/// unwinds to [main]. Never returns.
Never _abort(String message) {
  stderr.writeln(message);
  exitCode = 2;
  throw const _Abort();
}
