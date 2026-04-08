import 'dart:developer';
import 'dart:convert';
import 'package:hive/hive.dart';

/// A helper class to inspect Hive boxes for FlutterPilot.
class HivePilotInspector {
  static final Set<String> _registeredBoxNames = {};
  static bool _extensionRegistered = false;

  static void registerBox(String boxName) {
    _registeredBoxNames.add(boxName);
    if (!_extensionRegistered) {
      _extensionRegistered = true;
      _registerExtension();
    }
  }

  static void _registerExtension() {
    registerExtension('ext.flutterpilot.getHiveContents', (method, parameters) async {
      final Map<String, dynamic> allData = {};
      for (final boxName in _registeredBoxNames) {
        if (Hive.isBoxOpen(boxName)) allData[boxName] = Hive.box(boxName).toMap();
      }
      return ServiceExtensionResponse.result(json.encode({'contents': allData}));
    });
  }
}
