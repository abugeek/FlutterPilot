import 'dart:convert';

import 'package:flutterpilot_server/src/scenario.dart';
import 'package:test/test.dart';

void main() {
  test('a scenario file round-trips and says what it sets', () {
    final s = Scenario(
      description: 'Dark theme, feed filtered to AI',
      route: '/',
      prefs: {'theme_mode': 'dark', 'launches': 3},
      mocks: [
        {'urlPattern': '/ping', 'statusCode': 500, 'body': '{}'},
      ],
      riverpod: {'NotifierProvider<SearchNotifier, String>': 'AI'},
    );
    final back = Scenario.fromJson(
      jsonDecode(s.encode()) as Map<String, dynamic>,
    );
    expect(back.toJson(), s.toJson());
    expect(
      back.summary,
      'route /, 2 preference(s), 1 mocked response(s), 1 state value(s)',
    );
    // Hand-written files may leave parts out: no prefs = don't touch them.
    final minimal = Scenario.fromJson({'route': '/cart'});
    expect(minimal.prefs, isNull);
    expect(minimal.summary, 'route /cart');
  });

  test('preferences map to the setter types', () {
    expect(prefForSetter(true), (type: 'bool', value: 'true'));
    expect(prefForSetter(3), (type: 'int', value: '3'));
    expect(prefForSetter(1.5), (type: 'double', value: '1.5'));
    expect(prefForSetter('dark'), (type: 'string', value: 'dark'));
    expect(prefForSetter(['a', 'b']), (type: 'stringList', value: '["a","b"]'));
    expect(prefForSetter({'a': 1}), isNull);
  });

  test('only states set_state can put back are kept', () {
    final r = restorableStates({
      'counterProvider': {'value': '3', 'type': 'int'},
      'searchProvider': {'value': 'AI', 'type': 'String'},
      'onboardedProvider': {'value': 'true', 'type': 'bool'},
      'themeProvider': {'value': 'ThemeMode.dark', 'type': 'ThemeMode'},
      'apiProvider': {'value': "Instance of 'HnApi'", 'type': 'HnApi'},
      'feedProvider': {
        'value': 'AsyncLoading<List<Item>>()',
        'type': 'AsyncLoading<List<Item>>',
      },
    }, 'value');
    expect(r.kept, {
      'counterProvider': 3,
      'searchProvider': 'AI',
      'onboardedProvider': true,
    });
    // Services and loading futures are not worth a mention.
    expect(r.skipped, ['themeProvider (ThemeMode)']);
  });
}
