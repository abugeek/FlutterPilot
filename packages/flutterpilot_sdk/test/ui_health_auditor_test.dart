import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('UiHealthAuditor', () {
    testWidgets('reports an overflowing Row once, not once per wrapper', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: Row(children: [SizedBox(width: 300, height: 10)]),
            ),
          ),
        ),
      );
      tester.takeException(); // the overflow FlutterError itself

      final report = UiHealthAuditor.audit();
      expect(report['overflowCount'], 1);
      expect((report['overflows'] as List).single['type'], 'Row');
    });

    testWidgets('flags each undersized control once', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const SizedBox(width: 20, height: 20),
              ),
            ),
          ),
        ),
      );

      final report = UiHealthAuditor.audit();
      expect(report['accessibilityIssueCount'], 1);
      expect(report['overflowCount'], 0);
    });

    testWidgets('standard Material controls pass', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ElevatedButton(onPressed: () {}, child: const Text('Save')),
                IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                const TextField(),
              ],
            ),
          ),
        ),
      );

      expect(UiHealthAuditor.audit()['isHealthy'], isTrue);
    });
  });
}
