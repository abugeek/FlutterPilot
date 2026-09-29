import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/layout_explorer.dart';

void main() {
  Widget app(Widget body) => MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: body),
    ),
  );

  testWidgets('an overflowing Row: by how much, and which children', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 200,
          child: Row(
            children: [
              SizedBox(key: ValueKey('a'), width: 150, height: 10),
              SizedBox(width: 6),
              SizedBox(width: 90, height: 10),
            ],
          ),
        ),
      ),
    );
    tester.takeException(); // Flutter's own overflow error
    final result = LayoutExplorer.describe(
      tester.element(find.byKey(const ValueKey('a'))),
    );
    final layout = (result['layout'] as List).cast<String>();
    expect(layout.first, contains('SizedBox'));
    expect(layout.first, contains('150×10'));
    // A Row lets its non-flexible children be as wide as they like.
    expect(layout.first, contains('w 0–∞'));
    final row = layout.firstWhere((l) => l.startsWith('Row '));
    expect(row, contains('layout_explorer_test.dart:'));
    expect(row, contains('200×10'));
    expect(row, contains('horizontal'));
    final issues = (result['issues'] as List).cast<String>();
    expect(issues.single, contains('overflows by 46 px'));
    expect(issues.single, contains('need 246 px, it has 200 (width)'));
    expect(issues.single, contains('SizedBox'));
    expect(issues.single, contains('150 px (not flexible)'));
    expect(issues.single, contains('Expanded/Flexible'));
  });

  testWidgets('an Expanded 0 wide: which ancestor leaves it no room', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 200,
          height: 20,
          child: Row(
            children: [
              SizedBox(width: 200),
              Expanded(
                child: ColoredBox(key: ValueKey('x'), color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
    final result = LayoutExplorer.describe(
      tester.element(find.byKey(const ValueKey('x'))),
    );
    final layout = (result['layout'] as List).cast<String>();
    expect(layout.first, contains('0×0'));
    expect(layout.first, contains('w=0'));
    expect(layout.first, contains('Expanded(flex 1)'));
    final issues = (result['issues'] as List).cast<String>();
    expect(issues.single, contains('has width 0 because Row'));
    expect(issues.single, contains('max width 0'));
    expect(issues.single, contains('other children already use all the room'));
  });

  testWidgets('a healthy layout has no issues, wrappers are folded', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Padding(
          padding: const EdgeInsets.all(8),
          child: Semantics(
            label: 'box',
            child: const SizedBox(key: ValueKey('ok'), width: 50, height: 50),
          ),
        ),
      ),
    );
    final result = LayoutExplorer.describe(
      tester.element(find.byKey(const ValueKey('ok'))),
    );
    expect(result['issues'], isNull);
    expect(result['folded'], contains('wrappers'));
    final layout = (result['layout'] as List).cast<String>();
    expect(layout.first, contains('50×50'));
    expect(layout.any((l) => l.startsWith('Padding ')), isTrue);
  });

  testWidgets('a Text is named as the app wrote it, not as RichText', (
    tester,
  ) async {
    // Ten test-font glyphs are wider than 100 px.
    await tester.pumpWidget(
      app(
        const SizedBox(width: 100, child: Row(children: [Text('abcdefghij')])),
      ),
    );
    tester.takeException();
    final result = LayoutExplorer.describe(tester.element(find.byType(Row)));
    final issue = (result['issues'] as List).single as String;
    expect(issue, contains('overflows by'));
    expect(
      issue,
      matches(
        RegExp(
          r'Widest: Text \S+layout_explorer_test\.dart:\d+:\d+ \(RichText\) [\d.]+ px \(not flexible\)',
        ),
      ),
    );
  });
}
