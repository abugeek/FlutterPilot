import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'source_locator.dart';

/// Counts rebuilds of the widgets the app's own code creates, through
/// Flutter's [debugOnRebuildDirtyWidget] hook (debug builds only).
///
/// Framework internals (the AnimatedBuilder inside a chip) are left out: an
/// agent can only change the app's code, so those are noise. Each type keeps
/// one live element to name where it is created.
class RebuildProfiler {
  RebuildProfiler._();

  static final Map<Type, int> _counts = {};
  // Elements built at least once. Flutter's builtOnce flag is only kept up
  // to date while debugPrintRebuildDirtyWidgets is on, so it can't tell a
  // first build from a rebuild. An Expando lets unmounted elements go.
  static final Expando<bool> _built = Expando();
  static final Map<Type, WeakReference<Element>> _samples = {};
  static DateTime _since = DateTime.now();
  static bool _installed = false;
  static RebuildDirtyWidgetCallback? _previous;

  /// Starts counting. Not at app start: DevTools' "track widget rebuilds"
  /// asserts that no other hook is installed when it turns on.
  // ponytail: hook conflicts with DevTools rebuild tracking turned on later;
  // the inspector's own trackRebuildDirtyWidgets events avoid that if needed.
  static void initialize() {
    if (_installed || !kDebugMode) return;
    _installed = true;
    _since = DateTime.now();
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _onRebuild;
  }

  /// Stops counting and puts back the hook that was there before.
  static void dispose() {
    if (!_installed) return;
    _installed = false;
    debugOnRebuildDirtyWidget = _previous;
    _previous = null;
    reset();
  }

  static void reset() {
    _counts.clear();
    _samples.clear();
    _since = DateTime.now();
  }

  static void _onRebuild(Element element, bool builtOnce) {
    _previous?.call(element, builtOnce);
    if (_built[element] != true) {
      _built[element] = true; // its first build, not a rebuild
      return;
    }
    if (!debugIsWidgetLocalCreation(element.widget)) return;
    final type = element.widget.runtimeType;
    _counts[type] = (_counts[type] ?? 0) + 1;
    _samples[type] = WeakReference(element);
  }

  static Map<String, dynamic> getStats({String? filter, int minCount = 1}) {
    if (!kDebugMode) {
      return {
        'unavailable':
            'Rebuild counts need a debug build: Flutter only reports '
            'rebuilds there. Use profile_action for timings in profile.',
      };
    }
    if (!_installed) {
      initialize();
      return {
        'started': true,
        'sinceMs': 0,
        'totalRebuilds': 0,
        'widgetTypes': 0,
        'rebuilds': const [],
        'hints': const [],
      };
    }
    final f = filter?.toLowerCase();
    final rows = [
      for (final MapEntry(key: type, value: count) in _counts.entries)
        if (count >= minCount &&
            (f == null || type.toString().toLowerCase().contains(f)))
          (type: type, count: count),
    ]..sort((a, b) => b.count.compareTo(a.count));

    String? where(Type type) {
      final element = _samples[type]?.target;
      return element != null && element.mounted
          ? SourceLocator.locationOf(element)
          : null;
    }

    int countOf(bool Function(String) test) => _counts.entries
        .where((e) => test(e.key.toString()))
        .fold(0, (sum, e) => sum + e.value);

    final hints = <String>[];
    final consumers = countOf(
      (t) => t.startsWith('Consumer') || t.startsWith('ConsumerWidget'),
    );
    if (consumers >= 10) {
      hints.add(
        'Riverpod Consumers rebuilt $consumers times: '
        'ref.watch(provider.select(...)) rebuilds only when that field changes.',
      );
    }
    final blocBuilders = countOf((t) => t.startsWith('BlocBuilder'));
    if (blocBuilders >= 10) {
      hints.add(
        'BlocBuilders rebuilt $blocBuilders times: buildWhen skips states '
        'they do not show.',
      );
    }
    final roots = countOf(
      (t) => const {'MaterialApp', 'CupertinoApp', 'WidgetsApp'}.contains(t),
    );
    if (roots > 2) {
      hints.add(
        'The app root rebuilt $roots times: something above it '
        '(a provider or a MediaQuery read) changes; every screen rebuilds.',
      );
    }

    return {
      'sinceMs': DateTime.now().difference(_since).inMilliseconds,
      'totalRebuilds': _counts.values.fold(0, (a, b) => a + b),
      'widgetTypes': _counts.length,
      'rebuilds': [
        for (final row in rows.take(20))
          {
            'widget': row.type.toString(),
            'rebuilds': row.count,
            'createdAt': ?where(row.type),
          },
      ],
      if (rows.length > 20) 'moreTypes': rows.length - 20,
      'hints': hints,
    };
  }
}
