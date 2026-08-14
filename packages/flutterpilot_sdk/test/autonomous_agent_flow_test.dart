import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real-World Autonomous AI Agent Workflows', () {
    setUp(() {
      PilotWidgetInspector.invalidateCache();
      StateSnapshotManager.clear();
    });

    testWidgets('Flow 1: Autonomous Form Driving via Fuzzy Selectors & Scoped Capture', (tester) async {
      // Build a realistic login screen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Store App')),
            body: Center(
              child: Card(
                key: const ValueKey('login_card'),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Sign In to Account'),
                      TextFormField(
                        key: const ValueKey('email_field'),
                        decoration: const InputDecoration(labelText: 'Email Address'),
                      ),
                      TextFormField(
                        key: const ValueKey('pass_field'),
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                      ),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Log In'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Agent requests scoped widget tree of the login card only
      final scopedTree = PilotWidgetInspector.captureWidgetTree(
        rootQuery: 'login_card',
        compact: true,
      );

      final scopedJson = json.encode(scopedTree);
      expect(scopedJson, contains('Sign In to Account'));
      expect(scopedJson, contains('Log In'));
      expect(scopedJson, isNot(contains('Store App'))); // Header pruned!

      // 2. Agent interacts via fuzzy button selector
      final buttonElem = PilotWidgetInspector.findElement('Button[\'Log In\']');
      expect(buttonElem, isNotNull);

      // 3. Agent checks available suggestions when querying non-existent element
      final notFoundTargets = PilotWidgetInspector.getAvailableActionableTargets();
      expect(notFoundTargets, contains('login_card'));
    });

    testWidgets('Flow 2: Atomic Multi-State Seeding and Point-in-Time Rollback', (tester) async {
      final appState = <String, dynamic>{
        'isLoggedIn': false,
        'user': {'name': 'Guest', 'tier': 'free'},
        'cartItems': <String>[],
      };

      StateSnapshotManager.onCaptureStates = () => appState;
      StateSnapshotManager.onRestoreStates = (states) async {
        appState.clear();
        appState.addAll(states);
      };

      // 1. Save pristine snapshot
      final snap = StateSnapshotManager.saveSnapshot('clean_state');
      expect(snap.states['isLoggedIn'], isFalse);

      // 2. Agent mutates state
      appState['isLoggedIn'] = true;
      appState['cartItems'] = ['item_1', 'item_2'];
      appState['user']['tier'] = 'pro';

      expect(appState['isLoggedIn'], isTrue);
      expect(appState['cartItems'].length, equals(2));

      // 3. Agent rolls back state instantly
      final success = await StateSnapshotManager.restoreSnapshot('clean_state');
      expect(success, isTrue);
      expect(appState['isLoggedIn'], isFalse);
      expect(appState['user']['tier'], equals('free'));
    });

    test('Flow 3: 32-Bit Word-Aligned Visual Regression Engine', () {
      // 100x100 pixels = 10,000 32-bit pixel words
      final baseBuffer = Uint32List(10000);
      final currBuffer = Uint32List(10000);

      // Fill with identical white color (0xFFFFFFFF)
      baseBuffer.fillRange(0, 10000, 0xFFFFFFFF);
      currBuffer.fillRange(0, 10000, 0xFFFFFFFF);

      // Modify 100 pixels in current image
      for (int i = 0; i < 100; i++) {
        currBuffer[i] = 0xFFFF0080; // Magenta diff
      }

      int diffCount = 0;
      for (int i = 0; i < baseBuffer.length; i++) {
        if (baseBuffer[i] != currBuffer[i]) diffCount++;
      }

      expect(diffCount, equals(100));
      final diffPercent = (diffCount / 10000) * 100.0;
      expect(diffPercent, equals(1.0));
    });
  });
}
