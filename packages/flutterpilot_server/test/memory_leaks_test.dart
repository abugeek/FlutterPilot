import 'package:flutterpilot_server/src/memory_leaks.dart';
import 'package:test/test.dart';

typedef _Snap = Map<String, ({String name, String? library, int instances})>;

_Snap _snap(Map<String, int> counts) => {
  for (final MapEntry(key: name, value: n) in counts.entries)
    'classes/$name': (
      name: name,
      library: name.startsWith('_Tracker')
          ? 'package:hn_reader/ui/story_screen.dart'
          : 'dart:core',
      instances: n,
    ),
};

void main() {
  test('only classes that grow every round are reported', () {
    final growing = growingClasses([
      _snap({'_TrackerState': 1, 'String': 900, '_List': 40, 'Cache': 3}),
      _snap({'_TrackerState': 2, 'String': 950, '_List': 38, 'Cache': 4}),
      _snap({'_TrackerState': 3, 'String': 940, '_List': 45, 'Cache': 4}),
      _snap({'_TrackerState': 4, 'String': 990, '_List': 50, 'Cache': 5}),
    ]);
    // String dipped once, _List dipped, Cache stood still once.
    expect(growing.map((c) => c.name), ['_TrackerState']);
    final leak = growing.single;
    expect(leak.growth, 3);
    expect(leak.rounds, 3);
    expect(leak.counts, [1, 2, 3, 4]);
    expect(leak.library, 'package:hn_reader/ui/story_screen.dart');
    expect(leak.steady, isTrue);
  });

  test('path libraries come from classes, static owners and closures', () {
    final libs = pathLibraries([
      {
        'value': {
          'type': '@Instance',
          'class': {
            'name': '_ReadTrackerState',
            'library': {
              'type': '@Library',
              'uri': 'package:hn_reader/ui/story_screen.dart',
            },
          },
        },
      },
      {
        'value': {
          'type': '@Field',
          'name': 'readEvents',
          'owner': {'type': '@Library', 'uri': 'package:hn_reader/x.dart'},
        },
      },
      {
        'value': {'type': '@Instance', 'kind': 'List'},
      },
    ]).toList();
    expect(libs, [
      'package:hn_reader/ui/story_screen.dart',
      'package:hn_reader/x.dart',
    ]);
  });

  test('uneven growth is not steady (JIT code, caches)', () {
    final growing = growingClasses([
      _snap({'Code': 100}),
      _snap({'Code': 168}),
      _snap({'Code': 451}),
      _snap({'Code': 524}),
    ]);
    expect(growing.single.steady, isFalse);
  });

  test('a class that first appears after the baseline counts from 0', () {
    final growing = growingClasses([
      _snap({'String': 1}),
      _snap({'String': 1, '_TrackerState': 1}),
      _snap({'String': 1, '_TrackerState': 2}),
    ]);
    expect(growing.single.counts, [0, 1, 2]);
  });

  test('one snapshot tells nothing', () {
    expect(
      growingClasses([
        _snap({'A': 1}),
      ]),
      isEmpty,
    );
  });

  test('retaining path reads from the leaked object to the GC root', () {
    // As the VM returns it for a listener never removed from a global
    // ChangeNotifier (field-tested on hn_reader).
    final path = describeRetainingPath([
      {
        'value': {
          'type': '@Instance',
          'kind': 'PlainInstance',
          'class': {'name': '_ReadTrackerState'},
        },
      },
      {
        'value': {
          'type': '@Instance',
          'kind': 'Closure',
          'class': {'name': '_Closure'},
          'closureFunction': {'name': '_onRead'},
        },
      },
      {
        'value': {
          'type': '@Instance',
          'kind': 'List',
          'class': {'name': '_List'},
        },
        'parentField': 5,
        'parentListIndex': 5,
      },
      {
        'value': {
          'type': '@Instance',
          'kind': 'PlainInstance',
          'class': {'name': 'ChangeNotifier'},
        },
        'parentField': '_listeners@816329750',
      },
      {
        'value': {'type': '@Field', 'name': 'readEvents'},
      },
    ]);
    expect(
      path,
      '_ReadTrackerState ← closure _onRead ← _List[5] ← '
      'ChangeNotifier._listeners ← static readEvents',
    );
  });
}
