import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/error_inspector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ErrorInspector', () {
    setUp(() {
      // Clear the buffer for each test if possible (since it's static)
      // Since it's private, we just hope the tests don't interfere too much
      // or we could add a clear method.
    });

    test('captures Flutter errors', () {
      ErrorInspector.initialize();

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: 'Test Exception',
          library: 'test_library',
        ),
      );

      expect(ErrorInspector.errors, isNotEmpty);
      expect(
        ErrorInspector.errors.last['exception'],
        contains('Test Exception'),
      );
      expect(ErrorInspector.errors.last['library'], 'test_library');
    });

    test('respects buffer limit of 10', () {
      ErrorInspector.initialize();

      for (var i = 0; i < 15; i++) {
        FlutterError.onError!(FlutterErrorDetails(exception: 'Error $i'));
      }

      expect(ErrorInspector.errors.length, 10);
      expect(ErrorInspector.errors.last['exception'], contains('Error 14'));
    });

    test('triggers onErrorCaptured callback', () {
      FlutterErrorDetails? caughtDetails;
      ErrorInspector.onErrorCaptured = (details) {
        caughtDetails = details;
      };

      FlutterError.onError!(
        FlutterErrorDetails(exception: 'Callback Exception'),
      );

      expect(caughtDetails, isNotNull);
      expect(caughtDetails!.exception.toString(), 'Callback Exception');
    });
  });
}
