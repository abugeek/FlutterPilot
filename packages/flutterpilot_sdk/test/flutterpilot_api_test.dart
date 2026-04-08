import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterPilot API', () {
    test('isInitialized returns true after initialize()', () {
      FlutterPilot.initialize();
      expect(FlutterPilot.isInitialized, isTrue);
    });

    test('registerStateSetter accepts multiple types', () {
      FlutterPilot.initialize();

      expect(
        () => FlutterPilot.registerStateSetter(
          'riverpod',
          (name, value) async => {'status': 'ok'},
        ),
        returnsNormally,
      );

      expect(
        () => FlutterPilot.registerStateSetter(
          'bloc',
          (name, value) async => {'status': 'ok'},
        ),
        returnsNormally,
      );

      expect(
        () => FlutterPilot.registerStateSetter(
          'custom',
          (name, value) async => {'status': 'ok'},
        ),
        returnsNormally,
      );
    });

    test('registerCustomTool accepts tool registration', () {
      FlutterPilot.initialize();

      expect(
        () => FlutterPilot.registerCustomTool(
          'test_tool',
          (params) async => {'result': 'success'},
        ),
        returnsNormally,
      );
    });

    test('registerCustomTool can register multiple tools', () {
      FlutterPilot.initialize();

      for (var i = 0; i < 5; i++) {
        expect(
          () => FlutterPilot.registerCustomTool(
            'tool_$i',
            (params) async => {'id': i},
          ),
          returnsNormally,
        );
      }
    });

    test('logStateChange does not throw for various data types', () {
      FlutterPilot.initialize();

      // String value
      expect(
        () => FlutterPilot.logStateChange('source1', 'name1', 'string_value'),
        returnsNormally,
      );

      // Map value
      expect(
        () => FlutterPilot.logStateChange('source2', 'name2', {'key': 'val'}),
        returnsNormally,
      );

      // List value
      expect(
        () => FlutterPilot.logStateChange('source3', 'name3', [1, 2, 3]),
        returnsNormally,
      );

      // Null value
      expect(
        () => FlutterPilot.logStateChange('source4', 'name4', null),
        returnsNormally,
      );

      // Numeric value
      expect(
        () => FlutterPilot.logStateChange('source5', 'name5', 42),
        returnsNormally,
      );

      // Boolean value
      expect(
        () => FlutterPilot.logStateChange('source6', 'name6', true),
        returnsNormally,
      );
    });

    test('localeNotifier is a ValueNotifier<Locale?>', () {
      FlutterPilot.initialize();
      expect(FlutterPilot.localeNotifier, isA<ValueNotifier<ui.Locale?>>());
      expect(FlutterPilot.localeNotifier.value, isNull);
    });

    test('localeNotifier can be set to a Locale', () {
      FlutterPilot.initialize();
      FlutterPilot.localeNotifier.value = const ui.Locale('en', 'US');
      expect(FlutterPilot.localeNotifier.value, const ui.Locale('en', 'US'));

      FlutterPilot.localeNotifier.value = const ui.Locale('de', 'DE');
      expect(FlutterPilot.localeNotifier.value, const ui.Locale('de', 'DE'));

      // Reset
      FlutterPilot.localeNotifier.value = null;
    });
  });
}
