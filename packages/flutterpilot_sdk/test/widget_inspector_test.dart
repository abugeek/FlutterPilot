import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

void main() {
  group('PilotWidgetInspector', () {
    testWidgets('captures widget tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Hello'),
                ElevatedButton(
                  key: const Key('submit_button'),
                  onPressed: () {},
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      );

      final tree = PilotWidgetInspector.captureWidgetTree();

      expect(tree, isNotNull);
      // In a test environment, the root might be RootWidget or View
      expect(tree.toString(), contains('MaterialApp'));

      // Verify button exists in tree
      String treeString = tree.toString();
      expect(treeString, contains('ElevatedButton'));
      expect(treeString, contains('submit_button'));
    });

    testWidgets('a toggled switch shows up in the tree diff', (tester) async {
      Future<Map<String, dynamic>> treeWith(bool on) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SwitchListTile(
                key: const ValueKey('dark'),
                title: const Text('Dark mode'),
                value: on,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        return PilotWidgetInspector.captureWidgetTree();
      }

      final off = await treeWith(false);
      final on = await treeWith(true);
      final diff = PilotWidgetInspector.diffWidgetTrees(off, on);
      expect(diff['modifiedCount'], 1);
      expect(diff['modified'].toString(), contains('= false'));
      expect(diff['modified'].toString(), contains('= true'));
    });

    testWidgets('findElementByKey finds widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              key: const Key('my_container'),
              child: const Text('Test'),
            ),
          ),
        ),
      );

      final element = PilotWidgetInspector.findElementByKey('my_container');

      expect(element, isNotNull);
      expect(element!.widget, isA<Container>());
    });

    testWidgets('countElements counts correctly', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [Text('1'), Text('2')]),
        ),
      );

      final root = tester.element(find.byType(Column));
      final count = PilotWidgetInspector.countElements(root);

      // Column + 2 Text widgets + their internal children (RichText, etc.)
      expect(count, greaterThanOrEqualTo(3));
    });
  });

  group('interactive elements skip framework noise', () {
    Widget scaffoldApp() => MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [
              PopupMenuButton<int>(
                tooltip: 'Menu',
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 1, child: Text('A')),
                ],
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'One'),
                Tab(text: 'Two'),
              ],
            ),
          ),
          drawer: Drawer(
            child: ListView(
              children: [
                const Text('In drawer'),
                ListTile(title: const Text('Drawer item'), onTap: () {}),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              Column(
                children: [
                  ElevatedButton(onPressed: () {}, child: const Text('Go')),
                  KeyedSubtree(
                    key: const ValueKey(_Slot.body),
                    child: TextButton(
                      key: const GlobalObjectKey(7),
                      onPressed: () {},
                      child: const Text('Push Later'),
                    ),
                  ),
                ],
              ),
              const Text('second'),
            ],
          ),
        ),
      ),
    );

    List<String?> labels() => [
      for (final e in PilotWidgetInspector.getInteractiveElements())
        e['text'] as String?,
    ];

    testWidgets('app bar, tab bar and scaffold are not merged entries', (
      tester,
    ) async {
      await tester.pumpWidget(scaffoldApp());
      expect(labels(), [
        'Go',
        'Push Later',
        'Open navigation menu',
        'Menu',
        'One',
        'Two',
      ]);
      final types = PilotWidgetInspector.getInteractiveElements().map(
        (e) => e['type'],
      );
      expect(types, isNot(contains('Scaffold')));
      expect(types, isNot(contains('AppBar')));
      expect(types, isNot(contains('TabBar')));
      expect(types, containsAll(['ElevatedButton', 'PopupMenuButton<int>']));
    });

    testWidgets('open drawer lists its items, not the scrim', (tester) async {
      await tester.pumpWidget(scaffoldApp());
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(labels(), ['Drawer item']);
    });

    testWidgets('not-found hints leave out framework and private keys', (
      tester,
    ) async {
      await tester.pumpWidget(scaffoldApp());
      final hints = PilotWidgetInspector.getAvailableActionableTargets(
        limit: 50,
      );
      expect(hints.take(3), ['Go', 'Push Later', 'Open navigation menu']);
      for (final noise in [
        'GlobalObjectKey',
        '_ScaffoldSlot',
        '_Slot',
        'StandardComponentType',
        '[<',
      ]) {
        expect(hints.where((h) => h.contains(noise)), isEmpty, reason: noise);
      }
    });

    testWidgets('hints still include keys the app wrote', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              key: const ValueKey('login_card'),
              child: ElevatedButton(
                key: const ValueKey(3),
                onPressed: () {},
                child: const Text('Log In'),
              ),
            ),
          ),
        ),
      );
      expect(PilotWidgetInspector.getAvailableActionableTargets(), [
        '3',
        'login_card',
      ]);
    });

    testWidgets('a tappable container is labelled by its own text only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InkWell(
                  onTap: () {},
                  child: Row(
                    children: [
                      TextButton(onPressed: () {}, child: const Text('A')),
                      TextButton(onPressed: () {}, child: const Text('B')),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {},
                  child: Row(
                    children: [
                      const Text('Title'),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () {},
                        icon: const Icon(Icons.delete),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(labels(), ['A', 'B', 'Title', 'Delete']);
    });
  });
}

enum _Slot { body }
