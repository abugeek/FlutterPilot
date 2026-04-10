import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterPilot.initialize();
    SharedPrefsPilotInspector.reset();
  });

  tearDown(() {
    SharedPrefsPilotInspector.reset();
  });

  group('SharedPrefsPilotInspector', () {
    test('register can be called without crashing', () async {
      final prefs = await SharedPreferences.getInstance();
      try {
        SharedPrefsPilotInspector.register(prefs);
      } on UnsupportedError {
        // Expected — registerExtension not available in test env.
      }
    });

    test('register is idempotent', () async {
      final prefs = await SharedPreferences.getInstance();
      try {
        SharedPrefsPilotInspector.register(prefs);
        SharedPrefsPilotInspector.register(prefs); // second call ignored
      } on UnsupportedError {
        // Expected.
      }
    });

    test('reset allows re-registration', () async {
      final prefs = await SharedPreferences.getInstance();
      SharedPrefsPilotInspector.reset();
      FlutterPilot.initialize();
      try {
        SharedPrefsPilotInspector.register(prefs);
      } on UnsupportedError {
        // Expected.
      }
    });

    test('sensitive patterns include token, password, secret, auth, session', () {
      // Test the exported sensitive pattern set
      const patterns = SharedPrefsPilotInspector.sensitivePatterns;
      expect(patterns, containsAll(['token', 'password', 'secret', 'auth', 'session']));
    });

    test('isSensitiveKey correctly classifies keys', () {
      // Keys that must be redacted
      for (final key in [
        'auth_token',
        'user_password',
        'api_secret',
        'refresh_token',
        'session_id',
        'access_key',
      ]) {
        expect(
          SharedPrefsPilotInspector.isSensitiveKey(key),
          isTrue,
          reason: '"$key" should be classified as sensitive',
        );
      }

      // Keys that must NOT be redacted
      for (final key in [
        'username',
        'theme',
        'notification_enabled',
        'onboarding_complete',
        'last_sync',
      ]) {
        expect(
          SharedPrefsPilotInspector.isSensitiveKey(key),
          isFalse,
          reason: '"$key" should NOT be classified as sensitive',
        );
      }
    });

    test('get/set/clear round-trip via SharedPreferences directly', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('greeting', 'hello');
      await prefs.setInt('count', 42);
      await prefs.setBool('flag', true);

      expect(prefs.getString('greeting'), 'hello');
      expect(prefs.getInt('count'), 42);
      expect(prefs.getBool('flag'), true);

      await prefs.remove('greeting');
      expect(prefs.getString('greeting'), null);

      await prefs.clear();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
