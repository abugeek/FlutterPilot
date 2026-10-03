import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/test_recorder.dart';

import 'support/other_library_widgets.dart' as other;

void main() {
  Future<void> pump(WidgetTester tester, Widget body) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));

  String finderFor(Finder f, {bool field = false}) =>
      TestFinder.of(f.evaluate().single, field: field)['finder'] as String;

  testWidgets('a key wins, also on an ancestor drawn in the same box', (
    tester,
  ) async {
    await pump(
      tester,
      Center(
        child: SizedBox(
          key: const ValueKey('send'),
          child: ElevatedButton(onPressed: () {}, child: const Text('Send')),
        ),
      ),
    );
    expect(
      finderFor(find.byType(ElevatedButton)),
      "find.byKey(const ValueKey('send'))",
    );
  });

  testWidgets('unique text, then tooltip, then type with text', (tester) async {
    await pump(
      tester,
      Column(
        children: [
          ElevatedButton(onPressed: () {}, child: const Text('Send')),
          IconButton(
            tooltip: "Don't",
            icon: const Icon(Icons.close),
            onPressed: () {},
          ),
          const Text('Save'),
          TextButton(onPressed: () {}, child: const Text('Save')),
        ],
      ),
    );
    expect(finderFor(find.byType(ElevatedButton)), "find.text('Send')");
    expect(finderFor(find.byType(IconButton)), r"find.byTooltip('Don\'t')");
    // "Save" is on screen twice: the button is found by its type.
    expect(
      finderFor(find.byType(TextButton)),
      "find.widgetWithText(TextButton, 'Save')",
    );
  });

  testWidgets('a text field by its label', (tester) async {
    await pump(
      tester,
      const Column(
        children: [
          TextField(decoration: InputDecoration(labelText: 'Email')),
          TextField(decoration: InputDecoration(labelText: 'Password')),
        ],
      ),
    );
    expect(
      finderFor(find.byType(EditableText).last, field: true),
      "find.widgetWithText(TextField, 'Password')",
    );
  });

  // An app on the separate material_ui package has its own TextField class.
  testWidgets('a text field of another widget library by its label', (
    tester,
  ) async {
    await pump(
      tester,
      const Column(
        children: [
          other.TextField(label: 'Email'),
          other.TextField(label: 'Password'),
        ],
      ),
    );
    expect(
      finderFor(find.byType(EditableText).last, field: true),
      "find.widgetWithText(TextField, 'Password')",
    );
  });

  testWidgets('repeated rows: inside the keyed row, else by position', (
    tester,
  ) async {
    await pump(
      tester,
      Column(
        children: [
          for (final id in ['a', 'b'])
            Row(
              key: ValueKey('row_$id'),
              children: [
                const Text('Title'),
                IconButton(
                  tooltip: 'Bookmark',
                  icon: const Icon(Icons.bookmark),
                  onPressed: () {},
                ),
              ],
            ),
          for (var i = 0; i < 2; i++) const Icon(Icons.star),
        ],
      ),
    );
    expect(
      finderFor(find.byType(IconButton).last),
      "find.descendant(of: find.byKey(const ValueKey('row_b')), "
      "matching: find.byTooltip('Bookmark'))",
    );
    final star = TestFinder.of(find.byIcon(Icons.star).evaluate().last);
    expect(star['finder'], 'find.byType(Icon).at(3)');
    expect(star['stable'], isFalse);
  });

  test('obscured text is kept out of the steps', () {
    TestRecorder.start();
    expect(TestRecorder.typed('me@x.io', obscured: false), {'text': 'me@x.io'});
    expect(TestRecorder.typed('hunter2', obscured: true), {'secret': 1});
    expect(TestRecorder.secrets, ['hunter2']);
    TestRecorder.active = false;
  });
}
