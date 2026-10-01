import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Why the app died outside Dart (ROADMAP §5.8): an Objective-C, Swift or
/// Kotlin exception, or a signal. The VM connection only says the app is
/// gone; the reason is in the OS crash report and log.
class NativeCrash {
  NativeCrash({
    this.kind,
    this.reason,
    this.frames = const [],
    this.report,
    this.time,
    this.reportPending = false,
  });

  /// `EXC_CRASH (SIGABRT)`, `SIGSEGV`, ...; null until the report is in.
  final String? kind;

  /// The exception's message, e.g. "*** Terminating app due to uncaught
  /// exception 'X', reason: '...'".
  final String? reason;

  /// Frames from where it was thrown, the throw machinery skipped.
  final List<String> frames;

  /// Where the full report is.
  final String? report;
  final DateTime? time;

  /// The OS is still writing the report (it takes ~20 s on Apple
  /// platforms).
  final bool reportPending;

  String describe() {
    final b = StringBuffer('The app crashed in native code');
    if (kind != null) b.write(': $kind');
    if (time != null) b.write(' at ${_clock(time!)}');
    b.write('.');
    if (reason != null) b.write('\n$reason');
    if (frames.isNotEmpty) {
      b.write('\nWhere:');
      for (final f in frames) {
        b.write('\n  $f');
      }
    }
    if (report != null) b.write('\nFull report: $report');
    if (reportPending) {
      b.write(
        '\nThe OS is still writing the crash report (~20 s after the '
        'crash); call get_errors again then for where it crashed.',
      );
    }
    return b.toString();
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

/// Parses an Apple `.ips` crash report (macOS apps and iOS simulator apps
/// both write them to the Mac's `~/Library/Logs/DiagnosticReports`): a
/// JSON header line, then the JSON body. Null if it is not a crash report.
({int pid, NativeCrash crash})? parseIpsReport(String content, {String? path}) {
  final newline = content.indexOf('\n');
  if (newline < 0) return null;
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(content.substring(newline + 1)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final pid = body['pid'];
  if (pid is! int) return null;
  final exception = body['exception'] as Map<String, dynamic>? ?? {};
  final type = exception['type'] as String? ?? 'crash';
  final signal = exception['signal'] as String?;
  final kind = signal == null ? type : '$type ($signal)';

  final reasons = <String>[
    // Swift fatalError, C++ aborts and friends leave their message here.
    for (final lines
        in (body['asi'] as Map<String, dynamic>? ?? {}).values
            .whereType<List>())
      for (final line in lines.whereType<String>()) line.trim(),
  ];
  final termination = body['termination'] as Map<String, dynamic>?;
  for (final r in (termination?['reasons'] as List?) ?? const []) {
    if (r is String) reasons.add(r.trim());
  }

  final images = [
    for (final i in (body['usedImages'] as List?) ?? const [])
      i is Map<String, dynamic> ? i : const <String, dynamic>{},
  ];
  // The app's own code (and the Flutter engine) is inside its bundle;
  // system libraries are elsewhere (on the simulator, /Volumes/VOLUME/…).
  bool isSystem(int? index) {
    if (index == null || index < 0 || index >= images.length) return true;
    return !(images[index]['path'] as String? ?? '').contains('.app/');
  }

  // An uncaught exception's own backtrace says where it was thrown; the
  // crashed thread then only shows abort().
  var raw = (body['lastExceptionBacktrace'] as List?) ?? const [];
  if (raw.isEmpty) {
    final threads = (body['threads'] as List?) ?? const [];
    final crashed = threads.whereType<Map<String, dynamic>>().where(
      (t) => t['triggered'] == true,
    );
    raw = crashed.isEmpty ? const [] : (crashed.first['frames'] as List);
  }
  final frames = raw.whereType<Map<String, dynamic>>().toList();
  // Skip the system frames on top (objc_exception_throw, abort, ...).
  final firstOwn = frames.indexWhere((f) => !isSystem(f['imageIndex'] as int?));
  final shown = frames
      .skip(firstOwn < 0 ? 0 : firstOwn)
      .take(8)
      .map((f) => _frame(f, images));

  final captured = body['captureTime'] as String?;
  return (
    pid: pid,
    crash: NativeCrash(
      kind: kind,
      reason: reasons.isEmpty ? null : reasons.join('\n'),
      frames: shown.toList(),
      report: path,
      time: captured == null ? null : parseIpsTime(captured),
    ),
  );
}

String _frame(Map<String, dynamic> f, List<Map<String, dynamic>> images) {
  final index = f['imageIndex'] as int?;
  final image = index != null && index >= 0 && index < images.length
      ? images[index]['name'] as String?
      : null;
  final symbol =
      f['symbol'] as String? ??
      '0x${(f['imageOffset'] ?? 0).toRadixString(16)}';
  // Swift thunks name `<compiler-generated>` as their file.
  final file = (f['sourceFile'] as String?)?.contains('<') ?? true
      ? null
      : f['sourceFile'] as String;
  final line = f['sourceLine'];
  return [
    symbol,
    if (file != null) line == null ? file : '$file:$line',
    if (image != null) '($image)',
  ].join(' ');
}

/// `2026-09-28 09:56:00.8018 +0500` → a local DateTime.
DateTime? parseIpsTime(String s) {
  final m = RegExp(
    r'^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)(\.\d+)? ([+-])(\d\d)(\d\d)$',
  ).firstMatch(s.trim());
  if (m == null) return null;
  final fraction = (m.group(3) ?? '').padRight(7, '0').substring(0, 7);
  final utc = DateTime.tryParse('${m.group(1)}T${m.group(2)}${fraction}Z');
  if (utc == null) return null;
  final offset = Duration(
    hours: int.parse(m.group(5)!),
    minutes: int.parse(m.group(6)!),
  );
  return (m.group(4) == '+' ? utc.subtract(offset) : utc.add(offset)).toLocal();
}

/// The uncaught exception message an Apple app logs just before aborting,
/// from `log show` output (compact style).
String? exceptionFromLog(String log) {
  final m = RegExp(
    r"\*\*\* Terminating app due to uncaught exception '[^']*', reason: '.*",
  ).firstMatch(log);
  return m?.group(0)?.trim();
}

/// The crash of process [pid] from `adb logcat -b crash -d` output: a Java
/// or Kotlin `FATAL EXCEPTION` with its stack, or a native signal.
NativeCrash? parseLogcatCrash(String log, int pid) {
  final lines = const LineSplitter().convert(log);
  // Each line: `09-29 10:00:01.123  1234  1234 E AndroidRuntime: message`.
  final line = RegExp(r'^\S+ \S+\s+(\d+)\s+\d+ \w (\S+?)\s*: ?(.*)$');
  final mine = [
    for (final l in lines)
      if (line.firstMatch(l) case final m?
          when int.tryParse(m.group(1)!) == pid ||
              (m.group(2) == 'DEBUG' || m.group(2) == 'libc'))
        (tag: m.group(2)!, text: m.group(3)!),
  ];
  final fatal = mine.lastIndexWhere(
    (l) => l.tag == 'AndroidRuntime' && l.text.startsWith('FATAL EXCEPTION'),
  );
  if (fatal >= 0) {
    final rest = mine
        .skip(fatal + 1)
        .where((l) => l.tag == 'AndroidRuntime')
        .map((l) => l.text.trim())
        .where((t) => !t.startsWith('Process:'))
        .toList();
    final reason = rest.isEmpty ? null : rest.first;
    return NativeCrash(
      kind: 'uncaught exception on the Android side',
      reason: reason,
      frames: rest.skip(1).where((t) => t.startsWith('at ')).take(8).toList(),
      report: 'adb logcat -b crash -d',
    );
  }
  final signal = mine.lastIndexWhere(
    (l) =>
        l.tag == 'libc' &&
        l.text.startsWith('Fatal signal') &&
        l.text.contains('pid $pid '),
  );
  if (signal >= 0) {
    final frames = mine
        .skip(signal + 1)
        .where((l) => l.tag == 'DEBUG' && l.text.trim().startsWith('#'))
        .map((l) => l.text.trim())
        .take(8)
        .toList();
    final abort = mine
        .skip(signal + 1)
        .where((l) => l.tag == 'DEBUG' && l.text.startsWith('Abort message:'))
        .map((l) => l.text)
        .firstOrNull;
    return NativeCrash(
      kind: mine[signal].text.split(' in tid').first,
      reason: abort,
      frames: frames,
      report: 'adb logcat -b crash -d',
    );
  }
  return null;
}

/// Where the app ran, to look for its crash once the connection drops.
class CrashTarget {
  CrashTarget({
    required this.pid,
    required this.operatingSystem,
    required this.since,
    this.simulatorUdid,
  });

  final int pid;
  final String operatingSystem;
  final DateTime since;
  final String? simulatorUdid;
}

/// Finds out, once the connection to [target] dropped, whether it crashed
/// and why. On Apple platforms the kernel logs a crash at once (it keeps a
/// "corpse" of the process for the report), while the report itself takes
/// ~20 s: [current] answers from the log first, then from the report.
class NativeCrashWatch {
  NativeCrashWatch(
    this.target, {
    this.reportsDir,
    this.reportWait = const Duration(seconds: 90),
    this.crashLogWait = const Duration(seconds: 30),
  }) {
    _run();
  }

  final CrashTarget target;
  final String? reportsDir;
  final Duration reportWait;

  /// How long to keep looking for the kernel's note of the crash.
  final Duration crashLogWait;

  final _decided = Completer<void>();
  NativeCrash? _crash;

  /// The crash as known now; null if the app did not crash (it was closed
  /// or stopped) or this platform can't tell from here.
  Future<NativeCrash?> current({
    Duration wait = const Duration(seconds: 8),
  }) async {
    await _decided.future.timeout(wait, onTimeout: () {});
    return _crash;
  }

  Future<void> _run() async {
    try {
      switch (target.operatingSystem) {
        case 'macos' || 'ios' when Platform.isMacOS:
          await _apple();
        case 'android':
          _crash = await _androidCrash(target);
        default:
      }
    } catch (_) {
      // Best effort: the error stays "not running".
    } finally {
      if (!_decided.isCompleted) _decided.complete();
    }
  }

  Future<void> _apple() async {
    // A phone's crashes stay on the phone.
    if (target.operatingSystem == 'ios' && target.simulatorUdid == null) {
      return;
    }
    // The log can lag behind the connection closing, by seconds on a busy
    // machine (CI). Callers wait for the first few looks only; a crash
    // seen later still reaches the next tool's error.
    var crashed = false;
    final logDeadline = DateTime.now().add(crashLogWait);
    for (var i = 0; !crashed && DateTime.now().isBefore(logDeadline); i++) {
      if (i > 0) await Future<void>.delayed(const Duration(seconds: 1));
      if (i == 3 && !_decided.isCompleted) _decided.complete();
      try {
        crashed = await _kernelSawCrash(target.pid);
      } on TimeoutException {
        // `log show` was slow: look again.
      }
    }
    if (!crashed) return;
    final reason = await _exceptionFromAppleLog(target);
    _crash = NativeCrash(reason: reason, reportPending: true);
    if (!_decided.isCompleted) _decided.complete();

    final deadline = DateTime.now().add(reportWait);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final report = _findIpsReport(target, reportsDir);
      if (report == null) continue;
      _crash = NativeCrash(
        kind: report.kind,
        reason: reason ?? report.reason,
        frames: report.frames,
        report: report.report,
        time: report.time,
      );
      return;
    }
    _crash = NativeCrash(reason: reason);
  }
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Future<String> _appleLog(String predicate, {String? simulatorUdid}) async {
  final args = [
    'show',
    '--style',
    'compact',
    '--start',
    _stamp(DateTime.now().subtract(const Duration(minutes: 2))),
    '--predicate',
    predicate,
  ];
  final result = simulatorUdid == null
      ? await Process.run('/usr/bin/log', args)
      : await Process.run('xcrun', [
          'simctl',
          'spawn',
          simulatorUdid,
          'log',
          ...args,
        ]);
  return result.stdout as String;
}

/// The kernel keeps a corpse of a crashed process for its crash report; a
/// process that exits normally has none. Up to macOS 27.0 the kernel logged
/// `name[pid] Corpse allowed …`; from 27.0.1 only ReportCrashService does
/// ("Parsing corpse data for pid N"). Simulator apps are processes on the
/// Mac, so this holds for them.
Future<bool> _kernelSawCrash(int pid) async {
  final log = await _appleLog(
    '(processID == 0 AND eventMessage CONTAINS "[$pid] Corpse") OR '
    '(process == "ReportCrashService" AND '
    'eventMessage CONTAINS "corpse data for pid $pid")',
  ).timeout(const Duration(seconds: 10));
  return crashSeenInLog(log, pid);
}

/// Whether `log show` output has the corpse of process [pid].
bool crashSeenInLog(String log, int pid) =>
    log.contains('[$pid] Corpse') ||
    RegExp('corpse data for pid $pid\\b').hasMatch(log);

/// An uncaught NSException's message is only in the app's log.
Future<String?> _exceptionFromAppleLog(CrashTarget target) async {
  try {
    final log = await _appleLog(
      'processID == ${target.pid} AND '
      'eventMessage CONTAINS "Terminating app due to uncaught exception"',
      simulatorUdid: target.simulatorUdid,
    ).timeout(const Duration(seconds: 15));
    return exceptionFromLog(log);
  } catch (_) {
    return null;
  }
}

NativeCrash? _findIpsReport(CrashTarget target, String? reportsDir) {
  final dir = Directory(
    reportsDir ??
        '${Platform.environment['HOME']}/Library/Logs/DiagnosticReports',
  );
  try {
    for (final e in dir.listSync()) {
      if (e is! File ||
          !e.path.endsWith('.ips') ||
          !e.lastModifiedSync().isAfter(target.since)) {
        continue;
      }
      final parsed = parseIpsReport(e.readAsStringSync(), path: e.path);
      if (parsed != null && parsed.pid == target.pid) return parsed.crash;
    }
  } catch (_) {}
  return null;
}

Future<NativeCrash?> _androidCrash(CrashTarget target) async {
  // The crash buffer is written as the app dies; give it a moment.
  for (var i = 0; i < 3; i++) {
    if (i > 0) await Future<void>.delayed(const Duration(seconds: 1));
    try {
      final result = await Process.run('adb', [
        'logcat',
        '-b',
        'crash',
        '-d',
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;
      final crash = parseLogcatCrash(result.stdout as String, target.pid);
      if (crash != null) return crash;
    } catch (_) {
      return null;
    }
  }
  return null;
}
