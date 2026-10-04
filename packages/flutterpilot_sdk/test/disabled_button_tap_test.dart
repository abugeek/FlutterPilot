import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

class CustomAppButton extends StatelessWidget {
  const CustomAppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  bool get enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final tap = enabled ? onPressed : null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: FilledButton(onPressed: tap, child: Text(label)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final print = debugPrint;
    FlutterPilot.initialize();
    debugPrint = print;
  });

  Future<ServiceExtensionResponse> callTap(
    WidgetTester tester, {
    required String target,
    String? gesture,
  }) async {
    final method = switch (gesture) {
      'double' => 'ext.flutterpilot.doubleTapWidget',
      'long' => 'ext.flutterpilot.longPressWidget',
      _ => 'ext.flutterpilot.tapWidget',
    };
    return tester
        .runAsync(() async {
          final call = FlutterPilot.debugCallExtension(method, {'key': target});
          var done = false;
          call.whenComplete(() => done = true);
          while (!done) {
            await tester.pump(const Duration(milliseconds: 16));
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          return call;
        })
        .then((r) => r!);
  }

  testWidgets('tapping a disabled ElevatedButton by label returns an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: null, child: Text('Submit')),
        ),
      ),
    );

    final res = await callTap(tester, target: 'Submit');
    expect(res.isError(), isTrue);
    expect(res.errorDetail, contains('is disabled and cannot be tapped'));
  });

  testWidgets('tapping a disabled ElevatedButton by key returns an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            key: Key('submit_btn'),
            onPressed: null,
            child: Text('Submit'),
          ),
        ),
      ),
    );

    final res = await callTap(tester, target: 'submit_btn');
    expect(res.isError(), isTrue);
    expect(res.errorDetail, contains('is disabled and cannot be tapped'));
  });

  testWidgets('tapping a disabled IconButton returns an error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IconButton(
            key: Key('add_btn'),
            onPressed: null,
            icon: Icon(Icons.add),
          ),
        ),
      ),
    );

    final res = await callTap(tester, target: 'add_btn');
    expect(res.isError(), isTrue);
    expect(res.errorDetail, contains('is disabled and cannot be tapped'));
  });

  testWidgets(
    'tapping a disabled Octana-style CustomAppButton returns an error',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomAppButton(
              key: Key('next_btn'),
              label: 'Next',
              onPressed: null,
            ),
          ),
        ),
      );

      // Tapping by text
      final textRes = await callTap(tester, target: 'Next');
      expect(textRes.isError(), isTrue);
      expect(textRes.errorDetail, contains('is disabled and cannot be tapped'));

      // Tapping by key
      final keyRes = await callTap(tester, target: 'next_btn');
      expect(keyRes.isError(), isTrue);
      expect(keyRes.errorDetail, contains('is disabled and cannot be tapped'));
    },
  );

  testWidgets('tapping an enabled button succeeds', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => pressed = true,
            child: const Text('Save'),
          ),
        ),
      ),
    );

    final res = await callTap(tester, target: 'Save');
    expect(res.isError(), isFalse);
    final jsonResult = jsonDecode(res.result!);
    expect(jsonResult['status'], 'success');
    expect(pressed, isTrue);
  });

  testWidgets('doubleTap and longPress on a disabled button return errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: null, child: Text('Options')),
        ),
      ),
    );

    final doubleRes = await callTap(
      tester,
      target: 'Options',
      gesture: 'double',
    );
    expect(doubleRes.isError(), isTrue);
    expect(doubleRes.errorDetail, contains('is disabled and cannot be tapped'));

    final longRes = await callTap(tester, target: 'Options', gesture: 'long');
    expect(longRes.isError(), isTrue);
    expect(longRes.errorDetail, contains('is disabled and cannot be tapped'));
  });
}
