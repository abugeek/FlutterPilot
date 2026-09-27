import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// Inspects Hive boxes for FlutterPilot.
///
/// Exposes a `ext.flutterpilot.getHiveContents` service extension that returns
/// the contents of every registered box.
///
/// Works with both `hive` and `hive_ce`: pass the opened box itself, so the
/// plugin never has to look it up in (the wrong) Hive singleton.
///
/// ## Setup
/// ```dart
/// final settings = await Hive.openBox('settings');
/// HivePilotInspector.registerBox(settings);
/// ```
class HivePilotInspector {
  // Boxes are held as `dynamic`: hive and hive_ce have identical but
  // unrelated `Box` types (name, isOpen, toMap()).
  static final Map<String, dynamic> _boxes = {};
  static bool _initialized = false;
  static const int _maxBoxChars = 100000;

  /// Registers an opened Hive (or Hive CE) [box] for inspection.
  static void registerBox(Object box) {
    final dynamic b = box;
    final String name;
    try {
      name = b.name as String;
      b.toMap();
    } on NoSuchMethodError {
      throw ArgumentError.value(
        box,
        'box',
        'Pass the opened Box (await Hive.openBox(...)), not its name',
      );
    }
    _boxes[name] = box;
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  /// Removes a box from inspection.
  static void unregisterBox(String name) {
    _boxes.remove(name);
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _boxes.clear();
    _initialized = false;
  }

  /// JSON-safe contents of every registered box. Keys become strings (Hive
  /// uses int keys for `box.add`); values JSON can't hold become strings.
  static Map<String, dynamic> contents() {
    final all = <String, dynamic>{};
    for (final MapEntry(key: name, value: dynamic box) in _boxes.entries) {
      try {
        if (box.isOpen != true) {
          all[name] = {'_status': 'closed'};
          continue;
        }
        final map = box.toMap() as Map;
        final entries = {
          for (final e in map.entries) '${e.key}': _jsonSafe(e.value),
        };
        all[name] = json.encode(entries).length > _maxBoxChars
            ? {
                '_truncated': true,
                '_keyCount': entries.length,
                '_keys': entries.keys.take(50).toList(),
              }
            : entries;
      } catch (e) {
        all[name] = {'_error': '$e'};
      }
    }
    return all;
  }

  static Object? _jsonSafe(Object? v) => switch (v) {
    null || bool() || num() || String() => v,
    DateTime() => v.toIso8601String(),
    List() => [for (final x in v) _jsonSafe(x)],
    Map() => {for (final e in v.entries) '${e.key}': _jsonSafe(e.value)},
    _ => v.toString(),
  };

  static void _registerExtension() {
    FlutterPilot.registerCapability(
      'hive',
      version: '1',
      extensions: ['ext.flutterpilot.getHiveContents'],
    );
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: HivePilotInspector registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    registerExtension('ext.flutterpilot.getHiveContents', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'contents': contents()}),
      );
    });
  }
}
