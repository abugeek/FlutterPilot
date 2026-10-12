import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'commands/doctor_command.dart';

/// What `flutterpilot doctor` says about the phones plugged in: whether each
/// one is fit to be driven by an agent (awake, unlocked, authorized,
/// developer mode on).

/// The adb executable: PATH, else the Android SDK's platform-tools.
String? findAdb({Map<String, String>? environment, String? path}) {
  final env = environment ?? Platform.environment;
  if (DoctorCommand.onPath('adb', path: path)) return 'adb';
  final home = env['HOME'] ?? env['USERPROFILE'];
  final exe = Platform.isWindows ? 'adb.exe' : 'adb';
  for (final root in [
    ?env['ANDROID_HOME'],
    ?env['ANDROID_SDK_ROOT'],
    if (home != null) ...[
      p.join(home, 'Library', 'Android', 'sdk'),
      p.join(home, 'Android', 'Sdk'),
    ],
    if (env['LOCALAPPDATA'] case final local?) p.join(local, 'Android', 'Sdk'),
  ]) {
    final f = File(p.join(root, 'platform-tools', exe));
    if (f.existsSync()) return f.path;
  }
  return null;
}

class AdbEntry {
  const AdbEntry(this.serial, this.state, this.model);
  final String serial;
  final String state;
  final String? model;
}

List<AdbEntry> parseAdbList(String out) => [
  for (final line in const LineSplitter().convert(out))
    if (RegExp(
          r'^(\S+)\s+(device|unauthorized|offline)\b(.*)$',
        ).firstMatch(line.trim())
        case final m?)
      AdbEntry(
        m.group(1)!,
        m.group(2)!,
        RegExp(r'model:(\S+)').firstMatch(m.group(3)!)?.group(1),
      ),
];

/// The host ports of `adb forward --list` lines for [serial] that [live]
/// does not list: left behind by a `flutter run` that was killed. [list] is
/// the output of `adb forward --list`.
List<int> staleForwardPorts(String list, String serial, Set<int> live) => [
  for (final line in const LineSplitter().convert(list))
    if (line.trim().split(RegExp(r'\s+')) case [
      final s,
      final local,
      _,
    ] when s == serial && local.startsWith('tcp:'))
      if (int.tryParse(local.substring(4)) case final port?)
        if (!live.contains(port)) port,
];

/// The warning for [ports] of stale forwards on [serial], else nothing.
List<DoctorCheck> staleForwardChecks(String serial, List<int> ports) =>
    ports.isEmpty
    ? const []
    : [
        DoctorCheck.warn(
          '$serial: ${ports.length} stale adb forward'
              '${ports.length == 1 ? '' : 's'} (left by a flutter run that was '
              'killed)',
          'Harmless but they pile up: '
              '${ports.take(5).map((p) => 'adb -s $serial forward --remove tcp:$p').join('; ')}'
              '${ports.length > 5 ? '; …' : ''}.',
        ),
      ];

/// Whether something on 127.0.0.1:[port] answers HTTP (any status).
Future<bool> portAnswers(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:$port/'))
        .timeout(const Duration(seconds: 2));
    final response = await request.close().timeout(const Duration(seconds: 2));
    await response.drain<void>();
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// The findings for one Android device from its `dumpsys`/`settings` output.
List<DoctorCheck> androidChecks(
  AdbEntry device, {
  String power = '',
  String window = '',
  String battery = '',
  String lowPower = '',
  String timeout = '',
}) {
  final name = '${device.model ?? 'Android'} (${device.serial})';
  if (device.state == 'unauthorized') {
    return [
      DoctorCheck.fail(
        '$name is not authorized for debugging',
        'Unlock the phone and accept "Allow USB debugging" (tick "Always '
            'allow"), or run `adb kill-server` and plug it in again.',
      ),
    ];
  }
  if (device.state == 'offline') {
    return [
      DoctorCheck.fail(
        '$name is offline',
        'Replug the cable (or reconnect Wi-Fi debugging); `adb kill-server` '
            'then `adb devices` if it stays offline.',
      ),
    ];
  }
  final awake = RegExp(r'mWakefulness=(\w+)').firstMatch(power)?.group(1);
  final locked = RegExp(
    r'isKeyguardShowing=(true|false)',
  ).firstMatch(window)?.group(1);
  final problems = <String>[
    if (awake != null && awake != 'Awake') 'the screen is off',
    if (locked == 'true') 'it is locked',
  ];
  final checks = <DoctorCheck>[];
  if (problems.isNotEmpty) {
    checks.add(
      DoctorCheck.warn(
        '$name: ${problems.join(' and ')}',
        'Wake and unlock it before a test run: system dialogs, the camera '
            'and anything native need it awake.',
      ),
    );
  } else {
    final level = RegExp(r'level: (\d+)').firstMatch(battery)?.group(1);
    checks.add(
      DoctorCheck.ok(
        '$name: screen on, unlocked${level == null ? '' : ', battery $level%'}',
      ),
    );
  }
  if (lowPower.trim() == '1') {
    checks.add(
      DoctorCheck.warn(
        '$name: battery saver is on',
        'It throttles background work and can slow or stall a test run: '
            'turn it off while testing.',
      ),
    );
  }
  final timeoutMs = int.tryParse(timeout.trim());
  if (timeoutMs != null && timeoutMs < 120000) {
    checks.add(
      DoctorCheck.warn(
        '$name: the screen dims after ${(timeoutMs / 1000).round()} s',
        'The FlutterPilot SDK keeps the screen on while an agent drives the '
            'app (and releases it 10 min after the last call); you do not '
            'need to change the phone\'s timeout. Needs flutterpilot_sdk in '
            'the app.',
      ),
    );
  }
  return checks;
}

/// The findings for the physical iPhones in `devicectl list devices` JSON.
/// [lockState] answers `device info lockState` for an identifier.
List<DoctorCheck> iosChecks(
  String listJson, {
  bool? Function(String identifier)? lockState,
}) {
  final List devices;
  try {
    devices =
        ((jsonDecode(listJson) as Map)['result'] as Map)['devices'] as List;
  } catch (_) {
    return const [];
  }
  final checks = <DoctorCheck>[];
  for (final d in devices.whereType<Map>()) {
    final conn = (d['connectionProperties'] as Map?) ?? const {};
    if (conn['transportType'] == 'sameMachine') continue;
    final props = (d['deviceProperties'] as Map?) ?? const {};
    final name = '${props['name'] ?? 'iPhone'}';
    final transport = conn['transportType'] == 'wired' ? 'USB' : 'Wi-Fi';
    if (conn['tunnelState'] != 'connected') {
      checks.add(
        DoctorCheck.warn(
          '$name (iPhone) is paired but not connected',
          'Unlock it and plug it in (or keep it on the same Wi-Fi as this '
              'Mac with "Connect via network" ticked in Xcode).',
        ),
      );
      continue;
    }
    if (props['developerModeStatus'] != null &&
        props['developerModeStatus'] != 'enabled') {
      checks.add(
        DoctorCheck.fail(
          '$name (iPhone): Developer Mode is off',
          'Settings → Privacy & Security → Developer Mode, then restart the '
              'phone.',
        ),
      );
      continue;
    }
    final locked = lockState?.call('${d['identifier']}');
    if (locked == true) {
      checks.add(
        DoctorCheck.warn(
          '$name (iPhone, $transport): it is locked',
          'Unlock it before a test run; iOS suspends a locked app and '
              'system dialogs need the screen.',
        ),
      );
    } else {
      checks.add(
        DoctorCheck.ok(
          '$name (iPhone, $transport)${locked == false ? ': unlocked' : ''}',
        ),
      );
    }
  }
  return checks;
}

Future<String?> _run(
  String exe,
  List<String> args, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final r = await Process.run(exe, args).timeout(timeout);
    return r.exitCode == 0 ? r.stdout as String : null;
  } catch (_) {
    return null;
  }
}

/// Phones plugged in right now: Android over adb, iPhones over devicectl.
/// Nothing is listed when there are none (or the tools are missing).
Future<List<DoctorCheck>> checkDevices() async {
  final checks = <DoctorCheck>[];
  final adb = findAdb();
  if (adb != null) {
    final list = await _run(adb, ['devices', '-l']);
    for (final device in parseAdbList(list ?? '')) {
      if (device.serial.startsWith('emulator-')) continue;
      Future<String> sh(List<String> cmd) async =>
          await _run(adb, ['-s', device.serial, 'shell', ...cmd]) ?? '';
      checks.addAll(
        device.state != 'device'
            ? androidChecks(device)
            : androidChecks(
                device,
                power: await sh(['dumpsys', 'power']),
                window: await sh(['dumpsys', 'window']),
                battery: await sh(['dumpsys', 'battery']),
                lowPower: await sh(['settings', 'get', 'global', 'low_power']),
                timeout: await sh([
                  'settings',
                  'get',
                  'system',
                  'screen_off_timeout',
                ]),
              ),
      );
      if (device.state == 'device') {
        final forwards = await _run(adb, ['forward', '--list']) ?? '';
        final live = <int>{};
        for (final line in const LineSplitter().convert(forwards)) {
          final parts = line.trim().split(RegExp(r'\s+'));
          final port = parts.length == 3 && parts[0] == device.serial
              ? int.tryParse(parts[1].replaceFirst('tcp:', ''))
              : null;
          if (port != null && await portAnswers(port)) live.add(port);
        }
        checks.addAll(
          staleForwardChecks(
            device.serial,
            staleForwardPorts(forwards, device.serial, live),
          ),
        );
      }
    }
  }
  if (Platform.isMacOS) {
    final list = await _run('xcrun', [
      'devicectl',
      'list',
      'devices',
      '--json-output',
      '-',
      '--timeout',
      '10',
    ]);
    if (list != null) {
      final locks = <String, bool?>{};
      try {
        final devices =
            ((jsonDecode(list) as Map)['result'] as Map)['devices'] as List;
        for (final d in devices.whereType<Map>()) {
          final conn = (d['connectionProperties'] as Map?) ?? const {};
          if (conn['transportType'] == 'sameMachine' ||
              conn['tunnelState'] != 'connected') {
            continue;
          }
          final id = '${d['identifier']}';
          final raw = await _run('xcrun', [
            'devicectl',
            'device',
            'info',
            'lockState',
            '--device',
            id,
            '--json-output',
            '-',
            '--timeout',
            '10',
          ]);
          try {
            final v =
                (((jsonDecode(raw ?? '') as Map)['result']
                    as Map)['passcodeRequired']);
            locks[id] = v is bool ? v : null;
          } catch (_) {}
        }
      } catch (_) {}
      checks.addAll(iosChecks(list, lockState: (id) => locks[id]));
    }
  }
  return checks;
}
