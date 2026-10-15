import 'dart:collection';

import 'redaction.dart';

/// The last state changes the plugins observed (Riverpod, Bloc) and the
/// route changes between them, oldest first: what happened before the
/// state an agent is looking at, in the order it happened.
///
/// Order and time only: what *caused* a change is not something an
/// observer is told.
class StateHistory {
  /// Changes kept; older ones are counted in [dropped].
  static const int maxEntries = 50;
  static const int _maxValueChars = 160;

  static final _entries = ListQueue<Map<String, Object?>>();
  static final _last = <String, String>{};

  /// Changes that fell out of the buffer since the last [clear].
  static int dropped = 0;

  static List<Map<String, Object?>> get entries => _entries.toList();

  static void clear() {
    _entries.clear();
    dropped = 0;
  }

  /// Everything, as after a hot restart (tests).
  static void reset() {
    clear();
    _last.clear();
  }

  /// A value of [name] from [source] ("riverpod", "bloc"): its first value
  /// is recorded as created, later ones with the value they replace.
  static void record(String source, String name, Object? value) {
    if (source == 'navigation') {
      _add({'source': source, 'name': name, 'to': ?value?.toString()});
      return;
    }
    final id = '$source/$name';
    final to = _text(name, value);
    final from = _last[id];
    _last[id] = to;
    _add({'source': source, 'name': name, 'from': ?from, 'to': to});
  }

  /// [name] is gone (an autoDispose provider nobody listens to, a closed
  /// bloc): the next value starts from scratch.
  static void disposed(String source, String name) {
    final from = _last.remove('$source/$name');
    _add({'source': source, 'name': name, 'from': ?from, 'disposed': true});
  }

  static void _add(Map<String, Object?> entry) {
    entry['at'] = DateTime.now().toIso8601String();
    _entries.add(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
      dropped++;
    }
  }

  static String _text(String name, Object? value) {
    if (Redaction.sensitiveName.hasMatch(name)) return Redaction.mask;
    var text = Redaction.text('$value');
    if (text.length > _maxValueChars) {
      text = '${text.substring(0, _maxValueChars)}…';
    }
    return text;
  }
}
