import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/flight_recorder.dart';
import 'package:flutterpilot_sdk/src/repro_test_generator.dart';

void main() {
  group('FlightRecorder & ReproTestGenerator', () {
    setUp(() {
      FlightRecorder.clear();
    });

    test('records discrete events and generates timeline', () {
      FlightRecorder.recordRoute('push', {'name': '/home'});
      FlightRecorder.recordGesture('tapWidget', {'key': 'submit_btn'});
      FlightRecorder.recordState('riverpod', 'counterProvider', 1);

      final timeline = FlightRecorder.getTimeline();
      expect(timeline.length, equals(3));
      expect(timeline[0]['category'], equals('route'));
      expect(timeline[0]['action'], equals('push'));
      expect(timeline[1]['category'], equals('gesture'));
      expect(timeline[1]['action'], equals('tapWidget'));
      expect(timeline[2]['category'], equals('state'));
    });

    test('evicts oldest events when buffer exceeds max limit', () {
      for (int i = 0; i < FlightRecorder.maxEvents + 10; i++) {
        FlightRecorder.record('action', 'step_$i', {'index': i});
      }

      final timeline = FlightRecorder.getTimeline();
      expect(timeline.length, equals(FlightRecorder.maxEvents));
      expect(timeline.first['action'], equals('step_10'));
      expect(timeline.last['action'], equals('step_${FlightRecorder.maxEvents + 9}'));
    });

    test('freezes crash snapshot on recordError', () {
      FlightRecorder.recordRoute('push', {'name': '/checkout'});
      FlightRecorder.recordGesture('tapWidget', {'key': 'pay_btn'});
      FlightRecorder.recordError('NullPointerException: user is null', 'StackTrace...');

      // Add another action after crash
      FlightRecorder.recordGesture('tapWidget', {'key': 'retry_btn'});

      final json = FlightRecorder.getFlightLogJson();
      expect(json['hasCrashSnapshot'], isTrue);
      expect(json['lastException'], contains('NullPointerException'));

      final frozenTimeline = FlightRecorder.getTimeline(useFrozen: true);
      expect(frozenTimeline.length, equals(3));
      expect(frozenTimeline.last['action'], equals('unhandled_exception'));
    });

    test('synthesizes valid repro_test.dart Dart code', () {
      FlightRecorder.recordRoute('push', {'name': '/settings'});
      FlightRecorder.recordGesture('tapWidget', {'key': 'ElevatedButton[\'Save\']'});
      FlightRecorder.recordGesture('enterText', {'key': 'username_field', 'text': 'john_doe'});

      final code = ReproTestGenerator.generate(
        testName: 'Repro Settings Save Flow',
        initialWidgetName: 'SettingsApp()',
      );

      expect(code, contains("testWidgets('Repro Settings Save Flow'"));
      expect(code, contains('await tester.pumpWidget(const SettingsApp());'));
      expect(code, contains("await tester.tap(find.text('Save'));"));
      expect(code, contains("await tester.enterText(find.byKey(const ValueKey('username_field')), 'john_doe');"));
      expect(code, contains('expect(tester.takeException(), isNull);'));
    });
  });
}
