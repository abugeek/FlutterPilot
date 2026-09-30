import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  testWidgets(
    'KeyboardSimulator dispatches hardware key events to focused widget',
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
    },
  );

  testWidgets('KeyboardSimulator triggers onSubmitted on Enter', (
    tester,
  ) async {
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

  // Desktop text editing goes through the OS input client, which synthesized
  // key events never reach; where the framework itself handles a key (its
  // editing shortcuts), the edit must not happen twice. Same result on every
  // platform.
  testWidgets('edits the focused field once, as typing would', (tester) async {
    final changes = <String>[];
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            autofocus: true,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pilot');
    final simulator = KeyboardSimulator();

    var field = await simulator.pressKey('backspace');
    expect(controller.text, 'Pilo');
    expect(field!['text'], 'Pilo');
    expect(field['changed'], isTrue);

    await simulator.pressKey('x');
    expect(controller.text, 'Pilox');

    await simulator.pressKey('arrowLeft');
    field = await simulator.pressKey('arrowLeft');
    expect(field!['selectionStart'], 3);
    await simulator.pressKey('delete');
    expect(controller.text, 'Pilx');

    final selectAll =
        defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS
        ? 'meta'
        : 'control';
    field = await simulator.pressKey('a', modifiers: {selectAll});
    expect((field!['selectionStart'], field['selectionEnd']), (0, 4));
    await simulator.pressKey('z');
    expect(controller.text, 'z');
    expect(changes.last, 'z');
  }, variant: TargetPlatformVariant.all());

  testWidgets('leaves a read-only field alone and masks obscured text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const ValueKey('ro'),
                readOnly: true,
                controller: TextEditingController(text: 'fixed'),
              ),
              TextField(
                key: const ValueKey('pin'),
                obscureText: true,
                controller: TextEditingController(text: '1234'),
              ),
            ],
          ),
        ),
      ),
    );
    final simulator = KeyboardSimulator();

    await tester.tap(find.byKey(const ValueKey('ro')));
    await tester.pumpAndSettle();
    var field = await simulator.pressKey('x');
    expect(field!['text'], 'fixed');
    expect(field['changed'], isFalse);

    await tester.tap(find.byKey(const ValueKey('pin')));
    await tester.pumpAndSettle();
    field = await simulator.pressKey('5');
    expect(field!['text'], '•••••');
  });

  testWidgets('reports nothing when no text field has focus', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(await KeyboardSimulator().pressKey('escape'), isNull);
  });

  // A field the app (or a tap elsewhere, or Enter) unfocused stays
  // unfocused: the key goes nowhere rather than into the field it left.
  testWidgets('a key after the field lost focus does not edit it', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Pilo');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final simulator = KeyboardSimulator();
    expect((await simulator.pressKey('backspace'))!['text'], 'Pil');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(await simulator.pressKey('o'), isNull);
    expect(controller.text, 'Pil');
  });
}
