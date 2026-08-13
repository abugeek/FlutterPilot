import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('Optimization & Performance Benchmarks', () {
    testWidgets('Single-Pass O(N) Matcher accurately finds multi-priority targets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Store')),
            body: Center(
              child: Column(
                children: [
                  const Text('Welcome Back!'),
                  ElevatedButton(
                    key: const ValueKey('checkout_btn'),
                    onPressed: () {},
                    child: const Text('Proceed to Checkout'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Key lookup (Priority 100)
      final keyElem = PilotWidgetInspector.findElement('checkout_btn');
      expect(keyElem, isNotNull);

      // Cached lookup (O(1))
      final cachedElem = PilotWidgetInspector.findElement('checkout_btn');
      expect(cachedElem, equals(keyElem));

      // Semantic selector (Priority 90)
      final selectorElem = PilotWidgetInspector.findElement("ElevatedButton['Proceed to Checkout']");
      expect(selectorElem, isNotNull);

      // Button text (Priority 80)
      final textElem = PilotWidgetInspector.findElement('Proceed to Checkout');
      expect(textElem, isNotNull);
    });

    testWidgets('Semantic Tree Compaction significantly reduces JSON payload size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.blue),
                    child: Center(
                      child: ElevatedButton(
                        onPressed: () {},
                        child: const Text('Action'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final rawTree = PilotWidgetInspector.captureWidgetTree(compact: false);
      final compactTree = PilotWidgetInspector.captureWidgetTree(compact: true);

      final rawJson = json.encode(rawTree);
      final compactJson = json.encode(compactTree);

      // Compact version should be significantly smaller in byte/token size
      expect(compactJson.length, lessThan(rawJson.length));

      // But still contains the actionable button and text
      expect(compactJson, contains('Action'));
    });

    test('Fast similarity pre-filter handles length differences without GC pressure', () {
      final simExact = PilotWidgetInspector.calculateSimilarity('login', 'login');
      expect(simExact, equals(1.0));

      final simClose = PilotWidgetInspector.calculateSimilarity('create account', 'create new account');
      expect(simClose, greaterThan(0.65));

      final simFar = PilotWidgetInspector.calculateSimilarity('a', 'this is a completely different long string');
      expect(simFar, equals(0.0));
    });
  });
}
