import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

void main() {
  group('PilotWidgetInspector', () {
    testWidgets('captures widget tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Hello'),
                ElevatedButton(
                  key: const Key('submit_button'),
                  onPressed: () {},
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      );

      final tree = PilotWidgetInspector.captureWidgetTree();
      
      expect(tree, isNotNull);
      // In a test environment, the root might be RootWidget or View
      expect(tree.toString(), contains('MaterialApp'));
      
      // Verify button exists in tree
      String treeString = tree.toString();
      expect(treeString, contains('ElevatedButton'));
      expect(treeString, contains('submit_button'));
    });

    testWidgets('findElementByKey finds widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              key: const Key('my_container'),
              child: const Text('Test'),
            ),
          ),
        ),
      );

      final element = PilotWidgetInspector.findElementByKey('my_container');
      
      expect(element, isNotNull);
      expect(element!.widget, isA<Container>());
    });

    testWidgets('countElements counts correctly', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Text('1'),
              Text('2'),
            ],
          ),
        ),
      );

      final root = tester.element(find.byType(Column));
      final count = PilotWidgetInspector.countElements(root);
      
      // Column + 2 Text widgets + their internal children (RichText, etc.)
      expect(count, greaterThanOrEqualTo(3));
    });
  });
}
