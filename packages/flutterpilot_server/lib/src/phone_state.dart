import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'android_device.dart';

/// Whether a physical phone is fit to drive: awake and unlocked, and the
/// facts that make a test flaky (battery saver, a short screen timeout).
class PhoneState {
  const PhoneState({this.problem, required this.summary});

  /// Null when the phone is fine to drive, else why not.
  final String? problem;

  /// `screen on, unlocked, charging, 100%`.
  final String summary;

  /// What to do about [problem].
  static const fix =
      'Wake and unlock it by hand (native_button WAKEUP wakes an Android '
      'phone, not the lock screen). FlutterPilot keeps the app drawing, but '
      'system dialogs, the camera and anything native need it awake.';

  factory PhoneState.android(AndroidDeviceState s) =>
      PhoneState(problem: s.problem, summary: s.describe());
}

/// A physical iPhone as `xcrun devicectl` reports it.
class IosDevice {
  const IosDevice({
    required this.identifier,
    required this.name,
    required this.transport,
    required this.connected,
    this.udid,
  });
  final String identifier;

  /// The hardware UDID `flutter devices` prints (`00008130-…`).
  final String? udid;
  final String name;

  /// `wired`, `localNetwork`, or `sameMachine` (a simulator).
  final String transport;
  final bool connected;

  bool get physical => transport != 'sameMachine';
}

/// The devices of `devicectl list devices --json-output -`.
List<IosDevice> parseDevicectlDevices(String json) {
  try {
    final devices =
        ((jsonDecode(json) as Map)['result'] as Map)['devices'] as List;
    return [
      for (final d in devices.whereType<Map>())
        IosDevice(
          identifier: '${d['identifier']}',
          name: '${(d['deviceProperties'] as Map?)?['name'] ?? '?'}',
          transport:
              '${(d['connectionProperties'] as Map?)?['transportType'] ?? '?'}',
          connected:
              (d['connectionProperties'] as Map?)?['tunnelState'] ==
              'connected',
          udid: (d['hardwareProperties'] as Map?)?['udid'] as String?,
        ),
    ];
  } catch (_) {
    return const [];
  }
}

/// `devicectl device info lockState` JSON: true when a passcode is needed
/// to use the phone right now (it is locked), null if unreadable.
bool? parseDevicectlLocked(String json) {
  try {
    final result = (jsonDecode(json) as Map)['result'] as Map;
    final v = result['passcodeRequired'];
    return v is bool ? v : null;
  } catch (_) {
    return null;
  }
}

PhoneState iosPhoneState(IosDevice device, {bool? locked}) => PhoneState(
  problem: !device.connected
      ? 'the iPhone "${device.name}" is not connected (${device.transport}); '
            'unlock it and check the cable or the Wi-Fi'
      : locked == true
      ? 'the iPhone is locked'
      : null,
  summary: [
    device.name,
    device.transport == 'wired' ? 'USB' : device.transport,
    if (!device.connected) 'NOT connected',
    if (locked != null) locked ? 'LOCKED' : 'unlocked',
  ].join(', '),
);

Future<String?> _devicectl(List<String> args) async {
  try {
    final r = await Process.run('xcrun', [
      'devicectl',
      ...args,
      '--json-output',
      '-',
      '--timeout',
      '10',
    ]).timeout(const Duration(seconds: 15));
    return r.exitCode == 0 ? r.stdout as String : null;
  } catch (_) {
    return null;
  }
}

/// The one physical iPhone attached, with its lock state; null when there
/// is none, several (ambiguous), or devicectl is not available.
Future<PhoneState?> readIosPhoneState({String? udid}) async {
  if (!Platform.isMacOS) return null;
  final list = await _devicectl(['list', 'devices']);
  if (list == null) return null;
  final phones = parseDevicectlDevices(list)
      .where(
        (d) =>
            d.physical &&
            (udid == null || d.udid == udid || d.identifier == udid),
      )
      .toList();
  if (phones.length != 1) return null;
  final phone = phones.single;
  bool? locked;
  if (phone.connected) {
    final raw = await _devicectl([
      'device',
      'info',
      'lockState',
      '--device',
      phone.identifier,
    ]);
    if (raw != null) locked = parseDevicectlLocked(raw);
  }
  return iosPhoneState(phone, locked: locked);
}

/// The state of the phone `flutter run -d [deviceId]` targets: an Android
/// serial from `adb devices`, or an iPhone UDID; null for anything else
/// (simulators, desktops, web) or when it cannot be read.
Future<PhoneState?> phoneStateForDevice(String? deviceId) async {
  if (deviceId == null || deviceId.isEmpty) return null;
  try {
    final adbPath = await findAdb();
    if (adbPath != null) {
      final list = await adb(adbPath, null, ['devices', '-l']);
      final known = list == null
          ? const <AdbDevice>[]
          : parseAdbDevices(list.stdout as String);
      if (known.any((d) => d.serial == deviceId)) {
        final state = await readAndroidDeviceState(adbPath, deviceId);
        return state == null ? null : PhoneState.android(state);
      }
    }
    if (RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$').hasMatch(deviceId)) {
      return await readIosPhoneState(udid: deviceId);
    }
  } catch (_) {}
  return null;
}
