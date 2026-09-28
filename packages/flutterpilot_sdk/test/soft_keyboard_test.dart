import 'dart:convert';
import 'dart:developer' show ServiceExtensionResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final print = debugPrint;
    FlutterPilot.initialize();
    // initialize() routes debugPrint through its log buffer; widget tests
    // require the test binding's back. The extensions stay registered.
    debugPrint = print;
  });

  /// A phone-sized screen with the keyboard up: the Scaffold shrinks the
  /// body, so the button at the bottom is clipped (as on a 320x640 phone).
  Future<List<String>> setUpKeyboardScreen(
    WidgetTester tester, {
    bool keyboardCloses = true,
  }) async {
    final taps = <String>[];
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        if (call.method == 'TextInput.hide' && keyboardCloses) {
          tester.view.viewInsets = FakeViewPadding.zero;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(),
              const SizedBox(height: 400),
              ElevatedButton(
                onPressed: () => taps.add('Bottom'),
                child: const Text('Bottom'),
              ),
            ],
          ),
        ),
      ),
    );
    tester.takeException(); // the keyboard makes the column overflow
    return taps;
  }

  Future<ServiceExtensionResponse> tap(WidgetTester tester, String target) =>
      tester
          .runAsync(() async {
            final call = FlutterPilot.debugCallExtension(
              'ext.flutterpilot.tapWidget',
              {'key': target},
            );
            var done = false;
            call.whenComplete(() => done = true);
            while (!done) {
              await tester.pump(const Duration(milliseconds: 16));
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            return call;
          })
          .then((r) => r!);

  testWidgets('isVisible follows the view insets', (tester) async {
    await setUpKeyboardScreen(tester);
    expect(SoftKeyboard.isVisible, isTrue);
    tester.view.viewInsets = FakeViewPadding.zero;
    expect(SoftKeyboard.isVisible, isFalse);
  });

  testWidgets('a tap closes the keyboard to reach a button under it', (
    tester,
  ) async {
    final taps = await setUpKeyboardScreen(tester);
    final res = await tap(tester, 'Bottom');
    expect(res.isError(), isFalse, reason: res.errorDetail);
    expect(taps, ['Bottom']);
    expect(SoftKeyboard.isVisible, isFalse);
    expect(
      (jsonDecode(res.result!) as Map)['note'],
      contains('Closed the on-screen keyboard'),
    );
  });

  testWidgets('if the keyboard stays, the error says it is the keyboard', (
    tester,
  ) async {
    final taps = await setUpKeyboardScreen(tester, keyboardCloses: false);
    final res = await tap(tester, 'Bottom');
    expect(res.isError(), isTrue);
    expect(res.errorDetail, contains('on-screen keyboard covers it'));
    expect(taps, isEmpty);
  });
}
