import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'dtd_discovery.dart';

final _discoveryLog = Logger('VmDiscoveryService');

/// Finds the VM Service URI of a running Flutter app: from the file
/// `flutter run --vmservice-out-file=.dart_tool/flutterpilot_vm_uri` writes
/// (what `flutterpilot dev` passes), or from the Dart Tooling Daemon that a
/// plain `flutter run`, an IDE or the Dart MCP server's `launch_app`
/// registers the app with ([DtdDiscovery]).
///
/// Ports are not probed (any web server on 8080 would pass for a VM
/// service).
class VmDiscoveryService {
  /// Relative path of the URI file inside a Flutter project.
  static const uriFile = '.dart_tool/flutterpilot_vm_uri';

  /// What makes an app findable, for "no app" messages.
  static const howToStart =
      'Start the app with "flutter run" (or "flutterpilot dev", your IDE, or '
      "the Dart MCP server's launch_app) in its project folder or under the "
      'workspace; FlutterPilot then finds it. Otherwise call '
      'connect_app(uri: ...) with the VM service URI "flutter run" prints.';

  /// How deep below each root to look for a Flutter project (a workspace
  /// root is often a monorepo: `apps/mobile/`).
  static const maxDepth = 3;

  /// Stops a scan of a huge root (a home folder) early.
  static const _maxDirs = 3000;

  static const _skipDirs = {'build', 'node_modules', 'Pods'};

  /// A Flutter project's own folders, which never hold another app.
  static const _projectDirs = {
    'ios',
    'android',
    'macos',
    'linux',
    'windows',
    'web',
    'lib',
    'test',
  };

  /// Returns the URI of a running app found under [roots] — the most
  /// recently launched one when several are running — or null.
  /// [dtdApps] defaults to asking the machine's tooling daemons.
  static Future<String?> discover({
    List<Directory> roots = const [],
    Duration timeout = const Duration(seconds: 1),
    Future<List<DtdApp>> Function()? dtdApps,
  }) async {
    final found = <({String? uri, DateTime launched, String from})>[];
    for (final root in roots) {
      for (final file in findUriFiles(root)) {
        found.add((
          uri: _read(file),
          launched: _modified(file),
          from: file.path,
        ));
      }
    }
    if (roots.isNotEmpty) {
      for (final app in await (dtdApps ?? DtdDiscovery.apps)()) {
        if (!app.isUnder(roots, maxDepth: maxDepth)) continue;
        found.add((
          uri: app.uri,
          launched: app.started,
          from: 'the Dart Tooling Daemon for ${app.workspaceRoot}',
        ));
      }
    }
    found.sort((a, b) => b.launched.compareTo(a.launched));
    for (final f in found) {
      final uri = f.uri;
      if (uri != null && await _verifyVmUri(uri, timeout: timeout)) {
        _discoveryLog.info('Discovered VM Service URI in ${f.from}');
        return uri;
      }
    }
    return null;
  }

  /// URI files under [root], down to [maxDepth] directories below it.
  static List<File> findUriFiles(Directory root) {
    final found = <File>[];
    if (!root.existsSync()) return found;
    var visited = 0;
    void scan(Directory dir, int depth) {
      if (visited++ > _maxDirs) return;
      final file = File(p.join(dir.path, uriFile));
      if (file.existsSync()) found.add(file);
      if (depth >= maxDepth) return;
      List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } catch (_) {
        return; // unreadable (permissions)
      }
      final isProject = File(p.join(dir.path, 'pubspec.yaml')).existsSync();
      for (final child in children) {
        final name = p.basename(child.path);
        if (child is Directory &&
            !name.startsWith('.') &&
            !_skipDirs.contains(name) &&
            !(isProject && _projectDirs.contains(name))) {
          scan(child, depth + 1);
        }
      }
    }

    scan(root.absolute, 0);
    return found;
  }

  static DateTime _modified(File f) {
    try {
      return f.lastModifiedSync();
    } catch (_) {
      return DateTime(0);
    }
  }

  static String? _read(File file) {
    try {
      final content = file.readAsStringSync().trim();
      return content.startsWith('http') || content.startsWith('ws')
          ? content
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether something listens at [rawUri]'s host and port: a stale file
  /// names a port nothing listens on any more. (Not an HTTP probe: the web
  /// debug proxy, DWDS, doesn't answer one.)
  static Future<bool> _verifyVmUri(
    String rawUri, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    try {
      final uri = Uri.parse(rawUri);
      if (!uri.hasPort) return false;
      final socket = await Socket.connect(uri.host, uri.port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
