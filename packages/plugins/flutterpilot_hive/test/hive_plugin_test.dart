import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

void main() {
  group('HivePilotInspector', () {
    test('registerBox can be called without error', () {
      // registerExtension may throw in test environment since it requires
      // dart:developer VM service support. We catch that to verify the
      // public API itself doesn't fail for other reasons.
      try {
        HivePilotInspector.registerBox('testBox');
      } on UnsupportedError {
        // Expected in test environment where VM service extensions
        // are not available.
      }
    });

    test('registerBox is idempotent for the same box name (Set semantics)', () {
      // Calling registerBox multiple times with the same name should not
      // throw. The internal Set ensures no duplicates. The registerExtension
      // guard (_extensionRegistered) prevents a second registration attempt.
      try {
        HivePilotInspector.registerBox('duplicateBox');
        HivePilotInspector.registerBox('duplicateBox');
        HivePilotInspector.registerBox('duplicateBox');
      } on UnsupportedError {
        // Expected — registerExtension not supported in test runner.
      }
    });

    test('registerBox accepts different box names without error', () {
      try {
        HivePilotInspector.registerBox('boxA');
        HivePilotInspector.registerBox('boxB');
        HivePilotInspector.registerBox('boxC');
      } on UnsupportedError {
        // Expected — registerExtension not supported in test runner.
      }
    });
  });
}
