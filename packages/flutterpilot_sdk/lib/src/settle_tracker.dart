import 'dart:ui';

/// Tells, from successive samples of where the on-screen text is, when the
/// screen has stopped moving.
///
/// Text that keeps moving longer than any transition does (a marquee, a
/// pulsing badge) is looping: it is ignored after [loopingAfter], so an app
/// with one doesn't make every action wait for the full timeout. Text found
/// looping is remembered in [looping], so the next action ignores it at
/// once.
class SettleTracker {
  SettleTracker({
    this.loopingAfter = const Duration(milliseconds: 600),
    Expando<bool>? looping,
  }) : looping = looping ?? Expando<bool>();

  final Duration loopingAfter;
  final Expando<bool> looping;
  Map<Object, Offset>? _last;
  final _movingSince = <Object, DateTime>{};

  /// Adds a sample (text identity → global position) taken at [at]; true
  /// once nothing but looping text moved since the previous sample.
  bool add(Map<Object, Offset> sample, DateTime at) {
    final last = _last;
    _last = sample;
    if (last == null) return false;
    // Text that went away: something is still changing.
    var still = last.keys.every(sample.containsKey);
    for (final MapEntry(key: text, value: position) in sample.entries) {
      if (looping[text] == true) continue;
      final before = last[text];
      if (before != null && (before - position).distanceSquared < 0.25) {
        _movingSince.remove(text);
        continue;
      }
      final since = _movingSince.putIfAbsent(text, () => at);
      if (at.difference(since) < loopingAfter) {
        still = false;
      } else {
        looping[text] = true;
      }
    }
    return still;
  }

  /// Starts over (a route transition began: its end is a new screen).
  void reset() {
    _last = null;
    _movingSince.clear();
  }
}
