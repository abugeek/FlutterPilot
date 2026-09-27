import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/ai_overlay_manager.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

void main() {
  testWidgets('AiOverlayManager showAction creates ripple without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Test Target'))),
      ),
    );

    expect(find.text('Test Target'), findsOneWidget);

    // Trigger AI action ripple
    AiOverlayManager.showAction(const Offset(100, 100), 'Tap');
    await tester.pump();

    // Verify AI badge appeared
    expect(find.text('🤖 Tap'), findsOneWidget);

    // Pump past the dismiss timer (700ms)
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('🤖 Tap'), findsNothing);
  });

  testWidgets(
    'the badge is invisible to the inspector and clearNow removes it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TextButton(onPressed: () {}, child: const Text('Save')),
            ),
          ),
        ),
      );
      AiOverlayManager.showAction(const Offset(100, 100), 'Save');
      await tester.pump();
      expect(find.text('🤖 Save'), findsOneWidget);

      final tree = PilotWidgetInspector.captureWidgetTree().toString();
      expect(tree, isNot(contains('🤖')));
      expect(PilotWidgetInspector.findElement('🤖 Save'), isNull);
      expect(
        PilotWidgetInspector.getInteractiveElements().map((e) => e['text']),
        ['Save'],
      );

      AiOverlayManager.clearNow();
      await tester.pump();
      expect(find.text('🤖 Save'), findsNothing);
      await tester.pump(const Duration(milliseconds: 800)); // timer is a no-op
    },
  );
}
