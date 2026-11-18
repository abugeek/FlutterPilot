import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fp_sdk/src/scroll_jump.dart';

Future<Map<String, Object>> _jump(WidgetTester tester, double fraction) async {
  final future = jumpToFraction(scrollableFor(null)!.position, fraction);
  Map<String, Object>? result;
  future.then((r) => result = r);
  while (result == null) {
    await tester.pump();
  }
  return result!;
}

void main() {
  for (final fixed in [true, false]) {
    testWidgets('jumps to the end of a ${fixed ? 'fixed' : 'variable'}-extent '
        'list of 5,000 rows', (tester) async {
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: 5000,
              itemExtent: fixed ? 48 : null,
              itemBuilder: (context, i) {
                built++;
                return SizedBox(height: 48, child: Text('Row $i'));
              },
            ),
          ),
        ),
      );
      built = 0;

      final r = await _jump(tester, 1.0);

      expect(find.text('Row 4999'), findsOneWidget);
      expect(r['offset'], r['maxScrollExtent']);
      // The walk the tool is there to expose: without a fixed extent the
      // jump builds every row on the way.
      expect(built, fixed ? lessThan(100) : greaterThan(4000));
    });
  }

  testWidgets('a fraction lands in the middle of a fixed-extent list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 1000,
            itemExtent: 50,
            itemBuilder: (context, i) => Text('Row $i'),
          ),
        ),
      ),
    );
    final r = await _jump(tester, 0.5);
    expect(r['frames'], 1);
    expect(r['offset'], ((1000 * 50 - 600) / 2).round());
  });

  testWidgets('a target names the list to jump, or one around it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            key: const Key('the_list'),
            children: [for (var i = 0; i < 50; i++) Text('Item $i')],
          ),
        ),
      ),
    );
    final byList = scrollableFor('the_list');
    expect(byList, isNotNull);
    expect(scrollableFor('Item 3'), same(byList));
    expect(scrollableFor('nothing like this'), isNull);
  });
}
