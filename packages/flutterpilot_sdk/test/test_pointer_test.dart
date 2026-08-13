import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/interaction_manager.dart' as pilot;

void main() {
  group('TestPointer (pilot)', () {
    test('creates PointerDownEvent with correct position', () {
      final pointer = pilot.TestPointer(1, PointerDeviceKind.touch);
      final downEvent = pointer.down(const Offset(100.0, 200.0));

      expect(downEvent, isA<PointerDownEvent>());
      expect(downEvent.position, const Offset(100.0, 200.0));
      expect(downEvent.pointer, 1);
      expect(downEvent.kind, PointerDeviceKind.touch);
    });

    test('creates PointerUpEvent at last down position', () {
      final pointer = pilot.TestPointer(2, PointerDeviceKind.touch);
      pointer.down(const Offset(50.0, 75.0));
      final upEvent = pointer.up();

      expect(upEvent, isA<PointerUpEvent>());
      expect(upEvent.position, const Offset(50.0, 75.0));
      expect(upEvent.pointer, 2);
    });

    test('up() throws if called before down()', () {
      final pointer = pilot.TestPointer();
      expect(() => pointer.up(), throwsA(isA<StateError>()));
    });

    test('supports custom pointer IDs', () {
      final pointer = pilot.TestPointer(42, PointerDeviceKind.mouse);
      final downEvent = pointer.down(Offset.zero);

      expect(downEvent.pointer, 42);
      expect(downEvent.kind, PointerDeviceKind.mouse);
    });

    test('supports custom timestamp', () {
      final pointer = pilot.TestPointer();
      final downEvent = pointer.down(
        Offset.zero,
        timeStamp: const Duration(seconds: 5),
      );
      final upEvent = pointer.up(timeStamp: const Duration(seconds: 6));

      expect(downEvent.timeStamp, const Duration(seconds: 5));
      expect(upEvent.timeStamp, const Duration(seconds: 6));
    });

    test('location resets after up()', () {
      final pointer = pilot.TestPointer();
      pointer.down(const Offset(10.0, 20.0));
      pointer.up();

      // After up(), location is null again — calling up() again should throw
      expect(() => pointer.up(), throwsA(isA<StateError>()));
    });

    test('can perform multiple down/up sequences', () {
      final pointer = pilot.TestPointer(1, PointerDeviceKind.touch);

      // First tap
      final down1 = pointer.down(const Offset(100.0, 100.0));
      expect(down1.position, const Offset(100.0, 100.0));
      final up1 = pointer.up();
      expect(up1.position, const Offset(100.0, 100.0));

      // Second tap at different position
      final down2 = pointer.down(const Offset(200.0, 300.0));
      expect(down2.position, const Offset(200.0, 300.0));
      final up2 = pointer.up();
      expect(up2.position, const Offset(200.0, 300.0));
    });

    test('default constructor uses pointer=1 and touch kind', () {
      final pointer = pilot.TestPointer();
      final downEvent = pointer.down(Offset.zero);

      expect(downEvent.pointer, 1);
      expect(downEvent.kind, PointerDeviceKind.touch);
    });
  });
}
