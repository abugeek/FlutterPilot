import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

import 'support/other_library_widgets.dart' as other;

/// A drawer button ("Open navigation menu", icon Icons.menu) next to a popup
/// menu button whose tooltip is exactly "Menu".
Widget _app() => MaterialApp(
  home: DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'One'),
            Tab(text: 'Two'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'a', child: Text('Alpha')),
            ],
          ),
        ],
      ),
      drawer: const Drawer(child: Text('In drawer')),
      body: const SizedBox(),
    ),
  ),
);

/// Taps the center of whatever [query] resolves to, as tap_widget does.
Future<void> _tap(WidgetTester tester, String query) async {
  final element = PilotWidgetInspector.findElement(query);
  expect(element, isNotNull, reason: 'no match for $query');
  final box = element!.renderObject! as RenderBox;
  await tester.tapAt(box.localToGlobal(box.size.center(Offset.zero)));
  await tester.pumpAndSettle();
}

void main() {
  for (final query in ['Menu', 'menu', "Tooltip['Menu']", "Tooltip['menu']"]) {
    testWidgets(
      '"$query" is the popup button, not the drawer\'s '
      '"Open navigation menu" or its menu icon',
      variant: TargetPlatformVariant.all(),
      (tester) async {
        await tester.pumpWidget(_app());
        await _tap(tester, query);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('In drawer'), findsNothing);
      },
    );
  }

  testWidgets('a substring of one label still resolves', (tester) async {
    await tester.pumpWidget(_app());
    await _tap(tester, 'navigation');
    expect(find.text('In drawer'), findsOneWidget);
  });

  testWidgets('theme wrappers are never the match', (tester) async {
    await tester.pumpWidget(_app());
    for (final q in ['Menu', 'navigation', "Button['Menu']"]) {
      final type = PilotWidgetInspector.findElement(q)!.widget.runtimeType;
      expect(type.toString(), isNot(endsWith('Theme')), reason: q);
    }
  });

  group('several labels merely contain the query', () {
    Widget two() => MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Open settings',
              icon: const Icon(Icons.tune),
              onPressed: () {},
            ),
            IconButton(
              tooltip: 'Close settings',
              icon: const Icon(Icons.close),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    for (final query in ['settings', "Tooltip['settings']"]) {
      testWidgets('"$query" is refused with the candidates', (tester) async {
        await tester.pumpWidget(two());
        expect(PilotWidgetInspector.findElement(query), isNull);
        expect(PilotWidgetInspector.lastAmbiguity, contains('Open settings'));
        expect(PilotWidgetInspector.lastAmbiguity, contains('Close settings'));
      });
    }

    testWidgets('the exact label resolves', (tester) async {
      await tester.pumpWidget(two());
      final e = PilotWidgetInspector.findElement("Tooltip['Close settings']");
      expect((e!.widget as Tooltip).message, 'Close settings');
    });
  });

  testWidgets('an icon name still selects a button without a tooltip', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );
    await _tap(tester, "IconButton['settings']");
    expect(tapped, isTrue);
  });

  // An app on the separate material_ui package has its own Tooltip class.
  testWidgets('a tooltip of another widget library selects its button', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: other.Tooltip(
            message: 'Close settings',
            child: GestureDetector(
              onTap: () => tapped = true,
              child: const Icon(Icons.close),
            ),
          ),
        ),
      ),
    );
    for (final query in ['Close settings', "Tooltip['Close settings']"]) {
      tapped = false;
      await _tap(tester, query);
      expect(tapped, isTrue, reason: query);
    }
    expect(
      PilotWidgetInspector.isNamed(
        other.Slider(value: 0, onChanged: (_) {}),
        'Slider',
      ),
      isTrue,
    );
  });
}
