import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

void main() {
  List<String> labels() => [
    for (final e in PilotWidgetInspector.getInteractiveElements())
      '${e['text'] ?? e['key'] ?? e['type']}',
  ];

  // Field case (a POS app): a GestureDetector around the whole shell was
  // the first tappable element, labelled with every loose text on screen.
  testWidgets('a handler around the whole screen is not one of its controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          onTap: () {},
          child: Scaffold(
            body: Column(
              children: [
                const Text("TODAY'S REVENUE"),
                const Text('0 so\'m'),
                ElevatedButton(onPressed: () {}, child: const Text('Sales')),
                ElevatedButton(onPressed: () {}, child: const Text('Stock')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(labels(), ['Sales', 'Stock']);
  });

  testWidgets('a screen that is one big tap target is still listed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          onTap: () {},
          child: const Scaffold(body: Center(child: Text('Tap to continue'))),
        ),
      ),
    );

    expect(labels(), ['Tap to continue']);
  });

  testWidgets(
    'a keyed handler around the screen is kept: it can be asked for',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            key: const Key('dismiss_keyboard'),
            onTap: () {},
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('OK'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(labels(), contains('OK'));
      expect(
        PilotWidgetInspector.getInteractiveElements().map((e) => e['key']),
        contains('dismiss_keyboard'),
      );
    },
  );
}
