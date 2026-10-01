import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  test('the hidden-window pump renders every tick only while busy', () {
    int rendered({required bool busy, required bool animating}) => [
      for (var t = 1; t <= 60; t++)
        if (pumpRendersTick(t, busy: busy, animating: animating)) t,
    ].length;
    expect(rendered(busy: true, animating: false), 60);
    expect(rendered(busy: false, animating: true), 60);
    // Waiting for the agent's next call: ~10 Hz.
    expect(rendered(busy: false, animating: false), 10);
  });
}
