import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('Next-Gen Autonomous Suite Tests', () {
    testWidgets('Fuzzy semantic matching resolves slight copy variations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Create New Account'),
              ),
            ),
          ),
        ),
      );

      // Exact substring match
      final exact = PilotWidgetInspector.findElement('Create New Account');
      expect(exact, isNotNull);

      // Fuzzy / similarity match
      final similarity = PilotWidgetInspector.calculateSimilarity('Create Account', 'Create New Account');
      expect(similarity, greaterThanOrEqualTo(0.7));

      final fuzzyElement = PilotWidgetInspector.findElement('Create Account');
      expect(fuzzyElement, isNotNull);
    });

    testWidgets('ChaosFuzzer executes random monkey stress events', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Target'),
              ),
            ),
          ),
        ),
      );

      final report = await ChaosFuzzer.run(
        maxEvents: 3,
      );

      expect(report['status'], equals('passed'));
      expect(report['eventsExecuted'], greaterThanOrEqualTo(1));
    });

    testWidgets('MemoryAuditor audits image cache and warnings', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Hello'),
          ),
        ),
      );

      final audit = MemoryAuditor.audit();
      expect(audit['isHealthy'], isTrue);
      expect(audit['imageCache'], isNotNull);
      expect(audit['warningsCount'], equals(0));
    });

    test('FixtureManager records and exports fixtures', () {
      FixtureManager.clear();
      FixtureManager.recordInteraction(
        name: 'test_checkout',
        method: 'POST',
        url: '/api/v1/checkout',
        statusCode: 200,
        responseBody: {'orderId': '12345'},
      );

      final tempDir = Directory.systemTemp.createTempSync('pilot_fixtures');
      final file = FixtureManager.saveFixtureToDisk(
        name: 'test_checkout',
        baseDir: tempDir.path,
      );

      expect(file.existsSync(), isTrue);
      final loaded = FixtureManager.loadFixtureFromDisk(
        name: 'test_checkout',
        baseDir: tempDir.path,
      );
      expect(loaded.length, equals(1));
      expect(loaded.first['url'], equals('/api/v1/checkout'));

      tempDir.deleteSync(recursive: true);
    });

    test('PrReportGenerator generates valid GitHub Markdown report', () {
      final md = PrReportGenerator.generate(
        title: 'Fix Navigation Bug',
        description: 'Fixed bottom sheet not dismissing on back press.',
        gifPath: 'artifacts/session.gif',
        generatedTestPath: 'integration_test/flow_test.dart',
      );

      expect(md, contains('# 🚀 Fix Navigation Bug'));
      expect(md, contains('Autonomous Quality & Screen Health Audit'));
      expect(md, contains('Layout Overflows'));
      expect(md, contains('![Session Replay](artifacts/session.gif)'));
      expect(md, contains('`integration_test/flow_test.dart`'));
    });
  });
}
