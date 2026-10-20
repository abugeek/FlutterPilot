import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fp_sdk/fp_sdk.dart';

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

    testWidgets('flags a vertical list with no room to show its content', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 260),
                // Landscape-phone shape: the header ate the window.
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    itemCount: 20,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 60, child: Text('$i')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final report = UiHealthAuditor.audit();
      expect(report['crampedScrollableViewCount'], 1);
      final finding = (report['crampedScrollables'] as List).single as Map;
      expect('${finding['details']}', contains('shows 40 dp'));
      expect(report['isHealthy'], isFalse);
    });

    testWidgets('does not flag a list with room', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: 20,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
            ),
          ),
        ),
      );

      expect(UiHealthAuditor.audit()['crampedScrollableViewCount'], 0);
    });

    testWidgets('does not flag a short list that nearly fits', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 260),
                SizedBox(
                  height: 100,
                  child: ListView(
                    children: const [
                      SizedBox(height: 55),
                      SizedBox(height: 55),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(UiHealthAuditor.audit()['crampedScrollableViewCount'], 0);
    });

    testWidgets('flags a label cut by maxLines', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              child: Text(
                'Starting cash amount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );

      final report = UiHealthAuditor.audit();
      expect(report['clippedTextCount'], 1);
      expect(
        ((report['clippedText'] as List).single as Map)['text'],
        contains('Starting cash'),
      );
    });
  });
}
