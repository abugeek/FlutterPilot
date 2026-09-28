import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// The post-action wait reads the screen once the on-screen text holds
/// still. That must see motion that isn't a route transition (a drawer, a
/// tab switch), and must not wait on a spinner.
void main() {
  List<Offset> sig() => FlutterPilot.debugTextPositions().values.toList();

  testWidgets('a sliding drawer moves, an open one holds still', (
    tester,
  ) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffold,
          drawer: const Drawer(child: Text('Drawer item')),
          body: const Text('Body'),
        ),
      ),
    );
    scaffold.currentState!.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final a = sig();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sig(), isNot(a));

    await tester.pumpAndSettle();
    final open = sig();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sig(), open);
  });

  testWidgets('a tab switch moves until it lands', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: TabBar(
              tabs: [
                Tab(text: 'One'),
                Tab(text: 'Two'),
              ],
            ),
            body: TabBarView(children: [Text('In One'), Text('In Two')]),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Two'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final a = sig();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sig(), isNot(a));

    await tester.pumpAndSettle();
    final landed = sig();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sig(), landed);
  });

  testWidgets('a spinner does not count as motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [Text('Loading'), CircularProgressIndicator()],
          ),
        ),
      ),
    );
    final a = sig();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sig(), a);
    expect(a, isNotEmpty);
  });

  testWidgets('a covered page does not count', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Text('Home')),
    );
    final home = sig();
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Top')),
    );
    await tester.pumpAndSettle();
    // Only "Top" is measured: the covered home page is offstage.
    expect(sig(), hasLength(1));
    expect(home, hasLength(1));
  });

  group('SettleTracker', () {
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    final a = Object(), b = Object();

    test('settles once two samples match', () {
      final tracker = SettleTracker();
      expect(tracker.add({a: Offset.zero}, at(0)), isFalse);
      expect(tracker.add({a: const Offset(10, 0)}, at(16)), isFalse);
      expect(tracker.add({a: const Offset(10, 0)}, at(32)), isTrue);
    });

    test('new or vanished text is a change', () {
      final tracker = SettleTracker()..add({a: Offset.zero}, at(0));
      expect(tracker.add({a: Offset.zero, b: Offset.zero}, at(16)), isFalse);
      expect(tracker.add({b: Offset.zero}, at(32)), isFalse);
      expect(tracker.add({b: Offset.zero}, at(48)), isTrue);
    });

    test('text that keeps moving past a transition is ignored', () {
      final tracker = SettleTracker();
      var still = false;
      for (var ms = 0; ms <= 1000 && !still; ms += 16) {
        // "b" loops forever; "a" landed long ago.
        still = tracker.add({
          a: Offset.zero,
          b: Offset(ms.toDouble(), 0),
        }, at(ms));
        if (ms < 600) expect(still, isFalse, reason: 'at $ms ms');
      }
      expect(still, isTrue);
    });

    test('text found looping is ignored by the next tracker at once', () {
      final looping = Expando<bool>();
      final first = SettleTracker(looping: looping);
      for (var ms = 0; ms <= 700; ms += 16) {
        first.add({a: Offset.zero, b: Offset(ms.toDouble(), 0)}, at(ms));
      }
      final next = SettleTracker(looping: looping)
        ..add({a: Offset.zero, b: Offset.zero}, at(0));
      expect(next.add({a: Offset.zero, b: const Offset(5, 0)}, at(16)), isTrue);
    });

    test('reset starts over', () {
      final tracker = SettleTracker()..add({a: Offset.zero}, at(0));
      tracker.reset();
      expect(tracker.add({a: Offset.zero}, at(16)), isFalse);
    });
  });
}
