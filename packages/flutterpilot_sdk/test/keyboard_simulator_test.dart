import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  testWidgets('KeyboardSimulator dispatches hardware key events to focused widget',
      (tester) async {
    final events = <KeyEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            events.add(event);
            return KeyEventResult.ignored;
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final simulator = KeyboardSimulator();
    await simulator.pressKey('a');
    await tester.pumpAndSettle();

    final down = events.whereType<KeyDownEvent>().toList();
    final up = events.whereType<KeyUpEvent>().toList();
    expect(down, hasLength(1));
    expect(up, hasLength(1));
    expect(down.single.logicalKey, LogicalKeyboardKey.keyA);
    expect(down.single.character, 'a');
  });

  testWidgets('KeyboardSimulator triggers onSubmitted on Enter',
      (tester) async {
    String submitted = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextField(
              autofocus: true,
              onSubmitted: (val) => submitted = val,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello World');

    final simulator = KeyboardSimulator();
    await simulator.pressKey('enter');
    await tester.pumpAndSettle();

    expect(submitted, equals('Hello World'));
  });
}
