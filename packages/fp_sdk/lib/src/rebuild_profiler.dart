import 'package:flutter/widgets.dart';

/// Tracks widget rebuilds in FlutterPilot using Flutter's native
/// [debugOnRebuildDirtyWidget] callback.
///
/// Records element rebuild frequencies, identifies rebuild cascades
/// (hot rebuilders), and warns when root widgets rebuild excessively.
class RebuildProfiler {
  RebuildProfiler._();

  static final Map<String, int> _rebuildCounts = <String, int>{};
  static final Set<int> _knownElementIds = <int>{};
  static DateTime? _trackingStarted;
  static bool _installed = false;
  static RebuildDirtyWidgetCallback? _previousCallback;

  /// Initializes the rebuild profiler hook. Safe to call multiple times.
  static void initialize() {
    if (_installed) return;
    _installed = true;
    _trackingStarted = DateTime.now();

    _previousCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _onRebuild;
  }

  /// Stops tracking and restores previous callback.
  static void dispose() {
    if (!_installed) return;
    _installed = false;
    debugOnRebuildDirtyWidget = _previousCallback;
    _previousCallback = null;
  }

  /// Clears accumulated rebuild counts and resets tracking start timestamp.
  static void reset() {
    _rebuildCounts.clear();
    _knownElementIds.clear();
    _trackingStarted = DateTime.now();
  }

  static void _onRebuild(Element element, bool builtOnce) {
    _previousCallback?.call(element, builtOnce);

    final widgetType = element.widget.runtimeType.toString();
    // Exclude internal framework/overlay widgets that animate on every frame.
    if (widgetType.startsWith('_') ||
        widgetType == 'Transform' ||
        widgetType == 'CustomPaint' ||
        widgetType == 'RepaintBoundary') {
      return;
    }

    final id = identityHashCode(element);
    final isRebuild = builtOnce || !_knownElementIds.add(id);

    if (isRebuild) {
      final keyStr = element.widget.key != null ? ' [key: ${element.widget.key}]' : '';
      final identifier = '$widgetType$keyStr';
      _rebuildCounts[identifier] = (_rebuildCounts[identifier] ?? 0) + 1;
    }
  }

  /// Returns current rebuild stats, sorted by rebuild frequency.
  static Map<String, dynamic> getStats({String? filter, int minCount = 1}) {
    initialize();

    final now = DateTime.now();
    final durationMs = _trackingStarted != null
        ? now.difference(_trackingStarted!).inMilliseconds
        : 0;

    final sortedRebuilds = _rebuildCounts.entries
        .where((e) => e.value >= minCount)
        .where((e) => filter == null || e.key.toLowerCase().contains(filter.toLowerCase()))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalRebuilds = _rebuildCounts.values.fold<int>(0, (sum, count) => sum + count);

    // Identify hot rebuilders (widgets rebuilt >= 4 times)
    final hotRebuilders = sortedRebuilds
        .where((e) => e.value >= 4)
        .map((e) => {'widget': e.key, 'rebuilds': e.value})
        .toList();

    // Check if root MaterialApp/CupertinoApp or Scaffold rebuilt frequently
    final rootRebuilds = _rebuildCounts.entries
        .where((e) => e.key.startsWith('MaterialApp') || e.key.startsWith('CupertinoApp') || e.key.startsWith('WidgetsApp'))
        .fold<int>(0, (sum, e) => sum + e.value);

    final prescriptions = <String>[];
    if (hotRebuilders.isNotEmpty) {
      prescriptions.add(
        '${hotRebuilders.length} widget(s) rebuilt >= 4 times. '
        'Consider using const constructors, extracting subtrees into const widgets, or scoping state listeners.',
      );
    }
    if (rootRebuilds > 2) {
      prescriptions.add(
        'Root app rebuilt $rootRebuilds times. Check for top-level MediaQuery or InheritedWidget subscriptions.',
      );
    }
    if (_rebuildCounts.entries.any((e) => e.key.contains('Consumer') && e.value >= 4)) {
      prescriptions.add(
        'Riverpod Consumer rebuilt frequently. Use ref.watch(provider.select(...)) to listen only to necessary fields.',
      );
    }
    if (_rebuildCounts.entries.any((e) => e.key.contains('BlocBuilder') && e.value >= 4)) {
      prescriptions.add(
        'BlocBuilder rebuilt frequently. Add a buildWhen condition to filter redundant state updates.',
      );
    }

    return {
      'trackingDurationMs': durationMs,
      'totalRebuilds': totalRebuilds,
      'distinctWidgetCount': _rebuildCounts.length,
      'hotRebuilderCount': hotRebuilders.length,
      'rootAppRebuilds': rootRebuilds,
      'hotRebuilders': hotRebuilders,
      'rebuildCounts': [
        for (final entry in sortedRebuilds.take(20))
          {'widget': entry.key, 'rebuilds': entry.value},
      ],
      'prescriptions': prescriptions,
    };
  }
}
