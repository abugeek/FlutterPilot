// A fake "Node launcher" for `test/inspector_cli_test.dart`.
//
// The wrapper under test spawns `<nodeExecutable> <launcherEntry> <argv...>`.
// In tests the executable is the Dart VM and this file is the launcher entry,
// so the wrapper runs `dart fake_inspector.dart --cli --config … -q --method …`.
// Everything this "launcher" does is driven by environment variables, so one
// fixture can act like a healthy CLI, a failing one, a hanging one, or a noisy
// one without another process or the network.
//
// This is test support, not shipped code.
library;

import 'dart:io';

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final sleepMs = int.tryParse(env['FAKE_SLEEP_MS'] ?? '') ?? 0;
  if (sleepMs > 0) {
    // Optionally start a long-lived grandchild and record its pid, so the
    // wrapper's tree-kill can be proven (Windows `taskkill /T`).
    final childPidFile = env['FAKE_CHILD_PID_FILE'] ?? '';
    if (childPidFile.isNotEmpty) {
      final child = await Process.start(Platform.resolvedExecutable, [
        'run',
        'test/fixtures/fake_sleeper.dart',
      ]);
      File(childPidFile).writeAsStringSync('${child.pid}');
    }
    await Future<void>.delayed(Duration(milliseconds: sleepMs));
  }

  final out = env['FAKE_STDOUT'] ?? '';
  if (out.isNotEmpty) stdout.write(out.replaceAll(r'\n', '\n'));
  final err = env['FAKE_STDERR'] ?? '';
  if (err.isNotEmpty) stderr.write(err.replaceAll(r'\n', '\n'));
  exit(int.tryParse(env['FAKE_EXIT'] ?? '') ?? 0);
}
