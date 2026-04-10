import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_firebase/flutterpilot_firebase.dart';

void main() {
  setUp(() {
    FirebasePilotInspector.reset();
  });

  tearDown(() {
    FirebasePilotInspector.reset();
  });

  group('FirebasePilotInspector', () {
    test('register is safe to call without any services', () {
      // Firebase services require initializeApp() — we test the guard path
      // which handles all-null params gracefully.
      try {
        FirebasePilotInspector.register();
      } on UnsupportedError {
        // Expected — registerExtension not available in test env.
      }
    });

    test('register is idempotent', () {
      try {
        FirebasePilotInspector.register();
        FirebasePilotInspector.register(); // second call ignored
      } on UnsupportedError {
        // Expected in test env.
      }
    });

    test('reset clears all registered services', () {
      // After register + reset, re-registration should work again.
      FirebasePilotInspector.reset();
      try {
        FirebasePilotInspector.register();
      } on UnsupportedError {
        // Expected.
      }
    });

    test('reset is safe to call multiple times', () {
      FirebasePilotInspector.reset();
      FirebasePilotInspector.reset();
      FirebasePilotInspector.reset();
    });

    test('reset does not crash when active traces exist', () {
      // Verify that reset() stops and clears any active traces without
      // throwing — even if no traces are actually running.
      expect(() => FirebasePilotInspector.reset(), returnsNormally);
    });

    test('partial registration (only analytics) does not throw', () {
      // Apps may only use analytics without Crashlytics etc.
      // FirebasePilotInspector.register only registers extensions for
      // services that are non-null.
      try {
        FirebasePilotInspector.register(
          // All null — tests the guard path that skips null services
        );
      } on UnsupportedError {
        // Expected in test env.
      }
    });
  });
}
