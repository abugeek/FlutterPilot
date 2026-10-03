import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

import 'support/other_library_widgets.dart' as other;

void main() {
  group('PilotWidgetInspector Semantic Selectors', () {
    testWidgets('finds widget by explicit Key and ValueKey', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                ElevatedButton(
                  key: Key('submit_btn'),
                  onPressed: null,
                  child: Text('Submit'),
                ),
                Text('Hello World', key: ValueKey('greeting')),
              ],
            ),
          ),
        ),
      );

      final el1 = PilotWidgetInspector.findElement('submit_btn');
      expect(el1, isNotNull);
      expect(el1!.widget, isA<ElevatedButton>());

      final el2 = PilotWidgetInspector.findElement('greeting');
      expect(el2, isNotNull);
      expect(el2!.widget, isA<Text>());
    });

    testWidgets(
      'finds button by semantic selector and button text without keys',
      (WidgetTester tester) async {
        int tapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () => tapCount++,
                    child: const Text('Log In'),
                  ),
                  TextButton(
                    onPressed: () => tapCount += 2,
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
            ),
          ),
        );

        // 1. Structured selector
        final el1 = PilotWidgetInspector.findElement(
          "ElevatedButton['Log In']",
        );
        expect(el1, isNotNull);
        expect(el1!.widget, isA<ElevatedButton>());

        // 2. Generic button selector
        final el2 = PilotWidgetInspector.findElement(
          "Button['Forgot Password?']",
        );
        expect(el2, isNotNull);
        expect(el2!.widget, isA<TextButton>());

        // 3. Plain text query matching enclosing button
        final el3 = PilotWidgetInspector.findElement('Log In');
        expect(el3, isNotNull);
        expect(el3!.widget, isA<ElevatedButton>());
      },
    );

    testWidgets('finds TextField by placeholder or type selector', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                TextField(
                  decoration: InputDecoration(hintText: 'Enter your email'),
                ),
              ],
            ),
          ),
        ),
      );

      final el = PilotWidgetInspector.findElement(
        "TextField['Enter your email']",
      );
      expect(el, isNotNull);
    });

    testWidgets('finds widget by Tooltip message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IconButton(
              tooltip: 'Settings',
              onPressed: () {},
              icon: const Icon(Icons.settings),
            ),
          ),
        ),
      );

      final el = PilotWidgetInspector.findElement("Tooltip['Settings']");
      expect(el, isNotNull);
    });

    testWidgets('captures selector and text fields in widget tree JSON', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                ElevatedButton(onPressed: null, child: Text('Create Account')),
              ],
            ),
          ),
        ),
      );

      final tree = PilotWidgetInspector.captureWidgetTree(maxDepth: 250);
      expect(tree, isNotNull);
      expect(tree['error'], isNull);

      // Verify that tree contains selector
      bool foundSelector = false;
      void checkNode(Map<String, dynamic> node) {
        if (node['selector'] != null &&
            node['selector'].toString().contains('ElevatedButton')) {
          foundSelector = true;
          expect(node['selector'], equals("ElevatedButton['Create Account']"));
        }
        for (final child in node['children'] as List? ?? []) {
          checkNode(child as Map<String, dynamic>);
        }
      }

      checkNode(tree);
      expect(foundSelector, isTrue);
    });

    testWidgets(
      'finds IconButton by icon name without explicit key or tooltip',
      (WidgetTester tester) async {
        int tapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => tapCount++,
                  ),
                ],
              ),
            ),
          ),
        );

        final el = PilotWidgetInspector.findElement("IconButton['settings']");
        expect(el, isNotNull);
        expect(el!.widget, isA<IconButton>());

        final elDirect = PilotWidgetInspector.findElement("settings");
        expect(elDirect, isNotNull);
      },
    );

    testWidgets('a field label or hint resolves to the TextField, not the '
        'label Text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(decoration: InputDecoration(labelText: 'Email')),
                TextField(
                  decoration: InputDecoration(hintText: 'Search notes'),
                ),
                CupertinoTextField(placeholder: 'Nickname'),
              ],
            ),
          ),
        ),
      );

      expect(
        PilotWidgetInspector.findElement('Email')!.widget,
        isA<TextField>(),
      );
      expect(
        PilotWidgetInspector.findElement('email')!.widget,
        isA<TextField>(),
      );
      expect(
        PilotWidgetInspector.findElement('Search notes')!.widget,
        isA<TextField>(),
      );
      expect(
        PilotWidgetInspector.findElement('Nickname')!.widget,
        isA<CupertinoTextField>(),
      );
    });

    // Field test (Octana fuel sale): the tappable list shows an empty field
    // as "<hint> <label>". Typed back as a target it matched the page-wide
    // GestureDetector by substring, and the text went into the first field
    // on the page.
    testWidgets('a field is found by its hint and label together, and a '
        'container of fields is not one field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () {},
              child: const Column(
                children: [
                  TextField(
                    decoration: InputDecoration(hintText: 'Enter Plate Number'),
                  ),
                  TextField(
                    decoration: InputDecoration(
                      hintText: '0.00',
                      labelText: 'Liters (L)',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      for (final name in ['0.00 Liters (L)', 'Liters (L) 0.00', 'Liters (L)']) {
        final element = PilotWidgetInspector.findElement(name)!;
        expect(element.widget, isA<TextField>(), reason: name);
        expect(
          (element.widget as TextField).decoration!.labelText,
          'Liters (L)',
          reason: name,
        );
        expect(PilotWidgetInspector.fieldsUnder(element), hasLength(1));
      }

      final page = tester.element(find.byType(GestureDetector).first);
      expect(PilotWidgetInspector.fieldsUnder(page), hasLength(2));
    });

    // Octana's field passes its label as a widget, so labelText is null.
    testWidgets('a field whose label is a widget is found by the text it '
        'shows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () {},
              child: const Column(
                children: [
                  TextField(
                    decoration: InputDecoration(hintText: 'Enter Plate Number'),
                  ),
                  TextField(
                    decoration: InputDecoration(
                      hintText: '0.00',
                      label: Text('Liters (L)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final element = PilotWidgetInspector.findElement('0.00 Liters (L)')!;
      expect(element.widget, isA<TextField>());
      expect((element.widget as TextField).decoration!.hintText, '0.00');
    });

    // Octana's login: the password field holds a "Show password" button,
    // and its TextField is material_ui's class, not Flutter's.
    testWidgets('a field of another widget library is found by its label, '
        'though other labels contain the word', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const other.TextField(label: 'Email'),
                other.TextField(
                  label: 'Password',
                  suffix: IconButton(
                    tooltip: 'Show password',
                    icon: const Icon(Icons.visibility),
                    onPressed: () {},
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Forgot Password?'),
                ),
              ],
            ),
          ),
        ),
      );

      final element = PilotWidgetInspector.findElement('Password');
      expect(PilotWidgetInspector.lastAmbiguity, isNull);
      expect(element!.widget, isA<other.TextField>());
      expect((element.widget as other.TextField).label, 'Password');
    });

    testWidgets('icon names label only icon-only buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete),
                  onPressed: () {},
                ),
                IconButton(icon: const Icon(Icons.add), onPressed: () {}),
              ],
            ),
          ),
        ),
      );

      final labels = PilotWidgetInspector.getInteractiveElements()
          .map((e) => e['text'])
          .toList();
      expect(labels, containsAll(['Delete', 'add']));
      expect(labels, isNot(contains('Delete delete')));
    });
    // A list of rows with a checkbox each: listed as "Checkbox" fifteen
    // times, and "Done: Buy milk" found nothing.
    testWidgets('names controls by their screen reader label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final title in ['Buy milk', 'Walk the dog'])
                  Checkbox(
                    value: false,
                    semanticLabel: 'Done: $title',
                    onChanged: (_) {},
                  ),
                Semantics(
                  label: 'Volume',
                  child: GestureDetector(
                    onTap: () {},
                    child: const SizedBox(width: 48, height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final milk = PilotWidgetInspector.findElement('Done: Buy milk');
      expect(
        milk?.findAncestorWidgetOfExactType<Checkbox>()?.semanticLabel,
        'Done: Buy milk',
      );
      expect(PilotWidgetInspector.findElement('Volume'), isNotNull);
      final texts = [
        for (final e in PilotWidgetInspector.getInteractiveElements())
          e['text'],
      ];
      expect(texts, containsAll(['Done: Buy milk', 'Done: Walk the dog']));
    });
  });
}
