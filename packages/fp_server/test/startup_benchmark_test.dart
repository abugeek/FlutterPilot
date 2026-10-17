// Tests for the task-09 startup/readiness benchmark harness.
//
// The harness (`tool/benchmarks/startup_benchmark.dart`) measures a real server
// process against one monotonic clock. Proving it must not require the real
// FlutterPilot server, a Flutter app, or the network, so every process test here
// drives a deterministic fake MCP server (`test/fixtures/fake_mcp_server.dart`)
// run by the Dart VM. The pure report/aggregation/decision logic is tested with
// synthetic trials.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/benchmarks/startup_benchmark.dart';
import '../tool/support/process_tree.dart';

void main() {
  final sep = Platform.pathSeparator;
  final fakeScript = File('test/fixtures/fake_mcp_server.dart').absolute.path;

  LaunchSpec fake({
    Map<String, String> env = const {},
    String? workingDirectory,
    List<String> args = const [],
  }) => LaunchSpec(
    label: 'fake',
    executable: Platform.resolvedExecutable,
    args: ['run', fakeScript, ...args],
    workingDirectory: workingDirectory ?? Directory.current.path,
    environment: env,
  );

  const fast = Duration(seconds: 20);
  const total = Duration(seconds: 60);

  group('one timed launch', () {
    test('timestamps are monotonic on a single clock', () async {
      final result = await runTrial(
        launch: fake(),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.ok, isTrue);
      expect(result.protocolVersion, '2025-11-25');
      expect(result.toolCount, 3);
      expect(result.readUsable, isTrue);
      expect(result.hygieneClean, isTrue);
      expect(result.exited, isFalse);
      expect(result.cleanupConfirmed, isTrue);
      expect(result.error, isNull);
      expect(result.timedOut, isFalse);

      expect(result.spawnToInitializeMs, isNotNull);
      expect(result.spawnToToolsListMs, isNotNull);
      expect(result.spawnToReadMs, isNotNull);
      expect(
        result.spawnToToolsListMs!,
        greaterThanOrEqualTo(result.spawnToInitializeMs!),
      );
      expect(
        result.spawnToReadMs!,
        greaterThanOrEqualTo(result.spawnToToolsListMs!),
      );
      expect(result.totalMs!, greaterThanOrEqualTo(result.spawnToReadMs!));
    });

    test('a delayed handshake is reflected in the handshake metric', () async {
      final result = await runTrial(
        launch: fake(env: {'FAKE_INIT_DELAY_MS': '300'}),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.ok, isTrue);
      expect(result.spawnToInitializeMs!, greaterThanOrEqualTo(280));
    });

    test('a delayed read is reflected after tools/list, not before', () async {
      final result = await runTrial(
        launch: fake(env: {'FAKE_READ_DELAY_MS': '250'}),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.ok, isTrue);
      expect(
        result.spawnToReadMs! - result.spawnToToolsListMs!,
        greaterThanOrEqualTo(230),
      );
    });

    test('a pending connected-app read is timed separately', () async {
      final result = await runTrial(
        launch: fake(
          env: {
            'FAKE_SLOW_TOOL': 'get_app_summary',
            'FAKE_SLOW_TOOL_MS': '250',
          },
        ),
        readTool: 'list_connected_devices',
        connectedReadTool: 'get_app_summary',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.ok, isTrue);
      expect(result.spawnToConnectedReadMs, isNotNull);
      expect(
        result.spawnToConnectedReadMs! - result.spawnToReadMs!,
        greaterThanOrEqualTo(230),
      );
    });

    test('no connected-read timestamp without a connected read', () async {
      final result = await runTrial(
        launch: fake(),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.spawnToConnectedReadMs, isNull);
    });

    test(
      'a process that dies while a request is pending fails, not hangs',
      () async {
        final result = await runTrial(
          launch: fake(env: {'FAKE_EXIT_ON_METHOD': 'initialize'}),
          readTool: 'list_connected_devices',
          initializeTimeout: fast,
          requestTimeout: fast,
          totalTimeout: total,
        );

        expect(result.ok, isFalse);
        expect(result.timedOut, isFalse);
        expect(result.error, isNotNull);
        expect(result.cleanupConfirmed, isTrue);
      },
    );

    test('a process that dies after the handshake is still recorded', () async {
      final result = await runTrial(
        launch: fake(env: {'FAKE_EXIT_ON_METHOD': 'tools/list'}),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
      expect(result.spawnToInitializeMs, isNotNull);
      expect(result.spawnToToolsListMs, isNull);
    });

    test(
      'malformed stdout is recorded but does not desynchronise replies',
      () async {
        final result = await runTrial(
          launch: fake(env: {'FAKE_BANNER': 'FlutterPilot server 1.0\\n'}),
          readTool: 'list_connected_devices',
          initializeTimeout: fast,
          requestTimeout: fast,
          totalTimeout: total,
        );

        expect(result.hygieneClean, isFalse);
        expect(result.ok, isFalse);
        expect(result.error, isNull);
        // The protocol conversation still completed.
        expect(result.protocolVersion, '2025-11-25');
        expect(result.toolCount, 3);
      },
    );

    test(
      'a silent initialize is accounted as a timeout at that stage',
      () async {
        final result = await runTrial(
          launch: fake(env: {'FAKE_NO_REPLY': 'initialize'}),
          readTool: 'list_connected_devices',
          initializeTimeout: const Duration(milliseconds: 300),
          requestTimeout: fast,
          totalTimeout: total,
        );

        expect(result.timedOut, isTrue);
        expect(result.timedOutStage, 'initialize');
        expect(result.ok, isFalse);
        expect(result.toolCount, isNull);
        expect(result.cleanupConfirmed, isTrue);
      },
    );

    test('a silent tools/list is accounted at the tools/list stage', () async {
      final result = await runTrial(
        launch: fake(env: {'FAKE_NO_REPLY': 'tools/list'}),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: const Duration(milliseconds: 300),
        totalTimeout: total,
      );

      expect(result.timedOut, isTrue);
      expect(result.timedOutStage, 'tools/list');
      expect(result.spawnToInitializeMs, isNotNull);
      expect(result.spawnToToolsListMs, isNull);
    });

    test('a silent read is accounted at the read stage', () async {
      final result = await runTrial(
        launch: fake(env: {'FAKE_NO_REPLY': 'tools/call'}),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: const Duration(milliseconds: 300),
        totalTimeout: total,
      );

      expect(result.timedOut, isTrue);
      expect(result.timedOutStage, 'read');
      expect(result.spawnToToolsListMs, isNotNull);
      expect(result.spawnToReadMs, isNull);
    });

    test('index and cache state survive into the result', () async {
      final result = await runTrial(
        launch: fake(),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
        index: 7,
        cacheState: 'first-trial',
      );

      expect(result.index, 7);
      expect(result.cacheState, 'first-trial');
    });
  });

  group('process handling', () {
    test(
      'a directory path containing spaces is passed through intact',
      () async {
        final dir = Directory.systemTemp.createTempSync('fp bench ');
        addTearDown(() {
          try {
            dir.deleteSync(recursive: true);
          } catch (_) {}
        });
        final record = File('${dir.path}${sep}record.json');
        final root = '${dir.path}${sep}a root with spaces';

        final result = await runTrial(
          launch: LaunchSpec(
            label: 'fake',
            executable: Platform.resolvedExecutable,
            args: ['run', fakeScript, '-p', root],
            workingDirectory: dir.path,
            environment: {'FAKE_RECORD_FILE': record.path},
          ),
          readTool: 'list_connected_devices',
          initializeTimeout: fast,
          requestTimeout: fast,
          totalTimeout: total,
        );

        expect(result.ok, isTrue);
        final recorded =
            jsonDecode(record.readAsStringSync()) as Map<String, dynamic>;
        expect(recorded['cwd'], dir.resolveSymbolicLinksSync());
        expect(recorded['args'], contains(root));
      },
    );

    test('cleanup terminates the whole process tree', () async {
      final dir = Directory.systemTemp.createTempSync('fp bench ');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final childPidFile = File('${dir.path}${sep}child.pid');

      final result = await runTrial(
        launch: fake(env: {'FAKE_CHILD_PID_FILE': childPidFile.path}),
        readTool: 'list_connected_devices',
        initializeTimeout: fast,
        requestTimeout: fast,
        totalTimeout: total,
      );

      expect(result.ok, isTrue);
      expect(result.cleanupConfirmed, isTrue);

      final childPid = int.parse(childPidFile.readAsStringSync().trim());
      expect(
        await waitUntilProcessGone(childPid),
        isTrue,
        reason: 'the server grandchild (pid $childPid) should not survive',
      );
    });
  });

  group('TrialSet summaries', () {
    TrialTimings warm(
      int toolsListMs, {
      bool ok = true,
      bool timedOut = false,
    }) => TrialTimings(
      index: 1,
      cacheState: 'warm',
      ok: ok,
      timedOut: timedOut,
      spawnToInitializeMs: toolsListMs - 100,
      spawnToToolsListMs: timedOut ? null : toolsListMs,
      spawnToReadMs: timedOut ? null : toolsListMs + 50,
      totalMs: toolsListMs + 60,
    );

    test('every trial is retained, including failures and timeouts', () {
      final set = TrialSet(
        caseId: 'no-app/source',
        launchMode: LaunchMode.source,
        appState: AppState.noApp,
        staticTools: false,
        trials: [
          TrialTimings(
            index: 0,
            cacheState: 'first-trial',
            ok: true,
            timedOut: false,
            spawnToToolsListMs: 900,
          ),
          warm(1000),
          warm(1200, ok: false, timedOut: true),
          warm(1100),
        ],
      );
      final json = set.toJson();

      expect(json['count'], 4);
      expect(json['ok'], 3);
      expect(json['timedOut'], 1);
      expect(json['timeoutRate'], closeTo(0.25, 1e-9));
      expect((json['trials'] as List), hasLength(4));
      expect((json['firstTrial'] as Map)['cacheState'], 'first-trial');
    });

    test('metrics use the warm trials only, with a nearest-rank p95', () {
      final set = TrialSet(
        caseId: 'no-app/source',
        launchMode: LaunchMode.source,
        appState: AppState.noApp,
        staticTools: false,
        trials: [
          TrialTimings(
            index: 0,
            cacheState: 'first-trial',
            ok: true,
            timedOut: false,
            spawnToToolsListMs: 1,
          ),
          for (var i = 1; i <= 5; i++) warm(1000 + i * 100),
        ],
      );
      final metric =
          (set.toJson()['metrics'] as Map)['spawnToToolsListMs'] as Map;

      expect(metric['n'], 5);
      // values 1100..1500 → median (odd) is the middle 1300.
      expect(metric['median'], 1300);
      // p95 nearest rank of 5 samples is the maximum.
      expect(metric['p95'], 1500);
      expect(metric['min'], 1100);
      expect(metric['max'], 1500);
    });

    test('an empty metric reports n=0 rather than a fabricated value', () {
      final set = TrialSet(
        caseId: 'no-app/source',
        launchMode: LaunchMode.source,
        appState: AppState.noApp,
        staticTools: false,
        trials: [warm(1000, ok: false, timedOut: true)],
      );
      final metric =
          (set.toJson()['metrics'] as Map)['spawnToToolsListMs'] as Map;

      expect(metric['n'], 0);
      expect(metric.containsKey('median'), isFalse);
    });
  });

  group('decision', () {
    TrialSet noApp(int medianMs) => TrialSet(
      caseId: 'no-app/source',
      launchMode: LaunchMode.source,
      appState: AppState.noApp,
      staticTools: false,
      trials: [
        TrialTimings(
          index: 0,
          cacheState: 'warm',
          ok: true,
          timedOut: false,
          spawnToInitializeMs: medianMs - 100,
          spawnToToolsListMs: medianMs,
        ),
      ],
    );

    TrialSet unavailable(int medianMs) => TrialSet(
      caseId: 'unavailable/source',
      launchMode: LaunchMode.source,
      appState: AppState.unavailable,
      staticTools: false,
      trials: [
        TrialTimings(
          index: 0,
          cacheState: 'warm',
          ok: true,
          timedOut: false,
          spawnToInitializeMs: medianMs - 100,
          spawnToToolsListMs: medianMs,
        ),
      ],
    );

    test('with no usable medians the decision is "insufficient data"', () {
      final decision = computeDecision([
        TrialSet(
          caseId: 'no-app/source',
          launchMode: LaunchMode.source,
          appState: AppState.noApp,
          staticTools: false,
          trials: const [],
        ),
      ]);

      expect(decision['bottleneck'], 'insufficient data');
      expect(decision['startupOrderingChangeRecommended'], isFalse);
    });

    test('a large, proportionally big delay recommends a review', () {
      final decision = computeDecision([noApp(1000), unavailable(1400)]);

      expect(decision['startupOrderingChangeRecommended'], isTrue);
      expect('${decision['bottleneck']}', contains('dominates'));
      expect('${decision['rationale']}', contains('separately approved'));
    });

    test('a delay inside the threshold recommends no change', () {
      final decision = computeDecision([noApp(1000), unavailable(1100)]);

      expect(decision['startupOrderingChangeRecommended'], isFalse);
      expect('${decision['bottleneck']}', contains('not dominated'));
    });
  });

  group('redaction', () {
    test('a VM auth token never reaches a report', () {
      final redacted = redactVmUri('http://127.0.0.1:43210/secretToken123/');
      expect(redacted, isNot(contains('secretToken123')));
      expect(redacted, contains('127.0.0.1:43210'));
    });

    test('a websocket path is kept, other paths become a token marker', () {
      expect(redactVmUri('ws://127.0.0.1:1/ws'), 'ws://127.0.0.1:1/ws');
      expect(redactVmUri('http://host:1/abc'), contains('<token>'));
    });

    test('a non-URI passes through path redaction unchanged', () {
      expect(redactVmUri('not a uri'), 'not a uri');
    });

    test('the home directory is collapsed to ~', () {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      expect(redactPath('$home${sep}sub'), startsWith('~'));
    });
  });

  group('reference data', () {
    test('case and mode names round-trip', () {
      expect(LaunchMode.byName('source'), LaunchMode.source);
      expect(LaunchMode.byName('aot'), LaunchMode.aot);
      expect(LaunchMode.byName('nope'), isNull);
      expect(AppState.byName('no-app'), AppState.noApp);
      expect(AppState.byName('unavailable'), AppState.unavailable);
      expect(AppState.byName('connected'), AppState.connected);
      expect(AppState.byName('nope'), isNull);
      expect(AppState.connected.id, 'connected');
    });

    test('a launch spec reports and relabels its argv', () {
      const spec = LaunchSpec(
        label: 'source',
        executable: 'dart',
        args: ['run', 'bin/fp_server.dart'],
      );
      expect(spec.displayArgv, ['dart', 'run', 'bin/fp_server.dart']);
      final relabelled = spec.relabelled('aot');
      expect(relabelled.label, 'aot');
      expect(relabelled.args, spec.args);
    });
  });
}
