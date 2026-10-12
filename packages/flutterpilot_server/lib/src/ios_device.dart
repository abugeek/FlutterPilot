import 'dart:convert';
import 'dart:io';

import 'phone_state.dart';

/// A physical iPhone's app and crash reports through `xcrun devicectl`
/// (idb drives simulators only).

/// The bundle id of the app that runs as process [pid]: the process's
/// `.app` folder from `devicectl device info processes` JSON, matched to
/// the installed app with that URL in `devicectl device info apps` JSON.
String? parseIosBundleId(String processesJson, String appsJson, int pid) {
  try {
    final processes =
        ((jsonDecode(processesJson) as Map)['result']
                as Map)['runningProcesses']
            as List;
    final executable = processes
        .whereType<Map>()
        .where((p) => p['processIdentifier'] == pid)
        .map((p) => '${p['executable']}')
        .firstOrNull;
    final end = executable?.indexOf('.app/') ?? -1;
    if (executable == null || end < 0) return null;
    final appUrl = executable.substring(0, end + 4);
    final apps =
        ((jsonDecode(appsJson) as Map)['result'] as Map)['apps'] as List;
    for (final app in apps.whereType<Map>()) {
      final url = '${app['url']}'.replaceAll(RegExp(r'/+$'), '');
      if (url == appUrl) return app['bundleIdentifier'] as String?;
    }
  } catch (_) {}
  return null;
}

/// The names of crash reports (`.ips`) in `devicectl device info files
/// --domain-type systemCrashLogs` JSON modified after [since], newest first.
List<String> recentCrashReportNames(String filesJson, DateTime since) {
  try {
    final files =
        ((jsonDecode(filesJson) as Map)['result'] as Map)['files'] as List;
    final recent = <({String name, DateTime time})>[];
    for (final f in files.whereType<Map>()) {
      final name = '${f['relativePath'] ?? f['name']}';
      final time = DateTime.tryParse(
        '${(f['metadata'] as Map?)?['lastModDate']}',
      );
      if (name.endsWith('.ips') && time != null && time.isAfter(since)) {
        recent.add((name: name, time: time));
      }
    }
    recent.sort((a, b) => b.time.compareTo(a.time));
    return [for (final r in recent) r.name];
  } catch (_) {
    return const [];
  }
}

Future<String?> _devicectl(List<String> args) async {
  try {
    final r = await Process.run('xcrun', [
      'devicectl',
      ...args,
      '--json-output',
      '-',
      '--timeout',
      '20',
    ]).timeout(const Duration(seconds: 30));
    return r.exitCode == 0 ? r.stdout as String : null;
  } catch (_) {
    return null;
  }
}

/// The connected iPhone running process [pid], and the bundle id of its app.
Future<({String device, String bundleId})?> findIosDeviceApp(int pid) async {
  if (!Platform.isMacOS) return null;
  final list = await _devicectl(['list', 'devices']);
  if (list == null) return null;
  for (final d in parseDevicectlDevices(list)) {
    if (!d.physical || !d.connected) continue;
    final processes = await _devicectl([
      'device',
      'info',
      'processes',
      '--device',
      d.identifier,
    ]);
    if (processes == null ||
        !RegExp('"processIdentifier"\\s*:\\s*$pid\\b').hasMatch(processes)) {
      continue;
    }
    final apps = await _devicectl([
      'device',
      'info',
      'apps',
      '--device',
      d.identifier,
    ]);
    final bundleId = apps == null
        ? null
        : parseIosBundleId(processes, apps, pid);
    if (bundleId != null) return (device: d.identifier, bundleId: bundleId);
  }
  return null;
}

/// Brings the app to the foreground on the iPhone, keeping its state.
Future<String?> launchOnIosDevice(String device, String bundleId) async {
  try {
    final r = await Process.run('xcrun', [
      'devicectl',
      'device',
      'process',
      'launch',
      '--device',
      device,
      bundleId,
    ]).timeout(const Duration(seconds: 30));
    return r.exitCode == 0 ? null : '${r.stderr}'.trim();
  } catch (e) {
    return '$e';
  }
}

/// Lists the phone's crash reports, copies the recent ones to a temp folder
/// and returns their contents (newest first).
Future<List<({String name, String content})>> recentIosCrashReports(
  String device,
  DateTime since, {
  int max = 5,
}) async {
  final files = await _devicectl([
    'device',
    'info',
    'files',
    '--device',
    device,
    '--domain-type',
    'systemCrashLogs',
  ]);
  if (files == null) return const [];
  final reports = <({String name, String content})>[];
  final dir = await Directory.systemTemp.createTemp('fp_ioscrash');
  try {
    for (final name in recentCrashReportNames(files, since).take(max)) {
      final dest = '${dir.path}/${name.replaceAll('/', '_')}';
      try {
        final r = await Process.run('xcrun', [
          'devicectl',
          'device',
          'copy',
          'from',
          '--device',
          device,
          '--domain-type',
          'systemCrashLogs',
          '--source',
          name,
          '--destination',
          dest,
        ]).timeout(const Duration(seconds: 30));
        if (r.exitCode == 0 && File(dest).existsSync()) {
          reports.add((name: name, content: File(dest).readAsStringSync()));
        }
      } catch (_) {}
    }
  } finally {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
  return reports;
}
