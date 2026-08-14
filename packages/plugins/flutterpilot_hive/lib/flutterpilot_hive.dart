import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// Inspects Hive boxes for FlutterPilot.
///
/// Exposes a `ext.flutterpilot.getHiveContents` service extension that returns
/// the contents of all registered (and currently open) boxes.
///
/// ## Setup
/// ```dart
/// final box = await Hive.openBox('settings');
/// HivePilotInspector.registerBox('settings');
/// ```
class HivePilotInspector {
  static final Set<String> _registeredBoxNames = {};
  static bool _initialized = false;
  static const int _maxResultSize = 100000;

  static void registerBox(String boxName) {
    _registeredBoxNames.add(boxName);
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  /// Removes a box from inspection.
  static void unregisterBox(String name) {
    _registeredBoxNames.remove(name);
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _registeredBoxNames.clear();
    _initialized = false;
  }

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
      final Map<String, dynamic> allData = {};
      for (final boxName in _registeredBoxNames) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final boxData = Hive.box(boxName).toMap();
            final encoded = json.encode(boxData);
            if (encoded.length > _maxResultSize) {
              allData[boxName] = {
                '_truncated': true,
                '_keyCount': boxData.length,
                '_note': 'Box contents exceed size limit',
              };
            } else {
              allData[boxName] = boxData;
            }
          } else {
            allData[boxName] = {'_status': 'closed'};
          }
        } catch (e) {
          allData[boxName] = {'_error': e.toString()};
        }
      }
      return ServiceExtensionResponse.result(
        json.encode({'contents': allData}),
      );
    });
  }
}
