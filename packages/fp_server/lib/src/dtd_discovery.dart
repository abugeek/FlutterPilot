// Keep in step with packages/flutterpilot_cli/lib/src/dtd_discovery.dart
// (doctor uses it; the CLI doesn't depend on the server).
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
        if (FileSystemEntity.isLinkSync(dir)) {
          final target = _resolveLink(dir);
          final resolved = dir == full
              ? target
              : p.join(target, p.relative(full, from: dir));
          return _real(resolved);
        }
        final real = Directory(dir).resolveSymbolicLinksSync();
        return dir == full ? real : p.join(real, p.relative(full, from: dir));
      } on FileSystemException {
        if (p.dirname(dir) == dir) return full;
      }
    }
  }

  static String _resolveLink(String path) {
    var cur = path;
    var hops = 0;
    while (FileSystemEntity.isLinkSync(cur) && hops++ < 10) {
      try {
        final target = Link(cur).targetSync();
        cur = p.isAbsolute(target)
            ? target
            : p.normalize(p.join(p.dirname(cur), target));
      } catch (_) {
        break;
      }
    }
    return cur;
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
    for (final instance in parseInstances(await _listInstances(timeout))) {
      final services = await _vmServices(instance.wsUri, timeout);
      for (final s in services) {
        final app = appFrom(s, instance.workspaceRoot, instance.started);
        if (app != null) found.add(app);
      }
    }
    _cached = found;
    _cachedAt = DateTime.now();
    return found;
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
      ], runInShell: Platform.isWindows).timeout(timeout * 3);
      return r.exitCode == 0 ? '${r.stdout}' : '';
    } catch (_) {
      return ''; // no dart, or one without the tooling daemon
    }
  }

  static Future<List<Map<String, dynamic>>> _vmServices(
    String wsUri,
    Duration timeout,
  ) async => (await _query(wsUri, timeout)).services;

  /// `ConnectedApp.getVmServices` on one daemon, with the raw reply or the
  /// error for [report].
  static Future<({List<Map<String, dynamic>> services, String said})> _query(
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
      final reply = '${await ws.first.timeout(timeout)}';
      final result = (jsonDecode(reply) as Map)['result'];
      return (
        services: [
          if (result is Map)
            for (final s in (result['vmServices'] as List? ?? const []))
              if (s is Map<String, dynamic>) s,
        ],
        said: reply,
      );
    } catch (e) {
      // A daemon without the ConnectedApp service.
      return (services: const <Map<String, dynamic>>[], said: '$e');
    } finally {
      await ws?.close();
    }
  }

  /// Why discovery found (or missed) an app under [roots]: each daemon, what
  /// it answered and whether its apps count as under the roots. For the e2e
  /// test's failure output.
  static Future<List<String>> report(
    List<Directory> roots, {
    Duration timeout = const Duration(seconds: 5),
    String? listing,
  }) async {
    final lines = <String>[];
    final instances = parseInstances(listing ?? await _listInstances(timeout));
    if (instances.isEmpty) lines.add('no daemon listed');
    for (final instance in instances) {
      final q = await _query(instance.wsUri, timeout);
      lines.add(
        'daemon ${instance.wsUri} for ${instance.workspaceRoot} '
        '(real: ${DtdApp._real(instance.workspaceRoot)}) said: '
        '${q.said.length > 400 ? '${q.said.substring(0, 400)}…' : q.said}',
      );
      for (final s in q.services) {
        final app = appFrom(s, instance.workspaceRoot, instance.started);
        lines.add(
          app == null
              ? '  skipped (not Flutter): ${s['name']}'
              : '  ${app.package ?? '?'} at ${app.uri}: under roots '
                    '${roots.map((r) => DtdApp._real(r.path)).join(', ')}: '
                    '${app.isUnder(roots)}',
        );
      }
    }
    return lines;
  }
}
