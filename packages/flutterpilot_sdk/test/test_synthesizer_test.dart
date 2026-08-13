import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/flight_recorder.dart';
import 'package:flutterpilot_sdk/src/test_synthesizer.dart';

void main() {
  group('TestSynthesizer', () {
    setUp(() {
      FlightRecorder.clear();
    });

    test('generates idiomatic Patrol test suite', () {
      FlightRecorder.recordRoute('push', {'name': '/login'});
      FlightRecorder.recordGesture('enterText', {'key': 'emailField', 'text': 'dev@test.com'});
      FlightRecorder.recordGesture('tapWidget', {'key': "ElevatedButton['Log In']"});
      FlightRecorder.recordRoute('push', {'name': '/dashboard'});

      final code = TestSynthesizer.generate(
        framework: TestFramework.patrol,
        testName: 'Login and Navigate to Dashboard',
        appWidget: 'MyApp()',
      );

      expect(code, contains("import 'package:patrol/patrol.dart';"));
      expect(code, contains("patrolTest('Login and Navigate to Dashboard', (\$) async {"));
      expect(code, contains('await \$.pumpWidgetAndSettle(const MyApp());'));
      expect(code, contains(r"await $(const ValueKey('emailField')).enterText('dev@test.com');"));
      expect(code, contains(r"await $('Log In').tap();"));
      expect(code, contains(r"// Route changed to: /dashboard"));
    });

    test('generates standard Flutter Integration Test suite', () {
      FlightRecorder.recordGesture('tapWidget', {'key': "Button['Checkout']"});

      final code = TestSynthesizer.generate(
        framework: TestFramework.integrationTest,
        testName: 'Checkout Flow Test',
      );

      expect(code, contains("import 'package:integration_test/integration_test.dart';"));
      expect(code, contains('IntegrationTestWidgetsFlutterBinding.ensureInitialized();'));
      expect(code, contains("testWidgets('Checkout Flow Test', (WidgetTester tester) async {"));
      expect(code, contains("await tester.tap(find.text('Checkout'));"));
      expect(code, contains('await tester.pumpAndSettle();'));
    });

    test('generates standard Flutter Widget Test suite', () {
      FlightRecorder.recordGesture('tapWidget', {'key': 'increment_btn'});

      final code = TestSynthesizer.generate(
        framework: TestFramework.widgetTest,
        testName: 'Counter Increment Test',
        appWidget: 'CounterApp()',
      );

      expect(code, contains("import 'package:flutter_test/flutter_test.dart';"));
      expect(code, contains('await tester.pumpWidget(const CounterApp());'));
      expect(code, contains("await tester.tap(find.byKey(const ValueKey('increment_btn')));"));
      expect(code, contains('await tester.pumpAndSettle();'));
    });

    test('handles empty flight event queue gracefully', () {
      final code = TestSynthesizer.generate(
        framework: TestFramework.patrol,
        testName: 'Empty Flow',
      );

      expect(code, contains("patrolTest('Empty Flow', (\$) async {"));
      expect(code, contains('expect(\$(MyApp()), findsOneWidget);'));
    });
  });
}
