import 'dart:convert';
import 'dart:io';

/// Records and replays HTTP/Dio network fixtures for offline testing.
class FixtureManager {
  static const int maxRecordedInteractions = 5000;
  static const int maxResponseBodyBytes = 1024 * 1024;
  static const int maxFixtureFileBytes = 8 * 1024 * 1024;
  static final Map<String, List<Map<String, dynamic>>> _recordedFixtures = {};

  /// Adds a network interaction to the in-memory recording.
  static void recordInteraction({
    required String name,
    required String method,
    required String url,
    required int statusCode,
    required dynamic responseBody,
    Map<String, String>? headers,
  }) {
    final fixtures = _recordedFixtures.values.fold<int>(
      0,
      (count, entries) => count + entries.length,
    );
    if (fixtures >= maxRecordedInteractions) return;
    final encodedBody = responseBody is String
        ? responseBody
        : json.encode(responseBody);
    final bodyBytes = utf8.encode(encodedBody);
    final body = bodyBytes.length <= maxResponseBodyBytes
        ? encodedBody
        : '${utf8.decode(bodyBytes.take(maxResponseBodyBytes).toList(), allowMalformed: true)}…';
    _recordedFixtures.putIfAbsent(name, () => []);
    _recordedFixtures[name]!.add({
      'method': method,
      'url': url,
      'statusCode': statusCode,
      'body': body,
      if (bodyBytes.length > maxResponseBodyBytes) 'bodyTruncated': true,
      'headers': headers ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Exports recorded fixture to disk.
  static File saveFixtureToDisk({
    required String name,
    String baseDir = 'test/fixtures',
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'must be a safe fixture name');
    }
    final list = _recordedFixtures[name] ?? [];
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final encoded = const JsonEncoder.withIndent('  ').convert(list);
    final bytes = utf8.encode(encoded);
    if (bytes.length > maxFixtureFileBytes) {
      throw StateError(
        'Fixture "$name" exceeds the $maxFixtureFileBytes-byte limit',
      );
    }
    final file = File('${dir.path}/$name.json');
    file.writeAsStringSync(encoded);
    return file;
  }

  /// Loads fixture from disk and returns interaction rules.
  static List<Map<String, dynamic>> loadFixtureFromDisk({
    required String name,
    String baseDir = 'test/fixtures',
  }) {
    final file = File('$baseDir/$name.json');
    if (!file.existsSync()) return [];
    try {
      final decoded = json.decode(file.readAsStringSync()) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Clears in-memory fixtures.
  static void clear() => _recordedFixtures.clear();
}
