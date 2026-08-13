import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

void main() {
  group('PilotWidgetInspector Semantic Selectors', () {
    testWidgets('finds widget by explicit Key and ValueKey', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                ElevatedButton(
                  key: Key('submit_btn'),
                  onPressed: null,
                  child: Text('Submit'),
                ),
                Text('Hello World', key: ValueKey('greeting')),
              ],
            ),
          ),
        ),
      );

      final el1 = PilotWidgetInspector.findElement('submit_btn');
      expect(el1, isNotNull);
      expect(el1!.widget, isA<ElevatedButton>());

      final el2 = PilotWidgetInspector.findElement('greeting');
      expect(el2, isNotNull);
      expect(el2!.widget, isA<Text>());
    });

    testWidgets('finds button by semantic selector and button text without keys', (
      WidgetTester tester,
    ) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  onPressed: () => tapCount++,
                  child: const Text('Log In'),
                ),
                TextButton(
                  onPressed: () => tapCount += 2,
                  child: const Text('Forgot Password?'),
                ),
              ],
            ),
          ),
        ),
      );

      // 1. Structured selector
      final el1 = PilotWidgetInspector.findElement("ElevatedButton['Log In']");
      expect(el1, isNotNull);
      expect(el1!.widget, isA<ElevatedButton>());

      // 2. Generic button selector
      final el2 = PilotWidgetInspector.findElement("Button['Forgot Password?']");
      expect(el2, isNotNull);
      expect(el2!.widget, isA<TextButton>());

      // 3. Plain text query matching enclosing button
      final el3 = PilotWidgetInspector.findElement('Log In');
      expect(el3, isNotNull);
      expect(el3!.widget, isA<ElevatedButton>());
    });

    testWidgets('finds TextField by placeholder or type selector', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final el = PilotWidgetInspector.findElement("TextField['Enter your email']");
      expect(el, isNotNull);
    });

    testWidgets('finds widget by Tooltip message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IconButton(
              tooltip: 'Settings',
              onPressed: () {},
              icon: const Icon(Icons.settings),
            ),
          ),
        ),
      );

      final el = PilotWidgetInspector.findElement("Tooltip['Settings']");
      expect(el, isNotNull);
    });

    testWidgets('captures selector and text fields in widget tree JSON', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                ElevatedButton(
                  onPressed: null,
                  child: Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      );

      final tree = PilotWidgetInspector.captureWidgetTree(maxDepth: 250);
      expect(tree, isNotNull);
      expect(tree['error'], isNull);

      // Verify that tree contains selector
      bool foundSelector = false;
      void checkNode(Map<String, dynamic> node) {
        if (node['selector'] != null &&
            node['selector'].toString().contains('ElevatedButton')) {
          foundSelector = true;
          expect(node['selector'], equals("ElevatedButton['Create Account']"));
        }
        for (final child in node['children'] as List? ?? []) {
          checkNode(child as Map<String, dynamic>);
        }
      }

      checkNode(tree);
      expect(foundSelector, isTrue);
    });
  });
}
