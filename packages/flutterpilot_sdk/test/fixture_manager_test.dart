import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_sdk/src/fixture_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    FixtureManager.clear();
    tempDir = Directory.systemTemp.createTempSync('flutterpilot-fixtures-');
  });

  tearDown(() {
    FixtureManager.clear();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('truncates oversized response bodies', () {
    FixtureManager.recordInteraction(
      name: 'bounded',
      method: 'GET',
      url: 'https://example.test/data',
      statusCode: 200,
      responseBody: List.filled(
        FixtureManager.maxResponseBodyBytes + 100,
        'x',
      ).join(),
    );

    final file = FixtureManager.saveFixtureToDisk(
      name: 'bounded',
      baseDir: tempDir.path,
    );
    final decoded = jsonDecode(file.readAsStringSync()) as List;
    expect(decoded.single['bodyTruncated'], isTrue);
    expect(
      (decoded.single['body'] as String).length,
      lessThanOrEqualTo(FixtureManager.maxResponseBodyBytes + 1),
    );
  });

  test('rejects unsafe fixture names', () {
    expect(
      () => FixtureManager.saveFixtureToDisk(
        name: '../escape',
        baseDir: tempDir.path,
      ),
      throwsArgumentError,
    );
  });
}
