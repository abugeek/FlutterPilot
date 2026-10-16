// Tests for the official-Inspector wrapper (task 03).
//
// The wrapper (`tool/inspector/inspector_cli.dart`) is exercised against a fake
// launcher (`test/fixtures/fake_inspector.dart`) run by the Dart VM, so every
// branch — success, a tool error, non-JSON stdout, a timeout, output truncation,
// tree cleanup — is proven without Node, the network, or a real Inspector. The
// real pinned Inspector is run by `tool/inspector/inspector_cli.dart` itself and
// by the CI job.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/inspector/inspector_cli.dart';

void main() {
  InspectorRunner runner({
    Map<String, String> env = const {},
    Duration deadline = const Duration(seconds: 60),
    int maxOutputBytes = 256 * 1024,
  }) => InspectorRunner(
    nodeExecutable: Platform.resolvedExecutable,
    launcherEntry: 'test/fixtures/fake_inspector.dart',
    configPath: 'unused-config.json',
    deadline: deadline,
    maxOutputBytes: maxOutputBytes,
    environment: env,
  );

  group('argument shape', () {
    test('the argv is an argument array with explicit flags', () {
      final argv = runner().argv([
        '--method',
        'tools/list',
        '--format',
        'json',
      ]);
      expect(argv, [
        '--cli',
        '--config',
        'unused-config.json',
        '--server',
        'flutterpilot',
        '--connect-timeout',
        '20000',
        '-q',
        '--method',
        'tools/list',
        '--format',
        'json',
      ]);
    });

    test('the exit classes match the pinned CLI documentation', () {
      expect(InspectorExit.of(0), InspectorExit.success);
      expect(InspectorExit.of(3), InspectorExit.authRequired);
      expect(InspectorExit.of(4), InspectorExit.unreachable);
      expect(InspectorExit.of(5), InspectorExit.toolError);
      expect(InspectorExit.of(6), InspectorExit.schemaUnportable);
      expect(InspectorExit.of(99), InspectorExit.unknown);
    });
  });

  group('parsing', () {
    test('a success envelope is parsed and trusted', () async {
      final result = await runner(
        env: {
          'FAKE_STDOUT': '{"result":{"tools":[{"name":"x"}]}}\n',
          'FAKE_EXIT': '0',
        },
      ).run(['--method', 'tools/list', '--format', 'json']);
      expect(result.exitCode, 0);
      expect(result.exitClass, InspectorExit.success);
      expect(result.stdoutIsJson, isTrue);
      expect(result.ok, isTrue);
      expect((result.result!['tools'] as List), hasLength(1));
    });

    test('a tool error keeps the payload and names the class', () async {
      final result = await runner(
        env: {
          'FAKE_STDOUT':
              '{"result":{"content":[{"type":"text","text":"no"}],'
              '"isError":true}}',
          'FAKE_STDERR': '{"error":{"code":"tool_error","message":"bad"}}\n',
          'FAKE_EXIT': '5',
        },
      ).run(['--method', 'tools/call', '--format', 'json']);
      expect(result.exitClass, InspectorExit.toolError);
      expect(result.result!['isError'], isTrue);
      expect(result.errorCode, 'tool_error');
      // A tool error still carries a machine-readable payload on stdout.
      expect(result.stdoutIsJson, isTrue);
      expect(result.ok, isFalse);
    });

    test('a banner or any trailing output invalidates stdout', () async {
      for (final stdout in [
        'Welcome to the Inspector\n{"result":{}}\n',
        '{"result":{}}\ntrailing',
        'not json at all',
      ]) {
        final result = await runner(
          env: {'FAKE_STDOUT': stdout, 'FAKE_EXIT': '0'},
        ).run(['--method', 'tools/list', '--format', 'json']);
        expect(result.stdoutIsJson, isFalse, reason: stdout);
        expect(result.ok, isFalse, reason: stdout);
      }
    });

    test('empty stdout is not trusted as JSON', () async {
      final result = await runner(
        env: {'FAKE_EXIT': '5'},
      ).run(['--method', 'tools/call', '--format', 'json']);
      expect(result.stdoutIsJson, isFalse);
      expect(result.ok, isFalse);
    });

    test('stdout is capped and reports truncation', () async {
      final huge = '{"result":{"blob":"${'x' * 5000}"}}';
      final result = await runner(
        env: {'FAKE_STDOUT': huge, 'FAKE_EXIT': '0'},
        maxOutputBytes: 1024,
      ).run(['--method', 'tools/list', '--format', 'json']);
      expect(result.truncated, isTrue);
      expect(result.ok, isFalse);
    });
  });

  group('deadlines and cleanup', () {
    test('a hanging probe is killed at the deadline, not waited out', () async {
      final stopwatch = Stopwatch()..start();
      final result = await runner(
        env: {'FAKE_SLEEP_MS': '60000', 'FAKE_EXIT': '0'},
        deadline: const Duration(seconds: 2),
      ).run(['--method', 'tools/list', '--format', 'json']);
      stopwatch.stop();
      expect(result.timedOut, isTrue);
      expect(result.ok, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
    });

    test('a killed probe leaves no descendant process behind', () async {
      final scratch = Directory.systemTemp.createTempSync('fp_inspector_pid');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final pidFile = File('${scratch.path}/child.pid');
      final result = await runner(
        env: {
          'FAKE_SLEEP_MS': '60000',
          'FAKE_CHILD_PID_FILE': pidFile.path,
          'FAKE_EXIT': '0',
        },
        deadline: const Duration(seconds: 4),
      ).run(['--method', 'tools/list', '--format', 'json']);
      expect(result.timedOut, isTrue);
      // The grandchild had time to start and record itself.
      expect(
        pidFile.existsSync(),
        isTrue,
        reason: 'fake never started a child',
      );
      final childPid = int.parse(pidFile.readAsStringSync().trim());
      expect(
        await _waitUntilGone(childPid),
        isTrue,
        reason: 'descendant $childPid survived the tree kill',
      );
    });
  });
}

/// Polls for up to ~8 seconds until [pid] is no longer a live process.
Future<bool> _waitUntilGone(int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    if (!await _isAlive(pid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return !await _isAlive(pid);
}

Future<bool> _isAlive(int pid) async {
  if (Platform.isWindows) {
    final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
    // "INFO: No tasks are running…" when the pid is gone.
    return RegExp('\\b$pid\\b').hasMatch('${result.stdout}');
  }
  final result = await Process.run('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}
