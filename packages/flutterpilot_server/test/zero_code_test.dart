import 'dart:convert';

import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/zero_code.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// A node as `ext.flutter.inspector.getRootWidgetTree` returns it.
Map<String, dynamic> node(
  String type, {
  String? id,
  String? key,
  String? text,
  bool local = false,
  int line = 1,
  List<Map<String, dynamic>> children = const [],
}) => {
  'description': key == null ? type : '$type-$key',
  'widgetRuntimeType': type,
  'valueId': ?id,
  'createdByLocalProject': ?(local ? true : null),
  'textPreview': ?text,
  'creationLocation': {
    'file': local
        ? 'file:///Users/me/app/lib/main.dart'
        : 'file:///flutter/packages/flutter/lib/src/widgets/basic.dart',
    'line': line,
  },
  'hasChildren': children.isNotEmpty,
  'children': children,
};

void main() {
  group('summaryTreeFromInspector', () {
    test('keeps app widgets, user keys and Text with source locations', () {
      final tree = summaryTreeFromInspector(
        node(
          '[root]',
          children: [
            node(
              'MyApp',
              local: true,
              line: 3,
              children: [
                node(
                  'Padding',
                  children: [
                    node(
                      'Text',
                      key: "[<'count'>]",
                      text: 'Count: 0',
                      local: true,
                      line: 9,
                    ),
                    node('LayoutId', key: '[<_ScaffoldSlot.body>]'),
                    node(
                      '_OverlayEntryWidget',
                      key: '[LabeledGlobalKey<_OverlayEntryWidgetState>#1]',
                    ),
                    node('KeyedSubtree', key: "[<'plain'>]"),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      expect(tree, {
        'type': 'MyApp',
        'loc': 'lib/main.dart:3',
        'children': [
          {
            'type': 'Text',
            'key': "[<'count'>]",
            'text': 'Count: 0',
            'loc': 'lib/main.dart:9',
          },
          {'type': 'KeyedSubtree', 'key': "[<'plain'>]"},
        ],
      });
    });

    test(
      'leaves out routes a _Theater skips and unselected IndexedStack children',
      () {
        final tree = summaryTreeFromInspector(
          node(
            '_Theater',
            id: 'theater',
            children: [
              node(
                'HomePage',
                local: true,
                children: [node('Text', text: 'covered')],
              ),
              node(
                'DetailsPage',
                local: true,
                children: [
                  node(
                    '_RawIndexedStack',
                    id: 'stack',
                    children: [
                      node('Text', text: 'tab A'),
                      node('Text', text: 'tab B'),
                    ],
                  ),
                ],
              ),
            ],
          ),
          skipCounts: {'theater': 1},
          stackIndexes: {'stack': 1},
        );
        expect(screenContent(tree).texts, ['tab B']);
        expect(jsonEncode(tree), isNot(contains('HomePage')));
      },
    );

    test('offstageHosts finds theaters and indexed stacks', () {
      final hosts = offstageHosts(
        node(
          'App',
          children: [
            node(
              '_Theater',
              id: 't1',
              children: [node('_RawIndexedStack', id: 's1')],
            ),
          ],
        ),
      );
      expect(hosts.theaters, ['t1']);
      expect(hosts.indexedStacks, ['s1']);
    });
  });

  test(
    'errorFromFlutterErrorEvent reads summary, culprit widget and stack',
    () {
      final error = errorFromFlutterErrorEvent({
        'description': 'Exception caught by rendering library',
        'properties': [
          {
            'type': 'ErrorDescription',
            'description': 'The following assertion was thrown during layout:',
          },
          {
            'type': 'ErrorSummary',
            'description': 'A RenderFlex overflowed by 38 pixels on the right.',
          },
          {
            'type': 'DiagnosticsBlock',
            'name': 'The relevant error-causing widget was',
            'children': [
              {
                'description':
                    'Row Row:file:///Users/me/app/lib/ui/tile.dart:23:17',
              },
            ],
          },
          {
            'name': 'When the exception was thrown, this was the stack',
            'children': [
              {'description': '#0 main (package:app/main.dart:4:3)'},
            ],
          },
        ],
      }, DateTime(2026));
      expect(
        error['exception'],
        'A RenderFlex overflowed by 38 pixels on the right.',
      );
      expect(error['widget'], 'Row lib/ui/tile.dart:23:17');
      expect(error['stackTrace'], '#0 main (package:app/main.dart:4:3)');
      expect(error['library'], 'Exception caught by rendering library');
    },
  );

  test(
    'zeroCodeSummary says what works, lists screen text and groups errors',
    () {
      final text = zeroCodeSummary({
        'flutterVersion': '3.x',
        'heapUsageMb': 80,
        'texts': ['Count: 0', 'Increment', 'Item', 'Item', 'Item'],
        'keys': ["[<'count'>]"],
        'errors': [
          {'exception': 'Overflow', 'widget': 'Row lib/main.dart:4:1'},
          {'exception': 'Overflow', 'widget': 'Row lib/main.dart:4:1'},
        ],
      });
      expect(text, contains('zero-code'));
      expect(text, contains('flutterpilot init'));
      expect(text, contains('"Count: 0", "Increment", "Item" (x3)'));
      expect(text, contains('Overflow — Row lib/main.dart:4:1 (x2)'));
    },
  );

  group('cropToScreen', () {
    String png(img.Image image) => base64Encode(img.encodePng(image));

    test(
      'finds the window left of which a covered route widened the bounds',
      () {
        // 100px transparent (unpainted covered route), a 10px faint shadow,
        // then the 200px opaque window.
        final image = img.Image(width: 310, height: 50, numChannels: 4);
        for (final p in image) {
          if (p.x >= 110) {
            p.setRgba(255, 0, 0, 255);
          } else if (p.x >= 100) {
            p.setRgba(0, 0, 0, 20);
          }
        }
        final cropped = img.decodePng(
          base64Decode(cropToScreen(png(image), 200, 50, 1)),
        )!;
        expect(cropped.width, 200);
        expect(cropped.getPixel(0, 0).a, 255);
        expect(cropped.getPixel(199, 49).a, 255);
      },
    );

    test('drops sparse overflow to the right', () {
      final image = img.Image(width: 300, height: 50, numChannels: 4);
      for (final p in image) {
        if (p.x < 200 || (p.x > 250 && p.y == 10)) p.setRgba(0, 0, 255, 255);
      }
      final cropped = img.decodePng(
        base64Decode(cropToScreen(png(image), 100, 25, 2)),
      )!;
      expect(cropped.width, 200);
      expect(cropped.height, 50);
      expect(cropped.getPixel(199, 0).a, 255);
    });

    test('returns an image that already fits unchanged', () {
      final data = png(img.Image(width: 200, height: 100, numChannels: 4));
      expect(cropToScreen(data, 100, 50, 2), data);
    });
  });

  test('zero-code mode lists only tools that work without the SDK', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    final all = server.listedToolNames.toSet();
    expect(
      all,
      containsAll(zeroCodeTools),
      reason: 'every zero-code tool exists',
    );

    server.updateSdkToolVisibility(hasSdk: false);
    expect(server.listedToolNames.toSet(), zeroCodeTools);

    server.updateSdkToolVisibility(hasSdk: true);
    expect(server.listedToolNames.toSet(), all);
  });
}
