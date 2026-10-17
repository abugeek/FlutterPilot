import 'dart:math' as math;
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
    this.stabilityRatio = 0.85,
  }) : looping = looping ?? Expando<bool>();

  final Duration loopingAfter;
  final Expando<bool> looping;
  final double stabilityRatio;
  Map<Object, Offset>? _last;
  final _movingSince = <Object, DateTime>{};
  int _consecutiveStableSamples = 0;

  /// Adds a sample (text identity → global position) taken at [at]; true
  /// once nothing but looping text moved since the previous sample.
  ///
  /// When [routesSettled] is true and >= [stabilityRatio] of on-screen
  /// elements remain stationary across consecutive samples, the screen is
  /// considered settled even if dynamic tickers or blinking cursors continuously
  /// rebuild individual RenderParagraph instances.
  bool add(Map<Object, Offset> sample, DateTime at, {bool routesSettled = false}) {
    final last = _last;
    _last = sample;
    if (last == null) {
      _consecutiveStableSamples = 0;
      return false;
    }
    // Text that went away: something is still changing.
    var still = last.keys.every(sample.containsKey);
    var stationaryCount = 0;
    for (final MapEntry(key: text, value: position) in sample.entries) {
      if (looping[text] == true) {
        stationaryCount++;
        continue;
      }
      final before = last[text];
      if (before != null && (before - position).distanceSquared < 0.25) {
        _movingSince.remove(text);
        stationaryCount++;
        continue;
      }
      final since = _movingSince.putIfAbsent(text, () => at);
      if (at.difference(since) < loopingAfter) {
        still = false;
      } else {
        looping[text] = true;
        stationaryCount++;
      }
    }

    if (still) {
      return true;
    }

    if (routesSettled) {
      final total = math.max(last.length, sample.length);
      if (total >= 4 && (stationaryCount / total) >= stabilityRatio) {
        _consecutiveStableSamples++;
        if (_consecutiveStableSamples >= 2) {
          return true;
        }
      } else {
        _consecutiveStableSamples = 0;
      }
    } else {
      _consecutiveStableSamples = 0;
    }

    return false;
  }

  /// Starts over (a route transition began: its end is a new screen).
  void reset() {
    _last = null;
    _movingSince.clear();
    _consecutiveStableSamples = 0;
  }
}
