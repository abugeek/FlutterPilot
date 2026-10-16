// Process-tree supervision shared by the development tools (task 03's Inspector
// wrapper and the task-09 startup benchmark).
//
// A probe that hangs must not leave an unbounded subprocess behind. On Windows
// the launcher and the server it spawned are separate processes, so the whole
// tree is killed with `taskkill /T /F`; POSIX has no portable kill-by-tree, so
// the direct children are signalled first (while the parent still exists) and
// then the group leader. Both are best effort — the caller still reports the
// timeout — but [isProcessAlive] lets a test assert the tree really is gone.
//
// Development-tool support, not shipped code.
library;

import 'dart:io';

/// Kills [process] and its descendants, best effort.
///
/// Windows uses `taskkill /T` because its `.bat`/`.cmd` launchers and any server
/// they spawned are separate processes; POSIX kills the direct children first
/// and then the parent. Never throws: a failed kill is not a benchmark failure.
Future<void> killProcessTree(Process process) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]).timeout(const Duration(seconds: 10));
    } else {
      try {
        await Process.run('pkill', [
          '-TERM',
          '-P',
          '${process.pid}',
        ]).timeout(const Duration(seconds: 5));
      } catch (_) {}
      process.kill(ProcessSignal.sigkill);
    }
  } catch (_) {
    // Best effort; the caller still reports the timeout or failure.
  }
}

/// Whether a process with [pid] is currently alive.
///
/// Used to assert that a killed probe left no descendant behind. Returns false
/// for a pid that no longer exists (on Windows `tasklist` prints an INFO line
/// rather than a row).
Future<bool> isProcessAlive(int pid) async {
  if (Platform.isWindows) {
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/NH',
      ]);
      return RegExp('\\b$pid\\b').hasMatch('${result.stdout}');
    } catch (_) {
      return false;
    }
  }
  try {
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Polls [isProcessAlive] for up to [timeout] until [pid] is gone.
///
/// Returns true when the process is gone within the window.
Future<bool> waitUntilProcessGone(
  int pid, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (!await isProcessAlive(pid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return !await isProcessAlive(pid);
}
