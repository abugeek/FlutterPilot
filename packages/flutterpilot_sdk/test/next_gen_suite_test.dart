import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('Next-Gen Autonomous Suite Tests', () {
    testWidgets(
      'finder never guesses: near-misses and ambiguous substrings fail',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Create New Account'),
                  ),
                  TextButton(onPressed: () {}, child: const Text('Save draft')),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Save and exit'),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(
          PilotWidgetInspector.findElement('Create New Account'),
          isNotNull,
        );
        // A similar label is not the same button; report not-found instead.
        expect(PilotWidgetInspector.findElement('Create Account'), isNull);
        // Unique substring is fine.
        expect(PilotWidgetInspector.findElement('New Account'), isNotNull);
        // Two different buttons contain "Save": refuse and explain.
        expect(PilotWidgetInspector.findElement('Save'), isNull);
        expect(PilotWidgetInspector.lastAmbiguity, contains('Save draft'));
      },
    );

    testWidgets('finder ignores routes covered by an opaque route', (
      tester,
    ) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('Home page')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Details')),
        ),
      );
      await tester.pumpAndSettle();

      expect(PilotWidgetInspector.findElement('Details'), isNotNull);
      expect(PilotWidgetInspector.findElement('Home page'), isNull);
    });
  });
}
