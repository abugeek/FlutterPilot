import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/accessibility_auditor.dart';

void main() {
  Future<Map<String, dynamic>> audit(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(backgroundColor: Colors.white, body: body),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();
    final result = (await tester.runAsync(AccessibilityAuditor.audit))!;
    AccessibilityAuditor.debugReleaseSemantics();
    handle.dispose();
    return result;
  }

  testWidgets('an icon button without a tooltip has no label', (tester) async {
    final result = await audit(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.bookmark), onPressed: () {}),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    final unlabeled = (result['unlabeled'] as List).cast<String>();
    expect(unlabeled, hasLength(1));
    expect(unlabeled.single, startsWith('Button at ('));
    expect(unlabeled.single, contains('has no label'));
    expect(unlabeled.single, contains('accessibility_auditor_test.dart:'));
    final order = (result['readingOrder'] as List).cast<String>();
    expect(order, [startsWith('button (no label)'), startsWith('"Share"')]);
  });

  testWidgets('a merged label is read once, with its button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Add todo'),
          ),
          body: Center(
            child: FilledButton(onPressed: () {}, child: const Text('Retry')),
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();
    final result = (await tester.runAsync(AccessibilityAuditor.audit))!;
    AccessibilityAuditor.debugReleaseSemantics();
    handle.dispose();
    final order = (result['readingOrder'] as List).cast<String>();
    expect(order, [startsWith('"Retry"'), startsWith('"Add todo"')]);
  });

  testWidgets('a gesture wrapper over a labeled tile is a silent stop', (
    tester,
  ) async {
    final result = await audit(
      tester,
      ListView(
        children: [
          for (var i = 0; i < 2; i++)
            GestureDetector(
              onSecondaryTapUp: (_) {},
              child: ListTile(title: Text('Story $i'), onTap: () {}),
            ),
        ],
      ),
    );
    final unlabeled = (result['unlabeled'] as List).cast<String>();
    // Grouped: one line for both rows, naming the wrapper.
    expect(unlabeled, hasLength(1));
    expect(unlabeled.single, startsWith('Tappable ×2 at (0, 0), (0, 56)'));
    expect(unlabeled.single, contains('Code: GestureDetector '));
    expect(unlabeled.single, contains('It covers "Story 0" (same box)'));
    expect(unlabeled.single, contains('excludeFromSemantics: true'));
  });

  testWidgets('faint text fails contrast, dark text passes', (tester) async {
    final result = await audit(
      tester,
      Column(
        children: [
          // Same code twice (a list row): one issue.
          for (var i = 0; i < 2; i++)
            Text('Faint $i', style: const TextStyle(color: Color(0xFFBBBBBB))),
          const Text('Dark text', style: TextStyle(color: Color(0xFF222222))),
        ],
      ),
    );
    final low = (result['lowContrast'] as List).cast<String>();
    expect(low, hasLength(1));
    expect(low.single, startsWith('"Faint 0" and 1 more like it contrast 1.'));
    expect(low.single, contains('#bbbbbb on #ffffff'));
    expect(low.single, contains('needs 4.5:1 for body text'));
  });

  // Field test (Octana): a disabled "Next" button was reported at 3.18:1.
  testWidgets('a disabled control is exempt from contrast', (tester) async {
    const faint = TextStyle(color: Color(0xFFBBBBBB));
    final result = await audit(
      tester,
      Column(
        children: [
          const TextButton(onPressed: null, child: Text('Next', style: faint)),
          TextButton(
            onPressed: () {},
            child: const Text('Back', style: faint),
          ),
        ],
      ),
    );
    final low = (result['lowContrast'] as List).cast<String>();
    expect(low, hasLength(1));
    expect(low.single, startsWith('"Back"'));
  });

  // An app on the separate material_ui package has its own button classes.
  testWidgets('a disabled control of another widget library is exempt too', (
    tester,
  ) async {
    const faint = TextStyle(color: Color(0xFFBBBBBB));
    final result = await audit(
      tester,
      const Column(
        children: [
          _OtherLibraryButton(
            onPressed: null,
            child: Text('Next', style: faint),
          ),
        ],
      ),
    );
    expect(result['lowContrast'], isEmpty);
  });

  test('WCAG contrast ratio', () {
    expect(
      AccessibilityAuditor.contrastRatio(0xff000000, 0xffffffff),
      closeTo(21, 0.01),
    );
    expect(
      AccessibilityAuditor.contrastRatio(0xff777777, 0xffffffff),
      closeTo(4.48, 0.01),
    );
    expect(AccessibilityAuditor.isLarge(18, false), isTrue);
    expect(AccessibilityAuditor.isLarge(14, true), isTrue);
    expect(AccessibilityAuditor.isLarge(16, false), isFalse);
  });

  test('reading order jumps back up the screen', () {
    final jumps = AccessibilityAuditor.readingOrderJumps([
      ('"Search"', const Rect.fromLTWH(0, 60, 100, 40)),
      ('"Save"', const Rect.fromLTWH(0, 500, 100, 40)),
      ('"Menu"', const Rect.fromLTWH(0, 10, 40, 40)),
      ('"Next"', const Rect.fromLTWH(200, 12, 40, 40)), // same row: fine
    ]);
    expect(jumps, [
      'After "Save" (y 500) a screen reader goes back up to "Menu" (y 10).',
    ]);
  });

  // Field test (Octana, 1280 dp): a two-column dashboard was reported as a
  // jump although left column then right column is the order to read it in.
  test('moving up into the next column is not a jump', () {
    const leftBottom = ('"Ledger"', Rect.fromLTWH(289, 324, 450, 60));
    const rightTop = ('"Fuel Sale"', Rect.fromLTWH(781, 96, 480, 90));

    expect(
      AccessibilityAuditor.readingOrderJumps([leftBottom, rightTop]),
      isEmpty,
    );
    // Right to left, the next column is on the left: the same move is a jump.
    expect(
      AccessibilityAuditor.readingOrderJumps([leftBottom, rightTop], rtl: true),
      hasLength(1),
    );
    expect(
      AccessibilityAuditor.readingOrderJumps([
        rightTop.withY(324),
        leftBottom.withY(96),
      ], rtl: true),
      isEmpty,
    );
  });
}

extension on (String, Rect) {
  (String, Rect) withY(double y) =>
      ($1, Rect.fromLTWH($2.left, y, $2.width, $2.height));
}

/// Stands in for a button class that is not flutter/material's.
class _OtherLibraryButton extends StatelessWidget {
  const _OtherLibraryButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  VoidCallback? get onLongPress => null;

  @override
  Widget build(BuildContext context) => child;
}
