import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  // Octana's tank card draws its fill level with a LinearProgressIndicator:
  // every action on that screen was answered with "still loading".
  testWidgets('a progress bar with a value is a gauge, not loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LinearProgressIndicator(value: 0.62)),
      ),
    );
    expect(FlutterPilot.debugProgressShowing(), isFalse);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CircularProgressIndicator())),
    );
    expect(FlutterPilot.debugProgressShowing(), isTrue);
  });
}
