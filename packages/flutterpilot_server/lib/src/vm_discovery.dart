import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _discoveryLog = Logger('VmDiscoveryService');

/// Finds the VM Service URI of a running Flutter app from the file
/// `flutter run --vmservice-out-file=.dart_tool/flutterpilot_vm_uri` writes
/// (what `flutterpilot dev` passes).
///
/// A plain `flutter run` writes nothing and listens on a random port behind
/// an auth code, so it can't be found; ports are not probed (any web server
/// on 8080 would pass for a VM service).
class VmDiscoveryService {
  /// Relative path of the URI file inside a Flutter project.
  static const uriFile = '.dart_tool/flutterpilot_vm_uri';

  /// What makes an app findable, for "no app" messages.
  static const howToStart =
      'Start the app with "flutterpilot dev" (or "flutter run '
      '--vmservice-out-file=$uriFile") in its project folder or under the '
      'workspace; FlutterPilot then finds it. A plain "flutter run" can\'t be '
      'found: call connect_app(uri: ...) with the VM service URI it prints.';

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
  static Future<String?> discover({
    List<Directory> roots = const [],
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final files = <File>[];
    for (final root in roots) {
      files.addAll(findUriFiles(root));
    }
    files.sort((a, b) => _modified(b).compareTo(_modified(a)));
    for (final file in files) {
      final uri = _read(file);
      if (uri != null && await _verifyVmUri(uri, timeout: timeout)) {
        _discoveryLog.info('Discovered VM Service URI in ${file.path}');
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

  /// Whether something answers at [rawUri] (a stale file names a dead port).
  static Future<bool> _verifyVmUri(
    String rawUri, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final client = HttpClient();
    final connectTimeout = Duration(
      milliseconds: (timeout.inMilliseconds * 0.4).round().clamp(100, 1000),
    );
    final responseTimeout = Duration(
      milliseconds: (timeout.inMilliseconds * 0.6).round().clamp(150, 2000),
    );
    client.connectionTimeout = connectTimeout;
    try {
      var uri = Uri.parse(rawUri);
      // flutter run writes the ws:// endpoint; probe its http:// root instead.
      if (uri.scheme.startsWith('ws')) {
        uri = uri.replace(
          scheme: uri.scheme == 'wss' ? 'https' : 'http',
          path: uri.path.replaceFirst(RegExp(r'ws/?$'), ''),
        );
      }
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(responseTimeout);
      return resp.statusCode == HttpStatus.ok ||
          resp.statusCode == HttpStatus.found;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
