import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _discoveryLog = Logger('VmDiscoveryService');

/// Service to automatically discover the Dart VM Service URI of a running Flutter app.
class VmDiscoveryService {
  /// Probes local files and active ports to discover a running VM Service URI.
  static Future<String?> discover({
    Directory? projectRoot,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // 1. Check project .dart_tool directory for service files
    final fromFiles = await _checkProjectFiles(projectRoot);
    if (fromFiles != null) {
      _discoveryLog.info(
        'Discovered VM Service URI from project file: $fromFiles',
      );
      return fromFiles;
    }

    // 2. Check /tmp or temp directory for flutter service info files
    final fromTemp = await _checkTempFiles();
    if (fromTemp != null) {
      _discoveryLog.info('Discovered VM Service URI from temp file: $fromTemp');
      return fromTemp;
    }

    // 3. Probe common localhost ports for active Dart VM services
    final fromProbe = await _probeLocalhostPorts(timeout: timeout);
    if (fromProbe != null) {
      _discoveryLog.info(
        'Discovered VM Service URI via localhost probe: $fromProbe',
      );
      return fromProbe;
    }

    return null;
  }

  static Future<String?> _checkProjectFiles(Directory? root) async {
    if (root == null || !root.existsSync()) return null;

    final candidates = [
      p.join(root.path, '.dart_tool', 'service_info.json'),
      p.join(root.path, '.dart_tool', 'daemon.json'),
      p.join(root.path, '.dart_tool', 'flutter_service_info.json'),
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          final parsed = jsonDecode(content);
          if (parsed is Map) {
            final uri =
                parsed['uri'] ?? parsed['serviceUri'] ?? parsed['vmServiceUri'];
            if (uri is String && uri.isNotEmpty && await _verifyVmUri(uri)) {
              return uri;
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<String?> _checkTempFiles() async {
    try {
      final tempDir = Directory.systemTemp;
      if (!tempDir.existsSync()) return null;

      final entities = tempDir.listSync();
      for (final entity in entities) {
        if (entity is File &&
            (entity.path.contains('flutter_service_info') ||
                entity.path.contains('dart_vm_service'))) {
          try {
            final content = await entity.readAsString();
            final parsed = jsonDecode(content);
            if (parsed is Map) {
              final uri = parsed['uri'] ?? parsed['serviceUri'];
              if (uri is String && uri.isNotEmpty && await _verifyVmUri(uri)) {
                return uri;
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _probeLocalhostPorts({
    required Duration timeout,
  }) async {
    // Check standard Dart / Flutter VM service ports first
    final primaryPorts = [8181, 5858, 8080, 8081, 9100, 9101];

    for (final port in primaryPorts) {
      final uri = 'http://127.0.0.1:$port/';
      if (await _verifyVmUri(uri)) {
        return uri;
      }
    }
    return null;
  }

  /// Verifies if a given URI points to an active Dart VM service.
  static Future<bool> _verifyVmUri(String rawUri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 300);
    try {
      final uri = Uri.parse(rawUri);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(milliseconds: 400));
      if (resp.statusCode == HttpStatus.ok ||
          resp.statusCode == HttpStatus.found) {
        return true;
      }
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
    return false;
  }
}
