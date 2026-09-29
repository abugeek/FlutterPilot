import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/interaction_manager.dart';

void main() {
  // A slow CI simulator took over 150 ms for two frames: the wait gave up
  // first and the response read the screen before the change.
  testWidgets('waits for two frames even when they are slow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('x')));
    var done = false;
    InteractionManager.waitForTwoFrames().then((_) => done = true);

    await tester.pump(const Duration(milliseconds: 200));
    expect(done, isFalse, reason: 'one frame is not enough');
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, isTrue);
  });

  testWidgets('gives up when no frame comes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('x')));
    var done = false;
    InteractionManager.waitForTwoFrames(
      timeout: const Duration(milliseconds: 300),
    ).then((_) => done = true);
    // Time passes without frames.
    await tester.binding.delayed(const Duration(milliseconds: 400));
    expect(done, isTrue);
  });
}
