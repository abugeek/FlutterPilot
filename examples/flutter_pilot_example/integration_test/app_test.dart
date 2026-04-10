import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_pilot_example/main.dart' as app;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Navigate to a screen by tapping its dashboard tile, wait for transition.
Future<void> _goTo(WidgetTester tester, String tileKey) async {
  final btn = find.byKey(Key(tileKey));
  await tester.ensureVisible(btn);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(btn);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Tap the AppBar back button and wait for the dashboard to reappear.
Future<void> _goBack(WidgetTester tester) async {
  final back = find.byTooltip('Back');
  expect(back, findsOneWidget, reason: 'Back button should always be present on sub-screens');
  await tester.tap(back);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Tap a widget by key and wait for any resulting rebuild / animation.
Future<void> _tap(WidgetTester tester, String key,
    {Duration settle = const Duration(milliseconds: 400)}) async {
  final w = find.byKey(Key(key));
  await tester.ensureVisible(w);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(w);
  await tester.pump(settle);
}

/// Scroll the first [Scrollable] on-screen by [dy] logical pixels.
Future<void> _scroll(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
  await tester.pump(const Duration(milliseconds: 400));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Widget rootWidget;

  setUpAll(() async {
    rootWidget = await app.initializeApp();
  });

  Future<void> launchApp(WidgetTester tester) async {
    await tester.pumpWidget(rootWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('FlutterPilot Dashboard'), findsOneWidget,
        reason: 'Dashboard should be the initial screen');
  }

  // ── 1. UI Automation ──────────────────────────────────────────────────────
  testWidgets('UI Automation: text fields, switches, checkboxes, scroll', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_ui_automation_button');
    expect(find.text('UI Automation Tools'), findsOneWidget);

    // Type into main text field
    await tester.enterText(find.byKey(const Key('main_text_field')), 'Hello FlutterPilot');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Value: "Hello FlutterPilot"'), findsOneWidget,
        reason: 'Entered text should appear as a live preview');

    // Type into search field
    await tester.enterText(find.byKey(const Key('search_field')), 'flutter');
    await tester.pump(const Duration(milliseconds: 300));

    // Clear the main text field
    await _tap(tester, 'clear_main_text_button');
    expect(find.text('No text entered yet'), findsOneWidget,
        reason: 'After clearing, preview should reset');

    // Dismiss keyboard
    await _tap(tester, 'unfocus_button');

    // Toggle the Notifications switch (it's a SwitchListTile, just tap it)
    await tester.ensureVisible(find.byKey(const Key('notifications_switch')));
    await tester.pump();
    await _tap(tester, 'notifications_switch');

    // Toggle dark-mode switch
    await tester.ensureVisible(find.byKey(const Key('dark_mode_switch')));
    await _tap(tester, 'dark_mode_switch');

    // Toggle auto-save checkbox
    await tester.ensureVisible(find.byKey(const Key('auto_save_checkbox')));
    await _tap(tester, 'auto_save_checkbox');

    // Scroll the outer screen down to the scrollable list section
    await _scroll(tester, -400);
    await _scroll(tester, -400);

    // The "Find Me" tile lives inside an inner ListView (lazy, so it may not
    // be in the tree yet). Use scrollUntilVisible to drive the inner list.
    final scrollableList = find.byKey(const Key('scrollable_list'));
    await tester.ensureVisible(scrollableList);
    await tester.pump(const Duration(milliseconds: 200));

    final findMe = find.byKey(const Key('find_me_tile'));
    await tester.scrollUntilVisible(findMe, 60,
        scrollable: find.descendant(
          of: scrollableList,
          matching: find.byType(Scrollable),
        ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(findMe, findsOneWidget, reason: '"Find Me" tile should be reachable by scrolling');

    // Tap "Find Me" to log the interaction
    await tester.tap(findMe);
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 2. Accessibility ──────────────────────────────────────────────────────
  testWidgets('Accessibility: text scale, semantics toggle, enable/disable form', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_accessibility_button');
    expect(find.text('Accessibility'), findsOneWidget);

    // Tap the "Large 1.5x" scale preset
    await _tap(tester, 'scale_1_5_button', settle: const Duration(milliseconds: 400));

    // Tap "XL 2.0x" preset, wait for text to rescale
    await _tap(tester, 'scale_2_0_button', settle: const Duration(milliseconds: 400));

    // Back to normal
    await _tap(tester, 'scale_1_0_button', settle: const Duration(milliseconds: 400));

    // Scroll to semantics section
    await _scroll(tester, -200);
    await tester.ensureVisible(find.byKey(const Key('show_semantic_labels_switch')));
    // Toggle semantic labels overlay on
    await _tap(tester, 'show_semantic_labels_switch');
    // Toggle back off
    await _tap(tester, 'show_semantic_labels_switch');

    // Scroll to form enabled section
    await _scroll(tester, -200);
    await tester.ensureVisible(find.byKey(const Key('form_enabled_switch')));

    // Verify submit button is initially enabled
    final submitBtn = tester.widget<ElevatedButton>(find.byKey(const Key('submit_button')));
    expect(submitBtn.onPressed, isNotNull, reason: 'submit_button should start enabled');

    // Disable the form
    await _tap(tester, 'form_enabled_switch');
    final submitBtnDisabled = tester.widget<ElevatedButton>(find.byKey(const Key('submit_button')));
    expect(submitBtnDisabled.onPressed, isNull, reason: 'submit_button should be disabled when form is off');

    // Re-enable
    await _tap(tester, 'form_enabled_switch');

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 3. Testing & Screenshots ───────────────────────────────────────────────
  testWidgets('Testing: screenshot buttons, recording toggle, pump counter', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_testing_button');
    expect(find.text('Testing & Screenshots'), findsOneWidget);

    // Screenshot tool buttons (log-only, no crash expected)
    await _tap(tester, 'capture_screenshot_button');
    await _tap(tester, 'save_baseline_button');
    await _tap(tester, 'compare_screenshot_button');

    // Start and stop recording
    await _tap(tester, 'start_recording_button', settle: const Duration(milliseconds: 500));
    expect(find.text('Recording...'), findsOneWidget,
        reason: 'Recording status should update after start');
    await _tap(tester, 'stop_recording_button', settle: const Duration(milliseconds: 500));
    expect(find.text('Not Recording'), findsOneWidget,
        reason: 'Recording status should reset after stop');

    // Scroll to pump_frames section
    await _scroll(tester, -300);
    await tester.ensureVisible(find.byKey(const Key('increment_counter_button')));

    // Increment counter several times
    for (var i = 0; i < 5; i++) {
      await _tap(tester, 'increment_counter_button', settle: const Duration(milliseconds: 200));
    }
    final counterLabel = tester.widget<Text>(find.byKey(const Key('pump_counter_label')));
    expect(counterLabel.data, contains('5'),
        reason: 'Counter should show 5 after 5 taps');

    // Tap pump_frames button
    await _tap(tester, 'pump_frames_button', settle: const Duration(milliseconds: 500));

    // Scroll to more tools
    await _scroll(tester, -200);
    await _tap(tester, 'get_crash_report_button');
    await _tap(tester, 'list_custom_tools_button');
    await _tap(tester, 'call_custom_tool_button');
    await _tap(tester, 'hot_reload_button');

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 4. Debug & Performance ────────────────────────────────────────────────
  testWidgets('Debug & Performance: logs, toggles', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_debug_perf_button');
    expect(find.text('Debug & Performance'), findsOneWidget);

    // Emit some debug logs
    await _tap(tester, 'emit_logs_button');
    await _tap(tester, 'emit_logs_button');

    // Scroll to toggles
    await _scroll(tester, -300);
    await tester.ensureVisible(find.byKey(const Key('perf_overlay_switch')));

    // Toggle performance overlay on/off
    await _tap(tester, 'perf_overlay_switch', settle: const Duration(milliseconds: 400));
    await _tap(tester, 'perf_overlay_switch', settle: const Duration(milliseconds: 400));

    // Repaint rainbow
    await tester.ensureVisible(find.byKey(const Key('repaint_rainbow_switch')));
    await _tap(tester, 'repaint_rainbow_switch', settle: const Duration(milliseconds: 400));
    await _tap(tester, 'repaint_rainbow_switch', settle: const Duration(milliseconds: 400));

    // Debug paint
    await tester.ensureVisible(find.byKey(const Key('debug_paint_switch')));
    await _tap(tester, 'debug_paint_switch', settle: const Duration(milliseconds: 400));
    await _tap(tester, 'debug_paint_switch', settle: const Duration(milliseconds: 400));

    // Slow animations
    await tester.ensureVisible(find.byKey(const Key('slow_animations_switch')));
    await _tap(tester, 'slow_animations_switch', settle: const Duration(milliseconds: 400));
    await _tap(tester, 'slow_animations_switch', settle: const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 5. Navigation Features ────────────────────────────────────────────────
  testWidgets('Navigation: theme toggle, locale, orientation buttons', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_navigation_button');
    expect(find.text('Navigation Features'), findsOneWidget);

    // Theme toggle
    await _tap(tester, 'theme_toggle_button', settle: const Duration(milliseconds: 500));
    await _tap(tester, 'theme_toggle_button', settle: const Duration(milliseconds: 500));

    // Scroll to locale section
    await _scroll(tester, -250);
    await tester.ensureVisible(find.byKey(const Key('locale_dropdown')));

    // Orientation buttons
    await _scroll(tester, -250);
    final portraitBtn = find.byKey(const Key('portrait_button'));
    if (portraitBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(portraitBtn);
      await _tap(tester, 'portrait_button', settle: const Duration(milliseconds: 400));
      await _tap(tester, 'landscape_button', settle: const Duration(milliseconds: 400));
    }

    // Delayed navigate button
    await _scroll(tester, -300);
    final delayedBtn = find.byKey(const Key('delayed_nav_button'));
    if (delayedBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(delayedBtn);
      await tester.tap(delayedBtn);
      // wait for the 1-second delay then route push
      await tester.pump(const Duration(seconds: 2));
      // navigate back from wherever it pushed to
      final back = find.byTooltip('Back');
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back);
        await tester.pump(const Duration(milliseconds: 600));
      }
    }

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 6. State Injection ────────────────────────────────────────────────────
  testWidgets('State Injection: increment counters', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_state_button');

    // Increment the first counter (bloc)
    final blocIncrBtn = find.byKey(const Key('bloc_increment_button'));
    if (blocIncrBtn.evaluate().isNotEmpty) {
      final before = tester.widget<Text>(find.byKey(const Key('bloc_count_text'))).data ?? '';
      await tester.tap(blocIncrBtn);
      await tester.pump(const Duration(milliseconds: 400));
      final after = tester.widget<Text>(find.byKey(const Key('bloc_count_text'))).data ?? '';
      expect(before, isNot(after), reason: 'Bloc counter should increment');
    }

    // Increment riverpod or provider counter if present
    final providerIncrBtn = find.byKey(const Key('provider_increment_button'));
    if (providerIncrBtn.evaluate().isNotEmpty) {
      await tester.tap(providerIncrBtn);
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 7. Network ────────────────────────────────────────────────────────────
  testWidgets('Network: fetch posts, users, 404 error', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_network_button');
    expect(find.text('Network & Logs'), findsOneWidget);

    // Trigger POST fetch (will fail in test env — we just verify no crash)
    await _tap(tester, 'fetch_posts_button', settle: const Duration(seconds: 2));
    // Verify log list is rendered
    await tester.ensureVisible(find.byKey(const Key('network_log_list')));

    await _tap(tester, 'fetch_users_button', settle: const Duration(seconds: 2));
    await _tap(tester, 'fetch_404_button', settle: const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 8. Storage (Hive) ─────────────────────────────────────────────────────
  testWidgets('Storage: save and seed data', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_storage_button');
    expect(find.text('Storage (Hive)'), findsOneWidget);

    // Type a key and value
    await tester.enterText(find.byKey(const Key('storage_key_field')), 'test_key');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const Key('storage_value_field')), 'hello_world');
    await tester.pump(const Duration(milliseconds: 200));

    // Save it
    await _tap(tester, 'storage_save_button', settle: const Duration(milliseconds: 600));

    // Seed demo data
    await _tap(tester, 'seed_demo_data_button', settle: const Duration(milliseconds: 800));

    // Verify entries list is visible
    final entriesList = find.byKey(const Key('storage_entries_list'));
    await tester.ensureVisible(entriesList);
    expect(entriesList, findsOneWidget);

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });

  // ── 10. Connectivity ─────────────────────────────────────────────────────
  testWidgets('Connectivity: status display, offline toggle, history', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_connectivity_button');
    expect(find.text('Connectivity'), findsOneWidget);

    // Connectivity status should be visible
    expect(find.byKey(const Key('connectivity_status_label')), findsOneWidget);

    // Toggle simulate offline switch on
    await tester.ensureVisible(find.byKey(const Key('simulate_offline_switch')));
    await _tap(tester, 'simulate_offline_switch',
        settle: const Duration(milliseconds: 400));
    expect(find.text('Offline simulation ACTIVE'), findsOneWidget,
        reason: 'After toggle, simulation should be active');

    // Toggle simulate offline switch off
    await _tap(tester, 'simulate_offline_switch',
        settle: const Duration(milliseconds: 400));
    expect(find.text('Simulation off'), findsOneWidget,
        reason: 'After second toggle, simulation should be off');

    // Clear history
    await _tap(tester, 'clear_history_button',
        settle: const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });
  // ── 11. Chaos ─────────────────────────────────────────────────────────────
  testWidgets('Chaos: screen loads with error trigger buttons visible', (tester) async {
    await launchApp(tester);
    await _goTo(tester, 'nav_chaos_button');
    expect(find.text('Chaos & Self-Heal'), findsOneWidget);

    // Verify the crash-trigger buttons are present and tappable.
    // We do NOT trigger them — they intentionally throw unhandled exceptions
    // which cause pending-frame assertion failures in the test binding.
    expect(find.byKey(const Key('trigger_sync_error_button')), findsOneWidget,
        reason: 'Sync error button should be visible');
    expect(find.byKey(const Key('trigger_async_error_button')), findsOneWidget,
        reason: 'Async error button should be visible');

    await _goBack(tester);
  });
}
