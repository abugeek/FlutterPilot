import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final print = debugPrint;
    FlutterPilot.initialize();
    debugPrint = print;
  });

  // wait_for and navigate_to end with this, as an action's response does.
  testWidgets('screenNow lists what is tappable and whether it is loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ElevatedButton(
                key: const Key('save'),
                onPressed: () {},
                child: const Text('Save'),
              ),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );

    final response = await tester.runAsync(
      () => FlutterPilot.debugCallExtension('ext.flutterpilot.screenNow', {}),
    );
    final post =
        (jsonDecode(response!.result!) as Map)['postActionState'] as Map;

    expect(post['interactiveElementsCount'], 1);
    expect(post['visibleInteractiveElements'], ['Save [save]']);
    expect(post['loading'], isTrue);
    expect(post['newErrorCount'], 0);
  });
}
