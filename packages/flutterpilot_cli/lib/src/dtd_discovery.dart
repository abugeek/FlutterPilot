// Keep in step with packages/flutterpilot_server/lib/src/dtd_discovery.dart
// (the CLI doesn't depend on the server).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A running Flutter app the Dart Tooling Daemon (DTD) knows: `flutter
/// run`, the IDEs and the official Dart MCP server's
/// `launch_app` all register their apps with one, so apps started without
/// FlutterPilot's URI file are found too.
class DtdApp {
  const DtdApp({
    required this.uri,
    required this.workspaceRoot,
    required this.started,
    this.package,
    this.kind,
  });

  /// The app's VM service (through DDS), e.g. `ws://127.0.0.1:1234/x=/ws`.
  final String uri;

  /// The folder the DTD was started for: the project for `flutter run`,
  /// the open workspace for an IDE.
  final String workspaceRoot;

  /// When the DTD started (its `flutter run` or IDE session).
  final DateTime started;

  /// From the name DTD gives the app: "Kind: Flutter - Device: macOS -
  /// Package: hn_reader".
  final String? package;
  final String? kind;

  /// Whether this app belongs under one of [roots]: the DTD's workspace is
  /// in a root, at most [maxDepth] folders down like the URI files, or a
  /// root is in it (an IDE workspace above the project, where the root's
  /// own package name has to match).
  bool isUnder(List<Directory> roots, {int maxDepth = 3}) {
    final workspace = _real(workspaceRoot);
    for (final root in roots) {
      final dir = _real(root.path);
      if (p.equals(dir, workspace)) return true;
      if (p.isWithin(dir, workspace) &&
          p.split(p.relative(workspace, from: dir)).length <= maxDepth) {
        return true;
      }
      if (p.isWithin(workspace, dir)) {
        final name = _packageName(dir);
        if (name == null || package == null || name == package) return true;
      }
    }
    return false;
  }

  /// The DTD records resolved paths (/private/var/… on macOS, where
  /// /var/… is a link to it).
  static String _real(String path) {
    final full = p.normalize(p.absolute(path));
    // The nearest folder that exists, with the rest appended.
    for (var dir = full; ; dir = p.dirname(dir)) {
      try {
        final real = Directory(dir).resolveSymbolicLinksSync();
        return dir == full ? real : p.join(real, p.relative(full, from: dir));
      } on FileSystemException {
        if (p.dirname(dir) == dir) return full;
      }
    }
  }

  static String? _packageName(String dir) {
    try {
      final pubspec = File(p.join(dir, 'pubspec.yaml')).readAsStringSync();
      return RegExp(
        r'^name:\s*([\w]+)',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
    } catch (_) {
      return null;
    }
  }
}

/// Finds apps through the DTD instances on this machine
/// (`dart tooling-daemon --list --machine`, then each one's
/// `ConnectedApp.getVmServices`).
class DtdDiscovery {
  static List<DtdApp>? _cached;
  static DateTime _cachedAt = DateTime(0);

  /// Discovery runs on every call while no app is connected: ask the
  /// daemons at most this often.
  static const cacheFor = Duration(seconds: 2);

  /// Flutter apps registered with any DTD; empty when there is no `dart`
  /// or no daemon.
  static Future<List<DtdApp>> apps({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final now = DateTime.now();
    if (_cached != null && now.difference(_cachedAt) < cacheFor) {
      return _cached!;
    }
    final found = <DtdApp>[];
    final diskInstances = instancesFromDisk();
    final instances = diskInstances.isNotEmpty
        ? diskInstances
        : parseInstances(await _listInstances(timeout));
    for (final instance in instances) {
      final services = await _vmServices(instance.wsUri, timeout);
      for (final s in services) {
        final app = appFrom(s, instance.workspaceRoot, instance.started);
        if (app != null) found.add(app);
      }
    }
    // If files on disk were stale (dead daemons), fall back to querying dart.
    if (found.isEmpty && diskInstances.isNotEmpty) {
      for (final instance in parseInstances(await _listInstances(timeout))) {
        final services = await _vmServices(instance.wsUri, timeout);
        for (final s in services) {
          final app = appFrom(s, instance.workspaceRoot, instance.started);
          if (app != null) found.add(app);
        }
      }
    }
    _cached = found;
    _cachedAt = DateTime.now();
    return found;
  }

  /// Known directories where DTD instances write their connection files.
  static List<Directory> get _instanceDirs {
    final home = Platform.environment['HOME'] ?? '';
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final appData = Platform.environment['APPDATA'];
    return [
      if (Platform.isMacOS && home.isNotEmpty)
        Directory(
          p.join(home, 'Library', 'Application Support', 'Dart', 'dtd'),
        ),
      if (Platform.isLinux) ...[
        if (xdg != null && xdg.isNotEmpty)
          Directory(p.join(xdg, 'dart', 'dtd')),
        if (home.isNotEmpty)
          Directory(p.join(home, '.local', 'share', 'dart', 'dtd')),
      ],
      if (Platform.isWindows) ...[
        if (localAppData != null && localAppData.isNotEmpty)
          Directory(p.join(localAppData, 'Dart', 'dtd')),
        if (appData != null && appData.isNotEmpty)
          Directory(p.join(appData, 'Dart', 'dtd')),
      ],
      if (!Platform.isWindows && home.isNotEmpty)
        Directory(p.join(home, '.dart-tool', 'dtd')),
    ];
  }

  /// Reads instances directly from the DTD state files on disk without
  /// spawning a process.
  static List<({String wsUri, String workspaceRoot, DateTime started})>
  instancesFromDisk([List<Directory>? dirs]) {
    final search = dirs ?? _instanceDirs;
    final instances =
        <({String wsUri, String workspaceRoot, DateTime started})>[];
    final seen = <String>{};
    for (final dir in search) {
      try {
        if (!dir.existsSync()) continue;
        for (final entry in dir.listSync()) {
          if (entry is! File) continue;
          try {
            final content = entry.readAsStringSync();
            final decoded = jsonDecode(content);
            if (decoded is Map &&
                decoded['wsUri'] is String &&
                decoded['workspaceRoot'] is String &&
                (decoded['workspaceRoot'] as String).isNotEmpty) {
              final wsUri = decoded['wsUri'] as String;
              if (seen.add(wsUri)) {
                instances.add((
                  wsUri: wsUri,
                  workspaceRoot: decoded['workspaceRoot'] as String,
                  started: DateTime.fromMillisecondsSinceEpoch(
                    decoded['epoch'] is int ? decoded['epoch'] as int : 0,
                  ),
                ));
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
    return instances;
  }

  /// The `--list --machine` output: one entry per daemon.
  static List<({String wsUri, String workspaceRoot, DateTime started})>
  parseInstances(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    return [
      if (decoded is List)
        for (final d in decoded)
          if (d is Map &&
              d['wsUri'] is String &&
              d['workspaceRoot'] is String &&
              (d['workspaceRoot'] as String).isNotEmpty)
            (
              wsUri: d['wsUri'] as String,
              workspaceRoot: d['workspaceRoot'] as String,
              started: DateTime.fromMillisecondsSinceEpoch(
                d['epoch'] is int ? d['epoch'] as int : 0,
              ),
            ),
    ];
  }

  /// An app from one `getVmServices` entry; null for a Dart (not Flutter)
  /// program.
  static DtdApp? appFrom(
    Map<String, dynamic> service,
    String workspaceRoot,
    DateTime started,
  ) {
    final uri = service['uri'];
    if (uri is! String || uri.isEmpty) return null;
    final name = '${service['name'] ?? ''}';
    final kind = RegExp(r'Kind: (\w+)').firstMatch(name)?.group(1);
    if (kind != null && kind != 'Flutter') return null;
    return DtdApp(
      uri: uri,
      workspaceRoot: workspaceRoot,
      started: started,
      package: RegExp(r'Package: (\w+)').firstMatch(name)?.group(1),
      kind: kind,
    );
  }

  /// A compiled server has no Dart of its own: the one it runs on under
  /// `dart run`, else Flutter's, else `dart` on PATH.
  static String get _dart {
    final self = Platform.resolvedExecutable;
    if (p.basenameWithoutExtension(self) == 'dart') return self;
    final flutter = Platform.environment['FLUTTER_ROOT'];
    if (flutter != null) {
      final dart = p.join(
        flutter,
        'bin',
        Platform.isWindows ? 'dart.bat' : 'dart',
      );
      if (File(dart).existsSync()) return dart;
    }
    return 'dart';
  }

  static Future<String> _listInstances(Duration timeout) async {
    try {
      final r = await Process.run(_dart, [
        'tooling-daemon',
        '--list',
        '--machine',
      ], runInShell: Platform.isWindows).timeout(const Duration(seconds: 15));
      return r.exitCode == 0 ? '${r.stdout}' : '';
    } catch (_) {
      return ''; // no dart, or one without the tooling daemon
    }
  }

  static Future<List<Map<String, dynamic>>> _vmServices(
    String wsUri,
    Duration timeout,
  ) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(wsUri).timeout(timeout);
      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': '1',
          'method': 'ConnectedApp.getVmServices',
        }),
      );
      final reply = await ws.first.timeout(timeout);
      final result = (jsonDecode('$reply') as Map)['result'];
      return [
        if (result is Map)
          for (final s in (result['vmServices'] as List? ?? const []))
            if (s is Map<String, dynamic>) s,
      ];
    } catch (_) {
      return const []; // a daemon without the ConnectedApp service
    } finally {
      await ws?.close();
    }
  }
}
