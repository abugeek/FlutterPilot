import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('Agent Superpowers Tests', () {
    testWidgets('UiHealthAuditor detects small touch targets (<48x48)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    key: const ValueKey('tiny_button'),
                    icon: const Icon(Icons.close),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      expect(audit['accessibilityIssueCount'], greaterThanOrEqualTo(1));
      expect(audit['isHealthy'], isFalse);
      final issues = audit['accessibilityIssues'] as List;
      expect(
        issues.any((i) => i['target'].toString().contains('tiny_button')),
        isTrue,
      );
    });

    testWidgets('UiHealthAuditor reports healthy on standard Material layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('standard_button'),
                onPressed: () {},
                child: const Text('Submit'),
              ),
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      expect(audit['overflowCount'], equals(0));
    });
  });
}
