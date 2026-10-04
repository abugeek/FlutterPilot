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

  test('stored data round-trips, one row per line', () {
    final s = Scenario(
      route: '/cart',
      channelMocks: [
        {'channel': 'app/scanner', 'method': 'start', 'result': true},
      ],
      databases: {
        'main': {
          'engine': 'drift',
          'tables': {
            'cart_items': [
              {'id': 1, 'name': 'Milk', 'qty': 2},
              {'id': 2, 'name': 'Tea', 'qty': 1},
            ],
            'orders': <Object?>[],
          },
          'sequences': {'cart_items': 2},
        },
      },
      hive: {
        'settings': [
          ['currency', 'UZS'],
          [0, true],
        ],
      },
    );
    final text = s.encode();
    expect(text, contains('          {"id":1,"name":"Milk","qty":2},\n'));
    expect(text, contains('      ["currency","UZS"],\n'));
    final back = Scenario.fromJson(jsonDecode(text) as Map<String, dynamic>);
    expect(back.toJson(), s.toJson());
    expect(
      back.summary,
      'route /cart, 1 platform-channel mock(s), 2 database row(s) in '
      '2 table(s), 1 Hive box(es)',
    );
    expect(back.replacesStoredData, isTrue);
    expect(Scenario(route: '/').replacesStoredData, isFalse);
  });

  test('a table with a credential column stays out of the file', () {
    final r = scenarioTables({
      'cart': [
        {'id': 1, 'author': 'Ann'},
      ],
      'sessions': [
        {'id': 1, 'access_token': 'eyJabc'},
      ],
      'empty': <Object?>[],
    });
    expect(r.kept.keys, ['cart', 'empty']);
    expect(r.secret, ['sessions']);
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
      'authTokenProvider': {'value': 'eyJabc', 'type': 'String'},
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
    // Scenario files are checked in: a credential never goes in one.
    expect(r.secret, ['authTokenProvider']);
  });
}
