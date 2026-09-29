import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/ai_overlay_manager.dart';
import 'package:flutterpilot_sdk/src/screen_capture.dart';

/// Captures the window the way capture_screenshot does; the frame the
/// capture waits for is pumped here (tests have no real frames).
Future<ui.Image> capture(WidgetTester tester, {double pixelRatio = 1}) async {
  final settled = ScreenCapture.settle();
  await tester.pump();
  await settled;
  return (await tester.runAsync(
    () => ScreenCapture.grab(pixelRatio: pixelRatio),
  ))!;
}

Future<Color> pixel(WidgetTester tester, ui.Image image, Offset at) async {
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final i = ((at.dy.round() * image.width) + at.dx.round()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

const red = Color(0xFFFF0000);
const white = Color(0xFFFFFFFF);

Widget app({VoidCallback? onOpen}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      backgroundColor: white,
      body: Align(
        alignment: Alignment.topLeft,
        child: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: red),
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a dialog on the root navigator is in the picture', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final image = await capture(tester);
    expect(image.width, 800);
    expect(await pixel(tester, image, const Offset(400, 300)), red);
  });

  testWidgets('the tap badge is not in the picture', (tester) async {
    await tester.pumpWidget(app());
    AiOverlayManager.showAction(const Offset(400, 300), 'Tap');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('🤖 Tap'), findsOneWidget);

    // Without settling, the last frame still shows it.
    final before = (await tester.runAsync(() => ScreenCapture.grab()))!;
    expect(await pixel(tester, before, const Offset(400, 300)), isNot(white));

    final image = await capture(tester);
    expect(find.text('🤖 Tap'), findsNothing);
    expect(await pixel(tester, image, const Offset(400, 300)), white);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('pixelRatio scales the picture', (tester) async {
    await tester.pumpWidget(app());
    final image = await capture(tester, pixelRatio: 0.5);
    expect([image.width, image.height], [400, 300]);
  });
}
