import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fp_sdk/fp_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetOfMark', () {
    setUp(() {
      SetOfMark.clear();
    });

    test('activeMarks registry findByIndex and clear', () {
      expect(SetOfMark.activeMarks, isEmpty);
      expect(SetOfMark.findByIndex(1), isNull);

      SetOfMark.activeMarks.add({
        'mark': 1,
        'type': 'ElevatedButton',
        'key': 'login',
        'text': 'Log In',
        'bounds': {'x': 10, 'y': 20, 'width': 100, 'height': 48},
        'center': {'x': 60, 'y': 44},
      });

      expect(SetOfMark.activeMarks.length, 1);
      final mark = SetOfMark.findByIndex(1);
      expect(mark, isNotNull);
      expect(mark!['type'], 'ElevatedButton');
      expect(mark['key'], 'login');

      SetOfMark.clear();
      expect(SetOfMark.activeMarks, isEmpty);
      expect(SetOfMark.findByIndex(1), isNull);
    });

    testWidgets('overlayMarks renders numbered badges onto canvas', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('test_btn'),
                onPressed: () {},
                child: const Text('Click Me'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 800),
        Paint()..color = Colors.blue,
      );
      final baseImage = await recorder.endRecording().toImage(400, 800);

      final elements = PilotWidgetInspector.getInteractiveElements();
      expect(elements, isNotEmpty);

      final labeledImage = await SetOfMark.overlayMarks(
        baseImage,
        elements,
        pixelRatio: 1.0,
      );
      expect(labeledImage.width, 400);
      expect(labeledImage.height, 800);
      expect(SetOfMark.activeMarks, isNotEmpty);
      expect(SetOfMark.activeMarks.first['mark'], 1);
    });
  });
}
