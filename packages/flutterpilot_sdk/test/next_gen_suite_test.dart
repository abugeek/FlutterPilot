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

  });
}
