import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/hit_test_utils.dart';
import 'package:flutterpilot_sdk/src/scroll_simulator.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

/// Runs a search, pumping the frames it waits for (tests have no real ones).
Future<bool> search(WidgetTester tester, String target) async {
  bool? found;
  ScrollSimulator.scrollUntilVisible(target).then((v) => found = v);
  while (found == null) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return found!;
}

Widget tile(String label) =>
    SizedBox(height: 56, child: Text(label, key: ValueKey(label)));

Widget app(Widget body) => MaterialApp(home: Scaffold(body: body));

Widget longList({double start = 0, bool reverse = false}) => ListView.builder(
  controller: ScrollController(initialScrollOffset: start),
  reverse: reverse,
  itemCount: 500,
  itemBuilder: (_, i) => tile('Item $i'),
);

bool onScreen(String text) {
  final e = PilotWidgetInspector.findElement(text, partial: false);
  return e != null && HitTestUtils.isElementHittable(e);
}

double offsetOf(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

void main() {
  testWidgets('an item a lazy list has not built yet, further down', (
    tester,
  ) async {
    await tester.pumpWidget(app(longList()));
    expect(find.text('Item 420'), findsNothing);
    expect(await search(tester, 'Item 420'), isTrue);
    expect(onScreen('Item 420'), isTrue);
  });

  testWidgets('an item above where the list starts', (tester) async {
    await tester.pumpWidget(app(longList(start: 14000)));
    expect(await search(tester, 'Item 3'), isTrue);
    expect(onScreen('Item 3'), isTrue);
  });

  testWidgets('a reversed (chat) list', (tester) async {
    await tester.pumpWidget(app(longList(reverse: true)));
    expect(await search(tester, 'Item 300'), isTrue);
    expect(onScreen('Item 300'), isTrue);
  });

  testWidgets('a grid', (tester) async {
    await tester.pumpWidget(
      app(
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
          ),
          itemCount: 800,
          itemBuilder: (_, i) => tile('Cell $i'),
        ),
      ),
    );
    expect(await search(tester, 'Cell 777'), isTrue);
    expect(onScreen('Cell 777'), isTrue);
  });

  testWidgets('a card in a horizontal list inside a vertical one', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ListView.builder(
          itemCount: 30,
          itemBuilder: (_, r) => SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 50,
              itemBuilder: (_, c) =>
                  SizedBox(width: 140, child: tile('Card $r-$c')),
            ),
          ),
        ),
      ),
    );
    expect(await search(tester, 'Card 20-40'), isTrue);
    expect(onScreen('Card 20-40'), isTrue);
  });

  testWidgets('"Item 3" is not satisfied by "Item 399" on the way', (
    tester,
  ) async {
    await tester.pumpWidget(app(longList(start: 22300)));
    // Only "Item 399" contains "Item 3" on this screen.
    expect(PilotWidgetInspector.findElement('Item 3'), isNotNull);
    expect(PilotWidgetInspector.lastMatchPartial, isTrue);
    expect(PilotWidgetInspector.findElement('Item 3', partial: false), isNull);

    expect(await search(tester, 'Item 3'), isTrue);
    expect(onScreen('Item 3'), isTrue);
    expect(PilotWidgetInspector.findElement('Item 3'), isNotNull);
    expect(PilotWidgetInspector.lastMatchPartial, isFalse);
  });

  testWidgets('with the window hidden (frames off), without a frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ListView.builder(
          itemCount: 30,
          itemBuilder: (_, r) => SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 50,
              itemBuilder: (_, c) =>
                  SizedBox(width: 140, child: tile('Card $r-$c')),
            ),
          ),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);

    // No pumping: the search builds and lays out by itself.
    expect(await ScrollSimulator.scrollUntilVisible('Card 20-40'), isTrue);
    expect(onScreen('Card 20-40'), isTrue);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a missing item leaves the list where it was', (tester) async {
    await tester.pumpWidget(app(longList(start: 5000)));
    expect(await search(tester, 'Item 9999'), isFalse);
    expect(offsetOf(tester), 5000);
  });
}
