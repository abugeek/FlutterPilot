// Entry point for the agent evals (task 01). Answers "given only FlutterPilot's
// tools, does a model finish realistic Flutter tasks, and at what call, token
// and time cost?" It is run by hand before and after surface changes; it calls
// a paid API, so it never runs in CI.
//
//   cd packages/flutterpilot_server
//   dart run tool/eval/run_evals.dart --repeat 3
//
// The app must already be running (`flutter run -d windows` in the lab app);
// see tool/eval/README.md for cost and setup.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'src/agent.dart';
import 'src/anthropic_runner.dart';
import 'src/mcp_session.dart';
import 'src/report.dart';
import 'src/tasks.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'model',
      defaultsTo: 'claude-sonnet-5-5',
      help: 'Messages API model id, pinned into the results.',
    )
    ..addOption('tasks', help: 'Comma-separated task ids (default: all).')
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
      'compare',
      help:
          'A baseline summary.json to compare against; exits 1 on a regression.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');
  final args = parser.parse(argv);
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'ANTHROPIC_API_KEY is not set. The runner needs it to call the '
      'Messages API. Set it in the environment (never on the command line) '
      'and run again.\n'
      'Without a key you can still run the unit tests: '
      'dart test test/eval_runner_test.dart',
    );
    exitCode = 2;
    return;
  }

  final root = _repoRoot();
  final evalDir = File.fromUri(Platform.script).parent.path;
  final model = '${args['model']}';
  final repeat = int.parse('${args['repeat']}');
  final extraServerArgs = _words(args['server-args'] as String? ?? '');

  var tasks = loadTasks('$evalDir/tasks.yaml');
  final ids = _csv(args['tasks'] as String? ?? '');
  if (ids.isNotEmpty) tasks = tasks.where((t) => ids.contains(t.id)).toList();
  final appsFilter = _csv(args['apps'] as String? ?? '');
  if (appsFilter.isNotEmpty) {
    tasks = tasks.where((t) => appsFilter.contains(t.app)).toList();
  }
  if (tasks.isEmpty) {
    stderr.writeln('No tasks selected.');
    exitCode = 2;
    return;
  }

  final byApp = <String, List<EvalTask>>{};
  for (final task in tasks) {
    byApp.putIfAbsent(task.app, () => []).add(task);
  }

  final runner = AnthropicRunner(apiKey: apiKey, model: model);
  final device = Platform.isWindows ? 'windows' : Platform.operatingSystem;
  final serverCommit = await _git(root.path);
  final apps = <String, AppInfo>{};
  final results = <TaskRun>[];

  for (final entry in byApp.entries) {
    final app = entry.key;
    final appDir = '${root.parent.path}/$app';
    if (!Directory(appDir).existsSync()) {
      stderr.writeln('Lab app not found: $appDir');
      exitCode = 2;
      return;
    }
    stdout.writeln('== $app ==');
    final session = await McpSession.start(
      entrypoint:
          '${root.path}/packages/flutterpilot_server/bin/flutterpilot_server.dart',
      serverArgs: ['-p', appDir, '--allow-destructive', ...extraServerArgs],
      workingDirectory: root.path,
      onStderr: _serverStderr,
    );
    try {
      if (args['launch'] as bool) {
        // The device is named: `flutter run` with no `-d` refuses when a web
        // device is connected too ("More than one device connected").
        await session.call('launch_app', {'relaunch': true, 'device': device});
      }
      await _waitForApp(session);
      apps[app] = AppInfo(
        commit: await _git(appDir),
        toolsListed: session.tools.length,
        toolListBytes: session.toolListBytes,
      );
      for (final task in entry.value) {
        for (var run = 1; run <= repeat; run++) {
          final resetProblem = await _reset(session, appDir, task);
          if (resetProblem != null) {
            results.add(
              TaskRun(
                task: task,
                run: _failedRun('reset failed: $resetProblem'),
                passed: false,
              ),
            );
            stdout.writeln('! ${task.id} $run/$repeat: $resetProblem');
            continue;
          }
          stdout.writeln('> ${task.id} $run/$repeat');
          final result = await runner.run(task, session);
          final passed = runPassed(task, result);
          results.add(TaskRun(task: task, run: result, passed: passed));
          stdout.writeln(
            '  ${passed ? 'pass' : 'FAIL'}'
            '${result.isError ? ' (error: ${result.error})' : ''}'
            '${result.hitTurnLimit ? ' (turn limit)' : ''} — '
            '${result.calls.length} calls, '
            '${result.inputTokens}+${result.outputTokens} tok, '
            '${result.seconds.toStringAsFixed(1)}s, '
            'answer: ${result.answer ?? '(none)'}',
          );
        }
        // Reset after a task too, so a crash in it cannot poison the next.
        await _reset(session, appDir, task);
      }
    } finally {
      await session.close();
    }
  }

  final report = summarize(
    model: model,
    device: device,
    serverCommit: serverCommit,
    apps: apps,
    results: results,
  );
  final resultsDir = Directory('$evalDir/results/${_timestamp()}')
    ..createSync(recursive: true);
  File('${resultsDir.path}/runs.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert([
      for (final result in results)
        {
          'task': result.task.id,
          'passed': result.passed,
          ...result.run.toJson(),
        },
    ]),
  );
  File(
    '${resultsDir.path}/summary.json',
  ).writeAsStringSync(runReportToJson(report));

  stdout.writeln('\n${_summaryTable(report)}');
  stdout.writeln('Wrote ${resultsDir.path}');

  final comparePath = args['compare'] as String?;
  if (comparePath != null) {
    final baseline = RunReport.fromJson(
      jsonDecode(File(comparePath).readAsStringSync()) as Map<String, dynamic>,
    );
    final comparison = compareReports(baseline, report);
    stdout.writeln('\nCompared to $comparePath:');
    for (final line in comparison.lines) {
      stdout.writeln('  $line');
    }
    if (comparison.regressed) {
      stderr.writeln('Regression against the baseline.');
      exitCode = 1;
    }
  }
}

AgentRun _failedRun(String error) => AgentRun(
  calls: const [],
  turns: 0,
  inputTokens: 0,
  outputTokens: 0,
  cacheWriteTokens: 0,
  cacheReadTokens: 0,
  seconds: 0,
  finalText: '',
  hitTurnLimit: false,
  error: error,
);

/// Loads the task's scenario, resets the app-level settings, clears the logs
/// and histories, and checks the scenario's route is showing. A non-null return
/// is why the reset could not be trusted (the run is then `error`, not `fail`).
Future<String?> _reset(McpSession session, String appDir, EvalTask task) async {
  final scenario = task.scenario ?? defaultScenarios[task.app];
  if (scenario != null) {
    final load = await session.call('scenario', {'load': scenario});
    if (load.isError) return 'scenario($scenario): ${load.text}';
  }
  final listed = session.tools.map((tool) => tool.name).toSet();
  Future<void> callIfListed(String name, Map<String, dynamic> arguments) async {
    if (listed.contains(name)) await session.call(name, arguments);
  }

  // A scenario restores stored data, mocks and state, not these.
  await callIfListed('set_app_settings', {
    'theme': 'light',
    'locale': 'system',
    'textScale': 0,
    'keyboardInset': 0,
  });
  await callIfListed('simulate_network', {'condition': 'normal'});
  await callIfListed('mock_platform_channel', {'clear': true});
  await callIfListed('get_debug_logs', {'clear': true});
  await callIfListed('get_state', {'history': true, 'clear': true});
  await callIfListed('get_http_profile', {'clear': true});

  if (scenario != null) {
    final route = _scenarioRoute(appDir, scenario);
    if (route != null) {
      final summary = await session.call('get_app_summary');
      if (summary.isError || !summary.text.contains(route)) {
        return 'route $route is not showing after loading $scenario';
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
  final buffer = StringBuffer(
    'Summary: ${report.totals.pass}/${report.totals.runs} passed '
    '(${(report.totals.passRate * 100).toStringAsFixed(0)}%), '
    '~\$${report.totals.costUsd.toStringAsFixed(2)}\n',
  );
  for (final entry in report.tasks.entries) {
    final task = entry.value;
    buffer.writeln(
      '  ${entry.key}: ${task.pass}/${task.runs}  '
      'calls ${task.callsMedian}  '
      'in ${task.inputTokensMedian}  '
      'out ${task.outputTokensMedian}  '
      '${task.secondsMedian}s',
    );
  }
  return buffer.toString().trimRight();
}

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
