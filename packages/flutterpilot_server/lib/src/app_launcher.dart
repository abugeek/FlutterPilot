/// Starting the app for `launch_app`: which command, where its output goes,
/// and how it keeps running after the MCP server that started it is gone.
///
/// Field sessions hand-rolled this each time (`pkill`, `nohup flutter run`,
/// a loop grepping the log for the VM service URI), and killed the app when
/// a hot restart would have done.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'vm_discovery.dart';

/// `flutter run`'s output, for a launch that fails or is still building.
const launchLogFile = '.dart_tool/flutterpilot_run.log';

/// The output of the launch before this one: a relaunch used to erase what
/// the app that was just stopped had printed (slow-frame warnings, in the
/// case that prompted this).
const previousLaunchLogFile = '.dart_tool/flutterpilot_run.prev.log';

/// The pid of the running launch command; gone when it has exited.
const launchPidFile = '.dart_tool/flutterpilot_run.pid';

/// A project's own way to start the app, checked in:
/// `{"command": ["./scripts/run_macos.sh", "-t", "tool/pilot_main.dart"]}`.
const launchConfigFile = 'flutterpilot/launch.json';

/// What the supervisor writes to the log when the command exits.
const _exitMarker = '[flutterpilot] launch command exited with code ';

/// The command that starts the app in [root].
class LaunchCommand {
  const LaunchCommand(this.command, {required this.fromConfig});

  final List<String> command;

  /// From [launchConfigFile]: device, target and mode are the project's.
  final bool fromConfig;

  @override
  String toString() => command.join(' ');
}

/// [launchConfigFile]'s command when the project has one, else `flutter run`
/// with [device], [target] and [mode]. Throws a [FormatException] naming
/// what is wrong with the file.
LaunchCommand launchCommandFor(
  Directory root, {
  String? device,
  String? target,
  String? mode,
}) {
  final config = File(p.join(root.path, launchConfigFile));
  if (config.existsSync()) {
    final Object? json;
    try {
      json = jsonDecode(config.readAsStringSync());
    } on FormatException catch (e) {
      throw FormatException('$launchConfigFile is not JSON: ${e.message}');
    }
    final command = json is Map ? json['command'] : null;
    if (command is! List ||
        command.isEmpty ||
        command.any((part) => part is! String || part.isEmpty)) {
      throw const FormatException(
        '$launchConfigFile needs "command": a list of strings, e.g. '
        '{"command": ["flutter", "run", "-d", "macos"]}',
      );
    }
    return LaunchCommand(command.cast<String>(), fromConfig: true);
  }
  return LaunchCommand([
    'flutter',
    'run',
    '--vmservice-out-file=${VmDiscoveryService.uriFile}',
    if (mode == 'profile') '--profile',
    if (device != null && device.isNotEmpty) ...['-d', device],
    if (target != null && target.isNotEmpty) ...['-t', target],
  ], fromConfig: false);
}

/// Flutter apps under [roots] (a pubspec.yaml that depends on the Flutter
/// SDK and has a lib/main.dart or a launch config), nearest first.
List<Directory> flutterAppsUnder(List<Directory> roots, {int maxDepth = 3}) {
  final found = <String>{};
  void scan(Directory dir, int depth) {
    if (_isFlutterApp(dir)) {
      found.add(p.normalize(dir.absolute.path));
      return;
    }
    if (depth >= maxDepth) return;
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final child in children) {
      final name = p.basename(child.path);
      if (child is Directory &&
          !name.startsWith('.') &&
          name != 'build' &&
          name != 'node_modules') {
        scan(child, depth + 1);
      }
    }
  }

  for (final root in roots) {
    if (root.existsSync()) scan(root, 0);
  }
  return [for (final path in found) Directory(path)];
}

bool _isFlutterApp(Directory dir) {
  final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  if (File(p.join(dir.path, launchConfigFile)).existsSync()) return true;
  try {
    return RegExp(
          r'^\s+sdk:\s*flutter\s*$',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync()) &&
        File(p.join(dir.path, 'lib', 'main.dart')).existsSync();
  } catch (_) {
    return false;
  }
}

final _vmServiceUri = RegExp(
  r'(?:Dart VM Service|Debug service)[^\n]*?((?:http|ws)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]*)',
);

/// The VM service URI `flutter run` printed in [log], if it got that far.
String? vmServiceUriIn(String log) => _vmServiceUri.firstMatch(log)?.group(1);

/// The exit code of the launch command, once [log] records it.
int? launchExitCodeIn(String log) {
  final at = log.lastIndexOf(_exitMarker);
  if (at < 0) return null;
  return int.tryParse(
    log.substring(at + _exitMarker.length).split('\n').first.trim(),
  );
}

/// The end of [log] an agent needs to see why a launch failed: the last
/// [lines] non-empty lines, without the supervisor's own marker.
String launchLogTail(String log, {int lines = 30, int maxChars = 3000}) {
  final kept = log
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty && !line.startsWith(_exitMarker))
      .toList();
  var tail = kept
      .skip(kept.length > lines ? kept.length - lines : 0)
      .join('\n');
  if (tail.length > maxChars) {
    tail = '…${tail.substring(tail.length - maxChars)}';
  }
  return tail;
}

/// The pid in [root]'s [launchPidFile] if that process is still running.
int? runningLaunchPid(Directory root) {
  final file = File(p.join(root.path, launchPidFile));
  if (!file.existsSync()) return null;
  final pid = int.tryParse(file.readAsStringSync().trim());
  if (pid == null) return null;
  return _isRunning(pid) ? pid : null;
}

bool _isRunning(int pid) {
  try {
    if (Platform.isWindows) {
      final r = Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH']);
      return '${r.stdout}'.contains(' $pid ');
    }
    return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Starts [command] in [root] under a supervisor (this same executable with
/// `--supervise`) that is detached from the MCP server: the app keeps
/// running when the agent's session ends, and the next one finds it.
/// No shell is involved; the output goes to [launchLogFile].
Future<void> startSupervised(Directory root, List<String> command) async {
  startLaunchLog(root);
  final exe = Platform.resolvedExecutable;
  final compiled = !p.basenameWithoutExtension(exe).startsWith('dart');
  await Process.start(
    exe,
    [
      if (!compiled) Platform.script.toFilePath(),
      superviseFlag,
      root.absolute.path,
      ...command,
    ],
    workingDirectory: root.path,
    mode: ProcessStartMode.detached,
  );
}

/// Empties [launchLogFile] for a new launch, keeping what the last one
/// wrote as [previousLaunchLogFile].
void startLaunchLog(Directory root) {
  final log = File(p.join(root.path, launchLogFile));
  log.parent.createSync(recursive: true);
  try {
    if (log.existsSync() && log.lengthSync() > 0) {
      log.copySync(p.join(root.path, previousLaunchLogFile));
    }
  } catch (_) {
    // Losing the old output must not stop the new launch.
  }
  log.writeAsStringSync('');
}

/// First argument of the supervisor invocation; see [superviseLaunch].
const superviseFlag = '--supervise';

/// The supervisor: runs `args[1..]` in the folder `args[0]`, copies its
/// output to [launchLogFile], keeps its pid in [launchPidFile] while it
/// runs, and records the exit code. Returns that code.
Future<int> superviseLaunch(List<String> args) async {
  if (args.length < 2) return 64;
  final root = Directory(args.first);
  final log = File(p.join(root.path, launchLogFile));
  final pidFile = File(p.join(root.path, launchPidFile));
  log.parent.createSync(recursive: true);
  final sink = log.openWrite(mode: FileMode.append);
  int code;
  try {
    final process = await Process.start(
      args[1],
      args.sublist(2),
      workingDirectory: root.path,
    );
    pidFile.writeAsStringSync('${process.pid}');
    await Future.wait([
      process.stdout.forEach(sink.add),
      process.stderr.forEach(sink.add),
    ]);
    code = await process.exitCode;
  } on ProcessException catch (e) {
    sink.writeln('Could not start "${args[1]}": ${e.message}');
    code = 127;
  }
  sink.writeln('\n$_exitMarker$code');
  await sink.flush();
  await sink.close();
  try {
    pidFile.deleteSync();
  } catch (_) {}
  return code;
}

/// Where a running launch is, from the end of [log] (what `flutter run`
/// printed so far): the agent otherwise waits blind for minutes.
String? launchPhase(String log) {
  const stages = <(String, String)>[
    ('Resolving dependencies', 'fetching packages'),
    ('pod install', 'installing iOS pods'),
    (
      'Running Gradle task',
      'compiling the Android app (Gradle: slow the first time)',
    ),
    (
      'Running Xcode build',
      'compiling the iOS app (Xcode: slow the first time)',
    ),
    ('Xcode build done', 'built; installing on the device'),
    ('Built build/', 'built; installing on the device'),
    ('Installing', 'installing on the device'),
    ('Syncing files to device', 'starting; waiting for the first frame'),
    ('Waiting for', 'waiting for the device (is it unlocked and connected?)'),
  ];
  var best = -1;
  String? phase;
  for (final (marker, text) in stages) {
    final at = log.lastIndexOf(marker);
    if (at > best) {
      best = at;
      phase = text;
    }
  }
  return phase;
}
