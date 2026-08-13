import 'dart:convert';
import 'dart:io';

/// Records and replays HTTP/Dio network fixtures for offline testing.
class FixtureManager {
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
    _recordedFixtures.putIfAbsent(name, () => []);
    _recordedFixtures[name]!.add({
      'method': method,
      'url': url,
      'statusCode': statusCode,
      'body': responseBody is String ? responseBody : json.encode(responseBody),
      'headers': headers ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Exports recorded fixture to disk.
  static File saveFixtureToDisk({
    required String name,
    String baseDir = 'test/fixtures',
  }) {
    final list = _recordedFixtures[name] ?? [];
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/$name.json');
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(list));
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
