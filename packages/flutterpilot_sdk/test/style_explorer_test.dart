import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/style_explorer.dart';

void main() {
  Map<String, dynamic> styleOf(WidgetTester tester, Finder finder) =>
      StyleExplorer.describe(tester.element(finder))['style']
          as Map<String, dynamic>;

  // A card as a design spec states it: 16/12 padding, radius 12, a 1 px
  // border, a 15/600 title and a 13/400 subtitle.
  Widget card() => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          key: const ValueKey('card'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paper playground',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                  height: 1.33,
                ),
              ),
              Text(
                'Print a test page',
                style: TextStyle(fontSize: 13, color: Color(0x9964748B)),
              ),
              Icon(Icons.print, size: 20, color: Color(0xFF334155)),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('a card: text, padding, fill, border and radius', (tester) async {
    await tester.pumpWidget(card());
    final style = styleOf(tester, find.byKey(const ValueKey('card')));

    final text = style['text'] as List;
    expect(
      text[0],
      allOf(
        containsPair('text', 'Paper playground'),
        containsPair('size', 15),
        containsPair('weight', 600),
        containsPair('color', '#0F172A'),
        containsPair('height', 1.33),
        contains('font'),
      ),
    );
    expect(text[1], containsPair('size', 13));
    expect(text[1], containsPair('weight', 400));
    // A translucent color keeps its alpha.
    expect(text[1], containsPair('color', '#64748B99'));

    expect(style['icons'], [
      {'size': 20, 'color': '#334155'},
    ]);
    // As written in the code: Container lays out 17 (16 + the 1 px border).
    expect(
      (style['padding'] as List).first,
      allOf(
        containsPair('ltrb', [16, 12, 16, 12]),
        containsPair('plusBorder', [1, 1, 1, 1]),
      ),
    );
    expect((style['boxes'] as List).first, {
      'color': '#FFFFFF',
      'radius': 12,
      'border': '#E2E8F0 1',
      'box': anything,
    });
    // Around the card: the page's 24 of padding, on the page's background.
    expect(style['paddingAround'], containsPair('ltrb', [24, 24, 24, 24]));
    expect(style['behind'], containsPair('color', '#F8FAFC'));
  });

  testWidgets('one text: its own style and what is around it', (tester) async {
    await tester.pumpWidget(card());
    final style = styleOf(tester, find.text('Paper playground'));
    expect((style['text'] as List).single, containsPair('weight', 600));
    expect(style['paddingAround'], containsPair('ltrb', [16, 12, 16, 12]));
    expect(style['behind'], containsPair('color', '#FFFFFF'));
    expect(style.containsKey('boxes'), isFalse);
  });

  testWidgets('Material widgets: elevation, shape and the scaled text size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Column(
              children: [
                Card(
                  key: const ValueKey('m'),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF112233), width: 2),
                  ),
                  child: const Text('Total', style: TextStyle(fontSize: 14)),
                ),
                FilledButton(onPressed: () {}, child: const Text('Pay')),
              ],
            ),
          ),
        ),
      ),
    );
    final cardStyle = styleOf(tester, find.byKey(const ValueKey('m')));
    final box = (cardStyle['boxes'] as List).first as Map;
    expect(box['elevation'], 3);
    expect(box['radius'], 8);
    expect(box['border'], '#112233 2');
    expect((cardStyle['text'] as List).single, containsPair('scaled', 28));

    final button = styleOf(tester, find.byType(FilledButton));
    expect(
      (button['boxes'] as List).first,
      allOf(containsPair('shape', 'stadium'), contains('color')),
    );
  });

  testWidgets('says what it cannot read: the app\'s own painters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomPaint(
          key: const ValueKey('chart'),
          painter: _Chart(),
          size: const Size(100, 50),
        ),
      ),
    );
    final style = styleOf(tester, find.byKey(const ValueKey('chart')));
    expect(style['note'], contains('1 CustomPaint inside'));
  });

  test('colors are #RRGGBB, with alpha only when translucent', () {
    expect(StyleExplorer.hex(const Color(0xFF0F172A)), '#0F172A');
    expect(StyleExplorer.hex(const Color(0x800F172A)), '#0F172A80');
  });
}

class _Chart extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_Chart oldDelegate) => false;
}
