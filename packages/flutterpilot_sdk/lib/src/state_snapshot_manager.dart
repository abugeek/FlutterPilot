import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'navigation_tracker.dart';

/// Represents a complete, point-in-time snapshot of the Flutter application state.
class StateSnapshot {
  final String name;
  final DateTime timestamp;
  final String? currentRoute;
  final List<String> navigationStack;
  final Map<String, dynamic> states;
  final Map<String, dynamic> storage;

  StateSnapshot({
    required this.name,
    required this.timestamp,
    this.currentRoute,
    this.navigationStack = const [],
    this.states = const {},
    this.storage = const {},
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    'currentRoute': currentRoute,
    'navigationStack': navigationStack,
    'states': states,
    'storage': storage,
  };

  factory StateSnapshot.fromJson(Map<String, dynamic> json) => StateSnapshot(
    name: json['name'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    currentRoute: json['currentRoute'] as String?,
    navigationStack: List<String>.from(json['navigationStack'] as List? ?? []),
    states: Map<String, dynamic>.from(json['states'] as Map? ?? {}),
    storage: Map<String, dynamic>.from(json['storage'] as Map? ?? {}),
  );
}

/// Manages in-memory and serialized time-travel state snapshots.
class StateSnapshotManager {
  static final Map<String, StateSnapshot> _snapshots = {};

  // State capture and restoration delegates
  static Map<String, dynamic> Function()? onCaptureStates;
  static Future<void> Function(Map<String, dynamic> states)? onRestoreStates;
  static Map<String, dynamic> Function()? onCaptureStorage;
  static Future<void> Function(Map<String, dynamic> storage)? onRestoreStorage;
  static Future<void> Function(String? route, List<String> stack)?
  onRestoreNavigation;

  /// Saves the current point-in-time state as a named snapshot.
  static StateSnapshot saveSnapshot(String name) {
    final currentRoute = NavigationTracker.currentRoute;
    final navStack = NavigationTracker.stack.whereType<String>().toList();
    final capturedStates = onCaptureStates != null
        ? onCaptureStates!()
        : <String, dynamic>{};
    final capturedStorage = onCaptureStorage != null
        ? onCaptureStorage!()
        : <String, dynamic>{};

    final clonedStates = _deepClone(capturedStates) as Map<String, dynamic>;
    final clonedStorage = _deepClone(capturedStorage) as Map<String, dynamic>;

    final snapshot = StateSnapshot(
      name: name,
      timestamp: DateTime.now(),
      currentRoute: currentRoute,
      navigationStack: List<String>.from(navStack),
      states: clonedStates,
      storage: clonedStorage,
    );

    _snapshots[name] = snapshot;
    return snapshot;
  }

  static dynamic _deepClone(dynamic val) {
    if (val is Map) {
      return val.map((k, v) => MapEntry(k.toString(), _deepClone(v)));
    } else if (val is List) {
      return val.map(_deepClone).toList();
    } else if (val is Set) {
      // JSON has no set type. Preserve the values while making the snapshot
      // exportable and deterministic.
      return val.map(_deepClone).toList();
    } else if (val is DateTime) {
      return val.toIso8601String();
    } else if (val is num || val is bool || val is String || val == null) {
      return val;
    }
    return val.toString();
  }

  /// Restores application state to the named snapshot.
  static Future<bool> restoreSnapshot(String name) async {
    final snapshot = _snapshots[name];
    if (snapshot == null) return false;

    // 1. Restore state values via delegate
    if (onRestoreStates != null && snapshot.states.isNotEmpty) {
      await onRestoreStates!(snapshot.states);
    }

    if (onRestoreStorage != null && snapshot.storage.isNotEmpty) {
      await onRestoreStorage!(snapshot.storage);
    }

    if (onRestoreNavigation != null) {
      await onRestoreNavigation!(
        snapshot.currentRoute,
        List<String>.unmodifiable(snapshot.navigationStack),
      );
    }

    // 2. Rebuild the Flutter widget tree to reflect state changes immediately
    try {
      void rebuildTree(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuildTree);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) {
        rebuildTree(root);
      }
    } catch (_) {}
    return true;
  }

  /// Lists all captured snapshots metadata.
  static List<Map<String, dynamic>> listSnapshots() {
    return _snapshots.values.map((s) => s.toJson()).toList();
  }

  /// Retrieves a specific snapshot by name.
  static StateSnapshot? getSnapshot(String name) => _snapshots[name];

  /// Deletes a snapshot by name.
  static bool deleteSnapshot(String name) => _snapshots.remove(name) != null;

  /// Clears all stored snapshots.
  static void clear() => _snapshots.clear();

  /// Exports all snapshots to a JSON string.
  static String exportJson() {
    final map = _snapshots.map((k, v) => MapEntry(k, v.toJson()));
    return json.encode(map);
  }

  /// Imports snapshots from a JSON string.
  static int importJson(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      int count = 0;
      decoded.forEach((key, val) {
        if (val is Map<String, dynamic>) {
          _snapshots[key] = StateSnapshot.fromJson(val);
          count++;
        }
      });
      return count;
    } catch (_) {
      return 0;
    }
  }
}
