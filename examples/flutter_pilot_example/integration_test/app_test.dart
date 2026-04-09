import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_pilot_example/main.dart' as app;

/// Integration test that navigates to every screen and verifies it loads
/// without throwing exceptions. This validates the complete example app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('All screens navigate without errors', (tester) async {
    // Fully await all plugin initializations before pumping the widget tree
    final widget = await app.initializeApp();
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(seconds: 2));

    // Dashboard must be visible
    expect(find.text('FlutterPilot Dashboard'), findsOneWidget);

    final screens = [
      ('nav_ui_automation_button', 'UI Automation'),
      ('nav_navigation_button', 'Navigation Features'),
      ('nav_debug_perf_button', 'Debug & Performance'),
      ('nav_accessibility_button', 'Accessibility'),
      ('nav_testing_button', 'Testing & Screenshots'),
      ('nav_state_button', 'State Injection'),
      ('nav_network_button', 'Network'),
      ('nav_storage_button', 'Storage'),
      ('nav_chaos_button', 'Chaos'),
    ];

    for (final (btnKey, screenLabel) in screens) {
      final btn = find.byKey(Key(btnKey));
      await tester.ensureVisible(btn);
      await tester.pump();

      await tester.tap(btn);
      // Use pump with duration instead of pumpAndSettle to avoid infinite-animation deadlock
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull,
          reason: '$screenLabel threw an exception on navigate');

      // Navigate back to dashboard
      final backBtn = find.byTooltip('Back');
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
  });
}
