import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterPilot.initialize();
  });

  test('registers extensions after init', () async {
    final prefs = await SharedPreferences.getInstance();
    // Should not throw
    SharedPrefsPilotInspector.register(prefs);
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
}
