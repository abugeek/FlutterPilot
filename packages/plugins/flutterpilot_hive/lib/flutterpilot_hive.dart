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

  static const int _maxScenarioEntries = 1000;

  /// Whether JSON holds [v] as it is (so a scenario can put it back).
  static bool _isPlain(Object? v) => switch (v) {
    null || bool() || num() || String() => true,
    List() => v.every(_isPlain),
    Map() => v.entries.every((e) => e.key is String && _isPlain(e.value)),
    _ => false,
  };

  /// The registered boxes for a scenario file: `boxes` holds each one as
  /// `[[key, value], ...]` (keys keep their type), `skipped` the ones JSON
  /// can't hold (adapter objects, dates) and why.
  static Map<String, Object?> dump() {
    final boxes = <String, Object?>{};
    final skipped = <String>[];
    for (final MapEntry(key: name, value: dynamic box) in _boxes.entries) {
      try {
        if (box.isOpen != true) {
          skipped.add('$name (closed)');
          continue;
        }
        final map = box.toMap() as Map;
        final odd = map.values.where((v) => !_isPlain(v));
        if (odd.isNotEmpty) {
          skipped.add('$name (holds ${odd.first.runtimeType} objects)');
        } else if (map.length > _maxScenarioEntries) {
          skipped.add('$name (${map.length} entries)');
        } else {
          boxes[name] = [
            for (final e in map.entries) [e.key, e.value],
          ];
        }
      } catch (e) {
        skipped.add('$name ($e)');
      }
    }
    return {'boxes': boxes, 'skipped': skipped};
  }

  /// Empties and fills each box in [data] (`{name: [[key, value], ...]}`).
  static Future<Map<String, Object?>> restore(Map<String, dynamic> data) async {
    final restored = <String, int>{};
    final errors = <String, String>{};
    for (final MapEntry(key: name, value: entries) in data.entries) {
      final dynamic box = _boxes[name];
      if (box == null || box.isOpen != true) {
        errors[name] =
            'no open Hive box registered as "$name" '
            '(registered: ${_boxes.keys.join(', ')})';
        continue;
      }
      try {
        await box.clear();
        for (final e in entries as List) {
          await box.put((e as List)[0], e[1]);
        }
        restored[name] = entries.length;
      } catch (e) {
        errors[name] = '$e';
      }
    }
    return {'restored': restored, 'errors': errors};
  }

  static void _registerExtension() {
    FlutterPilot.registerCapability(
      'hive',
      version: '1',
      extensions: [
        'ext.flutterpilot.getHiveContents',
        'ext.flutterpilot.dumpHive',
        'ext.flutterpilot.restoreHive',
      ],
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

    // -- ext.flutterpilot.dumpHive ----------------------------------------
    // For a scenario file: each open box as [[key, value], ...] (keys keep
    // their type), or why it can't be written as JSON.
    registerExtension('ext.flutterpilot.dumpHive', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode(dump()));
    });

    // -- ext.flutterpilot.restoreHive -------------------------------------
    // data: {boxName: [[key, value], ...]}: each box named is emptied and
    // filled.
    registerExtension('ext.flutterpilot.restoreHive', (
      method,
      parameters,
    ) async {
      try {
        return ServiceExtensionResponse.result(
          json.encode(
            await restore(
              (json.decode(parameters['data'] ?? '{}') as Map)
                  .cast<String, dynamic>(),
            ),
          ),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'data is not JSON: $e',
        );
      }
    });
  }
}
