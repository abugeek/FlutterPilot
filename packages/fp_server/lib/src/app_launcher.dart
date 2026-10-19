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

import 'start_command.dart';
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

/// Whether [root] starts its app its own way ([launchConfigFile]): `device`,
/// `target` and `mode` are the project's then, not the caller's.
bool hasLaunchConfig(Directory root) =>
    File(p.join(root.path, launchConfigFile)).existsSync();

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

/// The `-d` id of an app running on [operatingSystem], when the platform
/// names the device itself: a desktop app runs on the device called
/// `windows`, `macos` or `linux`. A web app's id is its browser and a phone's
/// is its serial, neither of which the platform gives: those are null, so the
/// caller lists the connected devices instead (field test #346).
String? deviceForPlatform(String? operatingSystem, {bool isWeb = false}) {
  if (isWeb) return null;
  return switch (operatingSystem) {
    'macos' || 'linux' || 'windows' => operatingSystem,
    _ => null,
  };
}

/// The ids `flutter devices --machine` lists, which is what `flutter run -d`
/// takes. Empty when the command fails or says nothing: the caller then lets
/// `flutter run` decide, as it did before.
Future<List<String>> flutterDeviceIds() async {
  try {
    final result = await runProgram(['flutter', 'devices', '--machine']);
    final decoded = jsonDecode('${result.stdout}');
    if (decoded is! List) return const [];
    return [
      for (final device in decoded)
        if (device is Map && device['id'] is String) '${device['id']}',
    ];
  } catch (_) {
    return const [];
  }
}

/// What `launch_app` will run and where, decided before the app it replaces
/// is stopped.
class LaunchPlan {
  const LaunchPlan.on(
    this.device,
    this.command, {
    this.deviceWasRunning = false,
  }) : refusal = null;

  /// Return [refusal] instead of launching: nothing was stopped or started.
  const LaunchPlan.refused(this.refusal)
    : device = null,
      command = null,
      deviceWasRunning = false;

  /// The `-d` value, or null to let `flutter run` pick the only connected
  /// device (as it did before).
  final String? device;

  /// The command that starts the app, already resolved.
  final LaunchCommand? command;

  /// The error to return in place of a launch.
  final String? refusal;

  /// Whether [device] came from the app being replaced, so the response can
  /// say so (field test #346).
  final bool deviceWasRunning;
}

/// Whether a `launch_app` call only waits for the launch a previous call
/// started: its command is still running, nothing is connected yet, and this
/// call is not a relaunch.
///
/// Such a call answers "Still building … call launch_app again to keep
/// waiting", so it has to work with no `device` on a machine with several
/// devices: nothing is chosen, `flutter devices` is not run and nothing is
/// stopped (review of PR #128). This is settled *before* the device question.
bool waitsForRunningLaunch({
  required bool relaunch,
  required bool launchRunning,
  required bool connected,
}) => !relaunch && launchRunning && !connected;

/// Works out where a launch will run and what will start it, and only then
/// stops the app a relaunch replaces.
///
/// The order is the point (field test #346): a relaunch with no `device` on a
/// machine with several devices stopped the app first and *then* let
/// `flutter run` refuse with "More than one device connected", leaving the
/// agent with no app at all. Everything knowable up front is settled first:
/// the device — the caller's, else the one the running app is on, else the
/// machine's only one, left to `flutter run` as before — then the command
/// ([commandFor]). When the device cannot be told, the plan is a [refusal]
/// naming the devices to pass and [stop] is not called.
///
/// A call that only waits for a launch already going on
/// ([waitsForRunningLaunch]) asks none of that: it plans nothing, lists
/// nothing and stops nothing, and only needs a command for its messages.
Future<LaunchPlan> prepareLaunch({
  required bool relaunch,

  /// The caller's own [waitsForRunningLaunch] answer: this call only waits.
  bool waitingForLaunch = false,
  required bool chooseDevice,
  String? requested,
  String? runningPlatform,
  bool runningIsWeb = false,
  required Future<List<String>> Function() listDevices,
  required LaunchCommand Function(String? device) commandFor,
  required Future<void> Function() stop,
}) async {
  final asked = requested?.trim();
  if (waitingForLaunch) {
    // The device the running launch used is not recorded, so the command for
    // the messages is this call's own, as it was before the ordering change.
    final device = !chooseDevice || asked == null || asked.isEmpty
        ? null
        : asked;
    return LaunchPlan.on(device, commandFor(device));
  }
  var device = !chooseDevice || asked == null || asked.isEmpty ? null : asked;
  var deviceWasRunning = false;
  if (chooseDevice && device == null) {
    device = deviceForPlatform(runningPlatform, isWeb: runningIsWeb);
    deviceWasRunning = device != null;
    if (device == null) {
      final devices = await listDevices();
      if (devices.length > 1) {
        return LaunchPlan.refused(
          'More than one device is connected (${devices.join(', ')}) and '
          'FlutterPilot cannot tell which one to use; nothing was launched or '
          'stopped. Pass device: launch_app(device: "${devices.first}").',
        );
      }
    }
  }
  final command = commandFor(device);
  if (relaunch) await stop();
  return LaunchPlan.on(device, command, deviceWasRunning: deviceWasRunning);
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
///
/// On macOS the supervisor runs as [macLauncherApp], opened through
/// LaunchServices, when that works; otherwise it is started directly.
Future<void> startSupervised(
  Directory root,
  List<String> command, {
  Map<String, String>? environment,
}) async {
  startLaunchLog(root);
  final exe = Platform.resolvedExecutable;
  final compiled = !p.basenameWithoutExtension(exe).startsWith('dart');
  if (Platform.isMacOS && compiled) {
    final app = await macLauncherApp(exe);
    if (app != null) {
      final env = {...Platform.environment, ...?environment};
      final opened = await Process.run('open', [
        '-n',
        '-g',
        app,
        for (final e in env.entries) ...['--env', '${e.key}=${e.value}'],
        '--args',
        superviseFlag,
        root.absolute.path,
        ...command,
      ]);
      if (opened.exitCode == 0) return;
    }
  }
  await Process.start(
    exe,
    [
      if (!compiled) Platform.script.toFilePath(),
      superviseFlag,
      root.absolute.path,
      ...command,
    ],
    workingDirectory: root.path,
    environment: environment,
    mode: ProcessStartMode.detached,
  );
}

/// The macOS app bundle the supervisor runs as, so macOS has a real app to ask
/// for camera, microphone and other privacy permissions.
///
/// macOS charges a process's privacy requests to its *responsible* process:
/// whatever started the chain. `flutter run` starts the app as its own child,
/// so an app launched from the MCP server answered to the agent's command-line
/// server, which cannot show a prompt, and every camera request was denied
/// without one (Octana, "Scan customer card"). Opened through LaunchServices,
/// this bundle is the responsible process of `flutter run` and of the app
/// under it: macOS asks once for "FlutterPilot", like it would for Terminal,
/// and the user can allow it under App Management for hot reload into a
/// sandboxed app's container.
///
/// The bundle is [exe] with an Info.plist, ad-hoc signed, under
/// [supportDir] (default `~/Library/Application Support/FlutterPilot`), and is
/// refreshed when [exe] changes. Null when it cannot be made: the caller then
/// starts the supervisor directly.
Future<String?> macLauncherApp(String exe, {String? supportDir}) async {
  try {
    final dir =
        supportDir ??
        p.join(
          Platform.environment['HOME']!,
          'Library',
          'Application Support',
          'FlutterPilot',
        );
    final app = p.join(dir, 'FlutterPilot.app');
    final source = File(exe);
    final bin = File(p.join(app, 'Contents', 'MacOS', 'fp_server'));
    // Signing rewrites the copy, so which build it is lives beside the bundle
    // (inside, it would break the signature).
    final stamp = File('$app.stamp');
    final stat = source.statSync();
    final id = '$exe ${stat.size} ${stat.modified.toIso8601String()}';
    if (bin.existsSync() &&
        stamp.existsSync() &&
        stamp.readAsStringSync() == id) {
      return app;
    }
    bin.parent.createSync(recursive: true);
    source.copySync(bin.path);
    File(
      p.join(app, 'Contents', 'Info.plist'),
    ).writeAsStringSync(_launcherInfoPlist);
    final sign = await Process.run('codesign', ['--force', '-s', '-', app]);
    if (sign.exitCode != 0) return null;
    stamp.writeAsStringSync(id);
    return app;
  } catch (_) {
    return null;
  }
}

const _launcherInfoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>dev.flutterpilot.launcher</string>
	<key>CFBundleName</key><string>FlutterPilot</string>
	<key>CFBundleExecutable</key><string>fp_server</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSUIElement</key><true/>
	<key>NSCameraUsageDescription</key><string>Apps FlutterPilot launches for testing can use the camera.</string>
	<key>NSMicrophoneUsageDescription</key><string>Apps FlutterPilot launches for testing can use the microphone.</string>
	<key>NSLocationUsageDescription</key><string>Apps FlutterPilot launches for testing can use your location.</string>
	<key>NSBluetoothAlwaysUsageDescription</key><string>Apps FlutterPilot launches for testing can use Bluetooth.</string>
</dict>
</plist>
''';

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
    // `flutter` is `flutter.bat` on Windows: without a shell it is not found
    // and the launch dies with code 127 (field test #327).
    final process = await startProgram([
      args[1],
      ...args.sublist(2),
    ], workingDirectory: root.path);
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

/// Ends the launch command [pid] and everything it started. On Windows a
/// launch is `cmd.exe` running a batch file (`flutter.bat`), and killing only
/// that shell leaves the build and the app behind: `taskkill /T` takes the
/// whole tree down (field test #327).
Future<void> killLaunchTree(
  int pid, {
  bool? isWindows,
  Future<ProcessResult> Function(String, List<String>)? run,
}) async {
  if (!(isWindows ?? Platform.isWindows)) {
    Process.killPid(pid);
    return;
  }
  try {
    await (run ?? Process.run)('taskkill', [
      '/T',
      '/F',
      '/PID',
      '$pid',
    ]).timeout(const Duration(seconds: 15));
  } catch (_) {
    // It exited between the check and the kill: nothing left to end.
  }
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
