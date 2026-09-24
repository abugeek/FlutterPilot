import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  testWidgets('InteractionManager tapAt executes without throwing and triggers button',
      (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => tapped = true,
              child: const Text('Click Me'),
            ),
          ),
        ),
      ),
    );

    final buttonCenter = tester.getCenter(find.text('Click Me'));
    await InteractionManager.tapAt(buttonCenter);
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('HitTestUtils verifies hittable elements accurately',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                key: const ValueKey('hidden_under_barrier'),
                child: const Text('Background Text'),
              ),
              ModalBarrier(dismissible: false, color: Colors.black54),
            ],
          ),
        ),
      ),
    );

    final element = PilotWidgetInspector.findElement('hidden_under_barrier');
    expect(element, isNotNull);
    // Because ModalBarrier is in front of it, the background element is not hittable!
    expect(HitTestUtils.isElementHittable(element!), isFalse);
  });

  testWidgets('PilotWidgetInspector.getInteractiveElements finds visible button',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('submitBtn'),
              onPressed: () {},
              child: const Text('Submit Form'),
            ),
          ),
        ),
      ),
    );

    final elements = PilotWidgetInspector.getInteractiveElements();
    expect(elements, isNotEmpty);
    final btn = elements.firstWhere((e) => e['key'] == 'submitBtn');
    expect(btn['text'], contains('Submit Form'));
    expect(btn['bounds'], isNotNull);
  });
}
