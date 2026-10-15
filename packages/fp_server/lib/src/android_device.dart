import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Talking to an Android phone or emulator through `adb`: finding it, the
/// native screen (system dialogs the Flutter tree does not have), and whether
/// the device is awake and unlocked.

/// The adb executable: on PATH, else in the Android SDK (`ANDROID_HOME`,
/// `ANDROID_SDK_ROOT`, or the SDK's default folder, none of which are
/// usually on PATH).
Future<String?> findAdb({
  Map<String, String>? environment,
  Future<bool> Function(String exe)? onPath,
}) async {
  final env = environment ?? Platform.environment;
  if (await (onPath ?? _onPath)('adb')) return 'adb';
  final home = env['HOME'] ?? env['USERPROFILE'];
  final exe = Platform.isWindows ? 'adb.exe' : 'adb';
  final roots = <String>[
    ?env['ANDROID_HOME'],
    ?env['ANDROID_SDK_ROOT'],
    if (home != null) ...['$home/Library/Android/sdk', '$home/Android/Sdk'],
    ?(env['LOCALAPPDATA'] == null
        ? null
        : '${env['LOCALAPPDATA']}/Android/Sdk'),
  ];
  for (final root in roots) {
    final f = File('$root/platform-tools/$exe');
    if (f.existsSync()) return f.path;
  }
  return null;
}

Future<bool> _onPath(String exe) async {
  try {
    final r = await Process.run(Platform.isWindows ? 'where' : 'which', [exe]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

class AdbDevice {
  const AdbDevice(this.serial, this.state, {this.model});
  final String serial;

  /// `device`, `unauthorized`, `offline`.
  final String state;
  final String? model;

  /// Wi-Fi debugging serials are `ip:port` (or `adb-xxx._adb-tls-connect`).
  bool get wireless => serial.contains(':') || serial.contains('_adb-tls');
  bool get ready => state == 'device';
}

/// The devices of `adb devices -l`.
List<AdbDevice> parseAdbDevices(String out) {
  final devices = <AdbDevice>[];
  for (final line in const LineSplitter().convert(out)) {
    final m = RegExp(
      r'^(\S+)\s+(device|unauthorized|offline|recovery|sideload)\b(.*)$',
    ).firstMatch(line.trim());
    if (m == null) continue;
    final model = RegExp(r'model:(\S+)').firstMatch(m.group(3)!)?.group(1);
    devices.add(AdbDevice(m.group(1)!, m.group(2)!, model: model));
  }
  return devices;
}

/// The serial whose `adb forward` maps host port [port] (what `flutter run`
/// sets up for the VM service), from `adb forward --list`.
String? serialForForwardedPort(String forwardList, int port) {
  for (final line in const LineSplitter().convert(forwardList)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length == 3 && parts[1] == 'tcp:$port') return parts[0];
  }
  return null;
}

/// One `adb forward` entry: `serial tcp:local tcp:remote`.
class AdbForward {
  const AdbForward(this.serial, this.local, this.remote);
  final String serial;
  final String local;
  final String remote;
}

List<AdbForward> parseAdbForwards(String out) => [
  for (final line in const LineSplitter().convert(out))
    if (line.trim().split(RegExp(r'\s+')) case [
      final serial,
      final local,
      final remote,
    ])
      AdbForward(serial, local, remote),
];

/// Runs `adb [-s serial] args`; null when it fails or times out.
Future<ProcessResult?> adb(
  String adbPath,
  String? serial,
  List<String> args, {
  Duration timeout = const Duration(seconds: 15),
  Encoding? stdoutEncoding = systemEncoding,
}) async {
  try {
    return await Process.run(adbPath, [
      if (serial != null) ...['-s', serial],
      ...args,
    ], stdoutEncoding: stdoutEncoding).timeout(timeout);
  } catch (_) {
    return null;
  }
}

/// A native view element from `uiautomator dump`.
class AndroidElement {
  const AndroidElement({
    required this.type,
    required this.label,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.enabled = true,
    this.clickable = false,
  });
  final String type;
  final String label;
  final int left, top, right, bottom;
  final bool enabled;
  final bool clickable;

  int get centerX => ((left + right) / 2).round();
  int get centerY => ((top + bottom) / 2).round();
}

String _unescapeXml(String s) => s
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(
        m.group(2)!,
        radix: m.group(1) == 'x' ? 16 : 10,
      );
      return code == null || code == 13 || code > 0x10FFFF
          ? ''
          : String.fromCharCode(code);
    })
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// The labelled elements of a `uiautomator dump` (XML, possibly followed by
/// the "UI hierchary dumped to" trailer).
List<AndroidElement> parseUiautomatorDump(String xml) {
  final elements = <AndroidElement>[];
  for (final node in RegExp(r'<node\s([^>]*?)/?>').allMatches(xml)) {
    final attrs = <String, String>{
      for (final a in RegExp(r'([\w-]+)="([^"]*)"').allMatches(node.group(1)!))
        a.group(1)!: _unescapeXml(a.group(2)!),
    };
    final bounds = RegExp(
      r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',
    ).firstMatch(attrs['bounds'] ?? '');
    if (bounds == null) continue;
    final text = (attrs['text'] ?? '').trim();
    final desc = (attrs['content-desc'] ?? '').trim();
    final label = text.isNotEmpty ? text : desc;
    final clickable = attrs['clickable'] == 'true';
    if (label.isEmpty) continue;
    elements.add(
      AndroidElement(
        type: (attrs['class'] ?? '?').split('.').last,
        label: label.replaceAll('\n', ' '),
        left: int.parse(bounds.group(1)!),
        top: int.parse(bounds.group(2)!),
        right: int.parse(bounds.group(3)!),
        bottom: int.parse(bounds.group(4)!),
        enabled: attrs['enabled'] != 'false',
        clickable: clickable,
      ),
    );
  }
  return elements;
}

/// One line per labelled element with its tap point, like the iOS tool.
String describeAndroidScreen(String xml) {
  final elements = parseUiautomatorDump(xml);
  if (elements.isEmpty) {
    return 'Nothing native on screen with a label (Flutter content is only '
        'listed when its semantics are on; use get_app_summary).';
  }
  final lines = [
    for (final e in elements)
      '- ${e.type} "${e.label}"${e.enabled ? '' : ' (disabled)'}'
          '${e.clickable ? ' (clickable)' : ''} → tap (${e.centerX}, ${e.centerY})',
  ];
  return '${lines.join('\n')}\nCoordinates are screen pixels (native_tap).';
}

/// `adb shell input text` goes through the device shell: spaces are `%s`,
/// shell characters are escaped. Null for text it cannot type (non-ASCII).
String? escapeAdbInputText(String text) {
  if (text.codeUnits.any((c) => c > 126 || (c < 32 && c != 10))) return null;
  final b = StringBuffer();
  for (final c in text.split('')) {
    if (c == ' ') {
      b.write('%s');
    } else if (c == '\n') {
      b.write('%s'); // newline needs KEYCODE_ENTER; typed as a space
    } else if (RegExp(r'''[\\'"`$&|;<>()*?\[\]{}~#!^]''').hasMatch(c)) {
      b.write('\\$c');
    } else {
      b.write(c);
    }
  }
  return "'${b.toString().replaceAll("'", r"'\''")}'";
}

/// Android keycodes for native_button.
const androidButtons = {
  'HOME': 'KEYCODE_HOME',
  'BACK': 'KEYCODE_BACK',
  'APP_SWITCH': 'KEYCODE_APP_SWITCH',
  'POWER': 'KEYCODE_POWER',
  'LOCK': 'KEYCODE_POWER',
  'SIDE_BUTTON': 'KEYCODE_POWER',
  'WAKEUP': 'KEYCODE_WAKEUP',
  'ENTER': 'KEYCODE_ENTER',
  'VOLUME_UP': 'KEYCODE_VOLUME_UP',
  'VOLUME_DOWN': 'KEYCODE_VOLUME_DOWN',
};

/// Whether a phone is awake and unlocked, and what else makes tests flaky.
class AndroidDeviceState {
  const AndroidDeviceState({
    this.awake,
    this.locked,
    this.batterySaver,
    this.charging,
    this.batteryLevel,
    this.screenOffTimeoutMs,
    this.foreground,
  });
  final bool? awake;
  final bool? locked;
  final bool? batterySaver;
  final bool? charging;
  final int? batteryLevel;
  final int? screenOffTimeoutMs;

  /// The package whose window has the focus: the app, a system dialog
  /// (`com.google.android.permissioncontroller`), the launcher.
  final String? foreground;

  /// Null when the device is fine to drive, else why not.
  String? get problem {
    if (awake == false) {
      return 'the screen is off (asleep)';
    }
    if (locked == true) return 'the device is locked';
    return null;
  }

  String describe() {
    final parts = <String>[
      if (awake != null) awake! ? 'screen on' : 'screen OFF',
      if (locked != null) locked! ? 'LOCKED' : 'unlocked',
      if (charging != null) charging! ? 'charging' : 'on battery',
      if (batteryLevel != null) '$batteryLevel%',
      if (batterySaver == true) 'battery saver ON',
      if (screenOffTimeoutMs != null)
        'dims after ${(screenOffTimeoutMs! / 1000).round()} s',
    ];
    return parts.join(', ');
  }
}

/// [power] is `dumpsys power`, [window] `dumpsys window`, [battery]
/// `dumpsys battery`; [lowPower] and [timeout] the `settings get` values.
AndroidDeviceState parseAndroidDeviceState({
  String power = '',
  String window = '',
  String battery = '',
  String lowPower = '',
  String timeout = '',
}) {
  final wake = RegExp(r'mWakefulness=(\w+)').firstMatch(power)?.group(1);
  // `dumpsys window` knows too, and is cheaper than `dumpsys power`.
  final windowAwake = RegExp(
    r'mAwake=(true|false)',
  ).firstMatch(window)?.group(1);
  bool? flag(String name) {
    final v = RegExp('$name=(true|false)').firstMatch(window)?.group(1);
    return v == null ? null : v == 'true';
  }

  final locked = flag('isKeyguardShowing') ?? flag('mShowingLockscreen');
  final powered = RegExp(
    r'(AC|USB|Wireless) powered: (true|false)',
  ).allMatches(battery).map((m) => m.group(2) == 'true').toList();
  return AndroidDeviceState(
    awake: wake != null
        ? wake == 'Awake'
        : (windowAwake == null ? null : windowAwake == 'true'),
    locked: locked,
    batterySaver: lowPower.trim() == '1'
        ? true
        : (lowPower.trim() == '0' ? false : null),
    charging: powered.isEmpty ? null : powered.any((p) => p),
    batteryLevel: int.tryParse(
      RegExp(r'level: (\d+)').firstMatch(battery)?.group(1) ?? '',
    ),
    screenOffTimeoutMs: int.tryParse(timeout.trim()),
    foreground: parseForegroundPackage(window),
  );
}

/// The package of `mCurrentFocus=Window{… u0 pkg/Activity}` in `dumpsys
/// window` output, null when nothing has the focus.
String? parseForegroundPackage(String window) => RegExp(
  r'mCurrentFocus=Window\{\S+ u\d+ ([\w.]+)[/}]',
).firstMatch(window)?.group(1);

/// Battery saver and the screen timeout change when the user opens settings,
/// not between calls: read them once a minute per device.
final _slowSettings =
    <String?, ({DateTime at, String lowPower, String timeout})>{};

/// Reads [AndroidDeviceState] from a connected device; null if adb fails.
/// One adb call with the filtering done on the phone. Measured on a phone:
/// five calls with whole `dumpsys` dumps took 550 ms; the window, the
/// battery and (once a minute) the two settings reads are about 250 ms.
Future<AndroidDeviceState?> readAndroidDeviceState(
  String adbPath,
  String? serial,
) async {
  final slow = _slowSettings[serial];
  final needSlow =
      slow == null || DateTime.now().difference(slow.at).inSeconds > 60;
  final script =
      'echo @@window; dumpsys window | grep -E '
      '"mAwake=|isKeyguardShowing|mShowingLockscreen|mCurrentFocus="; '
      'echo @@battery; dumpsys battery | grep -E "powered|level"'
      '${needSlow ? '; echo @@lowpower; settings get global low_power; '
                'echo @@timeout; settings get system screen_off_timeout' : ''}';
  final r = await adb(adbPath, serial, ['shell', script]);
  final out = r?.stdout as String?;
  if (r == null || r.exitCode != 0 || out == null || out.isEmpty) return null;
  final sections = splitSections(out);
  if ((sections['window'] ?? '').isEmpty) return null;
  if (needSlow) {
    _slowSettings[serial] = (
      at: DateTime.now(),
      lowPower: sections['lowpower'] ?? '',
      timeout: sections['timeout'] ?? '',
    );
  }
  final known = _slowSettings[serial];
  return parseAndroidDeviceState(
    window: sections['window'] ?? '',
    battery: sections['battery'] ?? '',
    lowPower: known?.lowPower ?? '',
    timeout: known?.timeout ?? '',
  );
}

/// `@@name` marker lines split [out] into named sections.
Map<String, String> splitSections(String out) {
  final sections = <String, StringBuffer>{};
  StringBuffer? current;
  for (final line in const LineSplitter().convert(out)) {
    if (line.startsWith('@@')) {
      current = sections[line.substring(2).trim()] = StringBuffer();
    } else {
      current?.writeln(line);
    }
  }
  return {for (final e in sections.entries) e.key: e.value.toString()};
}

/// The package behind process [pid] on the device (`/proc/<pid>/cmdline`),
/// which is the application id unless the app names its process.
Future<String?> androidPackageOfPid(
  String adbPath,
  String? serial,
  int pid,
) async {
  final r = await adb(adbPath, serial, ['shell', 'cat', '/proc/$pid/cmdline']);
  if (r == null || r.exitCode != 0) return null;
  final name = (r.stdout as String).split('\u0000').first.trim();
  return RegExp(r'^[\w.]+$').hasMatch(name) ? name : null;
}

/// Whether something on 127.0.0.1:[port] answers HTTP (any status): tells a
/// live `adb forward` from a stale one left by an earlier run.
Future<bool> portAnswersHttp(int port) async {
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

/// The VM service an Android app printed when it started, from
/// `adb logcat -d -v brief -s flutter:I`: the device port and auth token of
/// the last such line from process [pid]. Lets the server reach an app whose
/// `flutter run` (and its service proxy) died, e.g. when the cable dropped.
({int devicePort, String token})? parseVmServiceFromLogcat(
  String log,
  int pid,
) {
  ({int devicePort, String token})? found;
  final line = RegExp(
    r'\(\s*(\d+)\):.*Dart VM service is listening on '
    r'http://[\w.\[\]:]+?:(\d+)/([^\s/]+)/?',
  );
  for (final l in const LineSplitter().convert(log)) {
    final m = line.firstMatch(l);
    if (m == null || int.parse(m.group(1)!) != pid) continue;
    found = (devicePort: int.parse(m.group(2)!), token: m.group(3)!);
  }
  return found;
}
