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

  static void registerBox(String boxName) {
    _registeredBoxNames.add(boxName);
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  static void _registerExtension() {
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
        if (Hive.isBoxOpen(boxName))
          allData[boxName] = Hive.box(boxName).toMap();
      }
      return ServiceExtensionResponse.result(
        json.encode({'contents': allData}),
      );
    });
  }
}
