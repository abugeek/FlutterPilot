import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/error_inspector.dart';

void main() {
  _compactStackTests();
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

void _compactStackTests() {
  group('compactStackTrace', () {
    test('keeps only the app frames when an agent tap caused the error', () {
      const raw = '''
#0      _HomeState.build.<anonymous closure> (package:fixture/main.dart:73:28)
#1      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1224:21)
#2      _LinkedHashMapMixin.forEach (dart:_compact_hash:721:13)
#3      InteractionManager.tapAt (package:flutterpilot_sdk/src/interaction_manager.dart:154:5)
<asynchronous suspension>
#4      _runExtension.<anonymous closure> (dart:developer-patch/developer.dart:140:13)
<asynchronous suspension>''';
      expect(
        ErrorInspector.compactStackTrace(raw),
        '#0      _HomeState.build.<anonymous closure> '
        '(package:fixture/main.dart:73:28)\n'
        '  ... [6 framework frames skipped]',
      );
    });

    test('web (DDC) frames are filtered the same way, in the VM form', () {
      const raw = '''
dart-sdk/lib/_internal/js_dev_runtime/private/ddc_runtime/errors.dart 274:3       throw_
package:fixture/main.dart 133:28                                                  <fn>
package:flutter/src/material/ink_well.dart 1224:21                                handleTap
package:flutterpilot_sdk/src/interaction_manager.dart 121:33                      <fn>
dart-sdk/lib/async/zone.dart 1034:54                                              runUnary''';
      expect(
        ErrorInspector.compactStackTrace(raw),
        '  ... [1 framework frames skipped]\n'
        '<fn> (package:fixture/main.dart:133:28)\n'
        '  ... [3 framework frames skipped]',
      );
    });

    test('an app package whose name starts with flutter is kept', () {
      const raw = '#0 f (package:flutter_app/main.dart:1:1)';
      expect(ErrorInspector.compactStackTrace(raw), raw);
    });
  });
}
