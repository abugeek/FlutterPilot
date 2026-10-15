/// What the last action response said was tappable, so the next one can
/// say "same" or only the difference. tap_widget averaged 839 characters in
/// field sessions, a third of it the same ten labels again.
///
/// The full list comes back at least every fourth time and after two
/// minutes: an agent whose context was compacted must not be left with
/// "same as before" and no "before".
class ScreenMemory {
  static const _maxShort = 3;
  static const _fresh = Duration(minutes: 2);

  List<String>? _last;
  int _lastCount = 0;
  int _short = 0;
  DateTime _fullAt = DateTime(0);

  void reset() => _last = null;

  /// The "Tappable now" line for [shown] (the first labels of [count]
  /// tappable elements).
  String tappable(List<String> shown, int count, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final last = _last;
    final quoted = shown.map((e) => '"$e"').join(', ');
    String full() {
      _short = 0;
      _fullAt = now;
      return 'Tappable now ($count): $quoted';
    }

    final String line;
    if (last == null ||
        _short >= _maxShort ||
        now.difference(_fullAt) > _fresh) {
      line = full();
    } else {
      final added = shown.where((e) => !last.contains(e)).toList();
      final removed = last.where((e) => !shown.contains(e)).toList();
      if (added.isEmpty && removed.isEmpty && count == _lastCount) {
        _short++;
        line = 'Tappable now ($count): same as after the previous call.';
      } else if (shown.length > 5 && added.length + removed.length <= 4) {
        _short++;
        line =
            'Tappable now ($count): as after the previous call'
            '${added.isEmpty ? '' : ', plus ${added.map((e) => '"$e"').join(', ')}'}'
            '${removed.isEmpty ? '' : ', without ${removed.map((e) => '"$e"').join(', ')}'}'
            '.';
      } else {
        line = full();
      }
    }
    _last = List.of(shown);
    _lastCount = count;
    return line;
  }
}
