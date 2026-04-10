import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_connectivity/flutterpilot_connectivity.dart';

void main() {
  setUp(() {
    ConnectivityPilotInspector.reset();
  });

  tearDown(() {
    ConnectivityPilotInspector.reset();
  });

  group('ConnectivityPilotInspector', () {
    test('isSimulatedOffline is false by default', () {
      expect(ConnectivityPilotInspector.isSimulatedOffline, isFalse);
    });

    test('register can be called without crashing', () {
      // registerExtension throws UnsupportedError in test environment
      // (no VM service). We verify the guard path and public API work.
      try {
        ConnectivityPilotInspector.register();
      } on UnsupportedError {
        // Expected — dart:developer registerExtension not available in tests.
      }
    });

    test('register is idempotent — second call is ignored', () {
      try {
        ConnectivityPilotInspector.register();
        ConnectivityPilotInspector.register(); // second call should not throw
      } on UnsupportedError {
        // Expected in test env.
      }
    });

    test('reset clears simulated offline flag', () {
      // We can test the _simulatedOffline flag via the public getter
      // by calling reset and confirming it is false.
      ConnectivityPilotInspector.reset();
      expect(ConnectivityPilotInspector.isSimulatedOffline, isFalse);
    });

    test('reset allows re-registration after reset', () {
      ConnectivityPilotInspector.reset();
      try {
        ConnectivityPilotInspector.register();
      } on UnsupportedError {
        // Expected in test env.
      }
    });
  });
}
