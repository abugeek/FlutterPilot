import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

/// Same shape as hive's and hive_ce's `Box` (the plugin duck-types it).
class _FakeBox {
  _FakeBox(this.name, this._data, {this.isOpen = true});
  final String name;
  final Map<dynamic, dynamic> _data;
  final bool isOpen;
  Map<dynamic, dynamic> toMap() => _data;
  Future<int> clear() async {
    final n = _data.length;
    _data.clear();
    return n;
  }

  Future<void> put(dynamic key, dynamic value) async => _data[key] = value;
}

class _Note {
  @override
  String toString() => 'Note(groceries)';
}

void main() {
  setUp(HivePilotInspector.reset);

  test('int keys (box.add), DateTime and custom objects are JSON-safe', () {
    HivePilotInspector.registerBox(_FakeBox('recent', {0: 'milk', 1: 'eggs'}));
    HivePilotInspector.registerBox(
      _FakeBox('settings', {
        'sort': 'title',
        'lastSync': DateTime.utc(2026, 9, 27, 12),
        'draft': _Note(),
        'tags': ['a', 1, true],
      }),
    );

    final c = HivePilotInspector.contents();
    expect(() => json.encode(c), returnsNormally);
    expect(c['recent'], {'0': 'milk', '1': 'eggs'});
    expect(c['settings'], {
      'sort': 'title',
      'lastSync': '2026-09-27T12:00:00.000Z',
      'draft': 'Note(groceries)',
      'tags': ['a', 1, true],
    });
  });

  test('closed boxes are reported, not read', () {
    HivePilotInspector.registerBox(_FakeBox('old', {'a': 1}, isOpen: false));
    expect(HivePilotInspector.contents()['old'], {'_status': 'closed'});
  });

  test('passing a box name instead of the box explains the fix', () {
    expect(
      () => HivePilotInspector.registerBox('settings'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Pass the opened Box'),
        ),
      ),
    );
  });

  test(
    'a scenario gets plain boxes with typed keys, and puts them back',
    () async {
      final recent = <dynamic, dynamic>{0: 'milk', 1: 'eggs'};
      HivePilotInspector.registerBox(_FakeBox('recent', recent));
      HivePilotInspector.registerBox(_FakeBox('drafts', {'a': _Note()}));
      HivePilotInspector.registerBox(_FakeBox('old', {}, isOpen: false));

      final dump =
          json.decode(json.encode(HivePilotInspector.dump()))
              as Map<String, dynamic>;
      expect(dump['boxes'], {
        'recent': [
          [0, 'milk'],
          [1, 'eggs'],
        ],
      });
      expect(dump['skipped'], ['drafts (holds _Note objects)', 'old (closed)']);

      recent
        ..clear()
        ..[5] = 'tea';
      final res = await HivePilotInspector.restore({
        ...dump['boxes'] as Map<String, dynamic>,
        'gone': <Object?>[],
      });
      expect(recent, {0: 'milk', 1: 'eggs'});
      expect(res['restored'], {'recent': 2});
      expect((res['errors'] as Map).keys, ['gone']);
    },
  );
}
