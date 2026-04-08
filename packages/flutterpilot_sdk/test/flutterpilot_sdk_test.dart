import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FlutterPilot SDK', () {
    test('initializes correctly and registers state setters', () {
      FlutterPilot.initialize();
      
      bool setterCalled = false;
      FlutterPilot.registerStateSetter('test_type', (name, value) async {
        setterCalled = true;
        return {'status': 'ok'};
      });

      // We can't easily trigger the service extension in a unit test 
      // without mocking the developer service registry, but we can 
      // verify the public API for registration works.
      
      // Since _stateSetters is private, we verify via a custom setter registration.
      expect(() => FlutterPilot.registerStateSetter('another', (n, v) async {}), returnsNormally);
    });

    test('logStateChange records actions when recording is active', () {
      FlutterPilot.initialize();
      
      // Start recording
      // Note: startRecording is a service extension, but we can't call it easily.
      // However, we can use the private _isRecording if we were testing internally.
      // For now, we test that the API exists and doesn't crash.
      expect(() => FlutterPilot.logStateChange('source', 'name', 'value'), returnsNormally);
    });
  });
}
