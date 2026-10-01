import 'dart:async';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// What a device's VM service reports about the app running there.
class DeviceInfo {
  const DeviceInfo({required this.platform, this.app, required this.hasSdk});

  /// `macos`, `ios`, `android`, `web`, ...
  final String platform;

  /// The app's package name, from its root library.
  final String? app;

  /// Whether the app registers flutterpilot_sdk's extensions.
  final bool hasSdk;

  @override
  String toString() => [
    platform,
    ?app,
    hasSdk ? 'flutterpilot_sdk' : 'zero-code (inspect only)',
  ].join(' · ');
}

/// The ws:// endpoint for any form of VM service address a developer is
/// likely to paste: the `http://host:port/token=/` line `flutter run` prints,
/// the `ws://.../ws` URI, or a DevTools URL carrying `?uri=`. Null when [raw]
/// is none of these.
String? normalizeVmServiceUri(String raw) {
  var uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final embedded = uri.queryParameters['uri'];
  if (embedded != null) return normalizeVmServiceUri(embedded);
  final scheme = switch (uri.scheme) {
    'http' || 'ws' => 'ws',
    'https' || 'wss' => 'wss',
    _ => null,
  };
  if (scheme == null) return null;
  var path = uri.path;
  if (!path.endsWith('/ws')) {
    path = '${path.endsWith('/') ? path : '$path/'}ws';
  }
  uri = uri.replace(scheme: scheme, path: path, query: null, fragment: null);
  return uri.toString().replaceFirst(RegExp(r'\?$'), '');
}

/// Connects to the VM service at [uri], without vm_service's keep-alive.
///
/// Since 15.1.0 `vmServiceConnectUri` pings every 15 s and closes the
/// connection when no pong comes back within another 15 s. A slow hot
/// reload or a busy simulator stalls flutter's DDS for longer than that
/// while the app is still there: on CI the connection was "lost" 30 s into
/// such a step. A connection that is really gone closes by itself.
Future<VmService> connectVmService(String uri) =>
    vmServiceConnectUri(uri, pingInterval: null);

/// Connects to [uri] just long enough to see what runs there. Throws when
/// nothing answers within [timeout].
Future<DeviceInfo> probeDevice(
  String uri, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final vm = await connectVmService(uri).timeout(timeout);
  try {
    return await () async {
      final info = await vm.getVM();
      String? app;
      var hasSdk = false;
      for (final ref in info.isolates ?? const []) {
        final isolate = await vm.getIsolate(ref.id!);
        final root = isolate.rootLib?.uri;
        if (root != null && root.startsWith('package:')) {
          app ??= root.substring(8).split('/').first;
        }
        hasSdk |=
            isolate.extensionRPCs?.any(
              (e) => e.startsWith('ext.flutterpilot.'),
            ) ??
            false;
      }
      return DeviceInfo(
        platform: info.targetCPU == 'Web'
            ? 'web'
            : info.operatingSystem ?? 'unknown',
        app: app,
        hasSdk: hasSdk,
      );
    }().timeout(timeout);
  } finally {
    unawaited(vm.dispose());
  }
}

/// Manages multiple running Flutter instances across devices (iOS, Android, Web).
class FleetManager {
  final Map<String, String> _devices = {};
  String? _activeDeviceId;

  /// Registers or updates a device with its VM Service URI. An entry already
  /// holding [uri] under another name is renamed to [name] (e.g. the app
  /// FlutterPilot found on its own, "default"), keeping it active if it was.
  /// Returns that previous name, if any.
  String? registerDevice(String name, String uri) {
    final previous = _devices.entries
        .where((e) => e.key != name && e.value == uri)
        .map((e) => e.key)
        .firstOrNull;
    if (previous != null) {
      _devices.remove(previous);
      if (_activeDeviceId == previous) _activeDeviceId = name;
    }
    _devices[name] = uri;
    _activeDeviceId ??= name;
    return previous;
  }

  /// Sets the currently active device.
  bool switchDevice(String name) {
    if (_devices.containsKey(name)) {
      _activeDeviceId = name;
      return true;
    }
    return false;
  }

  /// Returns the VM Service URI of the active device.
  String? get activeUri =>
      _activeDeviceId != null ? _devices[_activeDeviceId] : null;

  /// Returns the ID/name of the currently active device.
  String? get activeDeviceId => _activeDeviceId;

  /// Returns the registered VM-service URI for [name], if present.
  String? uriFor(String name) => _devices[name];

  /// The registered device whose URI is [uri], if any.
  String? idForUri(String uri) =>
      _devices.entries.where((e) => e.value == uri).firstOrNull?.key;

  Iterable<String> get deviceIds => _devices.keys;

  /// `host:port` of a VM service URI: enough to tell devices apart without
  /// repeating its auth token.
  static String shortUri(String rawUri) {
    final uri = Uri.tryParse(rawUri);
    return uri == null || uri.host.isEmpty ? rawUri : '${uri.host}:${uri.port}';
  }

  /// One line per device: what runs there, or that nothing answers.
  String describe(Map<String, DeviceInfo?> probes) {
    if (_devices.isEmpty) {
      return 'No devices. Start the app with "flutter run" (FlutterPilot '
          'finds it), or call register_device(id, uri) with the VM service '
          'URI flutter run prints.';
    }
    final lines = [
      for (final MapEntry(key: id, value: uri) in _devices.entries)
        '- $id${id == _activeDeviceId ? ' (active)' : ''}: '
            '${probes[id] ?? 'not running (app stopped, or restarted on a new port: register_device again with the new URI)'}'
            ' — ${shortUri(uri)}',
    ];
    return '${lines.join('\n')}\n'
        'Every tool targets the active device; switch_device(id) changes it.';
  }

  /// Lists all registered devices and the active status.
  Map<String, dynamic> listDevices() => {
    'activeDevice': _activeDeviceId,
    'devices': [
      for (final e in _devices.entries)
        {
          'id': e.key,
          'uri': shortUri(e.value),
          'isActive': e.key == _activeDeviceId,
        },
    ],
    'total': _devices.length,
  };
}
