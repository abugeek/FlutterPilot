import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/source_locator.dart';
import 'package:flutterpilot_sdk/src/widget_inspector.dart';

class _StoryTile extends StatelessWidget {
  const _StoryTile();

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('story_1'),
    title: const Text('Show HN: a tool'),
    onTap: () {},
  );
}

/// The line of this file that holds [code], so edits don't break the test.
int _lineOf(String code) =>
    File(
      'test/source_locator_test.dart',
    ).readAsLinesSync().indexWhere((l) => l.contains(code)) +
    1;

void main() {
  // flutter test runs with --track-widget-creation, like flutter run.
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: Column(children: [_StoryTile()])),
    ),
  );

  testWidgets('creation locations are tracked under flutter test', (
    tester,
  ) async {
    expect(SourceLocator.available, isTrue);
  });

  testWidgets('a key points at the line that creates the widget', (
    tester,
  ) async {
    await pumpApp(tester);
    final tile = PilotWidgetInspector.findElement('story_1')!;
    final result = SourceLocator.describe(tile);
    expect(result['widget']['type'], 'ListTile');
    expect(result['widget']['key'], 'story_1');
    final source = result['source'] as Map;
    expect(source['type'], 'ListTile');
    expect(
      source['loc'],
      contains('source_locator_test.dart:${_lineOf('=> ListTile(')}:'),
    );
    expect(source.containsKey('note'), isFalse);
    // The app widgets above it, nearest first, each with its location.
    final ancestors = (result['ancestors'] as List).cast<String>();
    expect(ancestors.first, startsWith('_StoryTile '));
    expect(
      ancestors.first,
      contains('source_locator_test.dart:${_lineOf('[_StoryTile()]')}:'),
    );
    expect(ancestors.last, startsWith('MaterialApp '));
  });

  testWidgets('a point resolves to the app code that draws it', (tester) async {
    await pumpApp(tester);
    final center = tester.getCenter(find.text('Show HN: a tool'));
    final element = SourceLocator.elementAt(center)!;
    final result = SourceLocator.describe(element);
    // The hit is the RichText that Text builds internally (framework code);
    // the source is the Text the app wrote.
    expect(result['widget']['type'], 'RichText');
    final source = result['source'] as Map;
    expect(source['type'], 'Text');
    expect(
      source['loc'],
      contains('source_locator_test.dart:${_lineOf("Text('Show HN")}:'),
    );
    expect(source['note'], contains('created inside Text'));
    expect((result['ancestors'] as List).first, startsWith('ListTile '));
  });

  testWidgets('nothing drawn outside the window', (tester) async {
    await pumpApp(tester);
    expect(SourceLocator.elementAt(const Offset(-10, -10)), isNull);
  });

  test('short paths start at lib/', () {
    expect(
      SourceLocator.shortPath('file:///Users/me/app/lib/ui/tile.dart'),
      'lib/ui/tile.dart',
    );
    expect(SourceLocator.shortPath('/x/test/a.dart'), '/x/test/a.dart');
  });
}
