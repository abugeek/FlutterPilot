import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// FlutterPilot plugin that exposes [SharedPreferences] data to AI agents.
///
/// ## Setup
///
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// SharedPrefsPilotInspector.register(prefs);
/// ```
///
/// This registers three VM service extensions:
/// - `ext.flutterpilot.getSharedPreferences` — returns all keys and values
/// - `ext.flutterpilot.setSharedPreference` — writes a key-value pair
/// - `ext.flutterpilot.clearSharedPreferences` — clears one key or all keys
///
/// The MCP server exposes these as `get_shared_preferences`,
/// `set_shared_preference`, and `clear_shared_preferences` tools.
class SharedPrefsPilotInspector {
  SharedPrefsPilotInspector._();

  static bool _registered = false;
  static SharedPreferences? _prefs;

  /// Registers the [SharedPreferences] instance with FlutterPilot.
  ///
  /// Call once after [SharedPreferences.getInstance] resolves, before
  /// [runApp]:
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   FlutterPilot.initialize();
  ///   final prefs = await SharedPreferences.getInstance();
  ///   SharedPrefsPilotInspector.register(prefs);
  ///   runApp(const MyApp());
  /// }
  /// ```
  static void register(SharedPreferences prefs) {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] SharedPrefsPilotInspector.register called before '
        'FlutterPilot.initialize(). Extensions will not be registered.',
      );
      return;
    }
    if (_registered) return;
    _registered = true;
    _prefs = prefs;
    _registerExtensions();
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getSharedPreferences --------------------------------
    registerExtension(
      'ext.flutterpilot.getSharedPreferences',
      (method, parameters) async {
        final p = _prefs;
        if (p == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'SharedPreferences not registered.',
          );
        }
        final keys = p.getKeys();
        final data = <String, dynamic>{};
        for (final key in keys) {
          data[key] = p.get(key);
        }
        return ServiceExtensionResponse.result(
          json.encode({'prefs': data, 'count': data.length}),
        );
      },
    );

    // -- ext.flutterpilot.setSharedPreference --------------------------------
    registerExtension(
      'ext.flutterpilot.setSharedPreference',
      (method, parameters) async {
        final p = _prefs;
        if (p == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'SharedPreferences not registered.',
          );
        }
        final key = parameters['key'];
        final value = parameters['value'];
        final type = parameters['type'] ?? 'string';
        if (key == null || value == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'Missing required parameters: key, value',
          );
        }
        try {
          switch (type) {
            case 'int':
              await p.setInt(key, int.parse(value));
            case 'double':
              await p.setDouble(key, double.parse(value));
            case 'bool':
              await p.setBool(key, value.toLowerCase() == 'true');
            case 'stringList':
              final list = (json.decode(value) as List<dynamic>)
                  .cast<String>();
              await p.setStringList(key, list);
            default: // 'string'
              await p.setString(key, value);
          }
          return ServiceExtensionResponse.result(
            json.encode({'status': 'success', 'key': key, 'type': type}),
          );
        } catch (e) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'Failed to set preference: $e',
          );
        }
      },
    );

    // -- ext.flutterpilot.clearSharedPreferences ------------------------------
    registerExtension(
      'ext.flutterpilot.clearSharedPreferences',
      (method, parameters) async {
        final p = _prefs;
        if (p == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'SharedPreferences not registered.',
          );
        }
        final key = parameters['key'];
        if (key != null) {
          await p.remove(key);
          return ServiceExtensionResponse.result(
            json.encode({'status': 'success', 'removed': key}),
          );
        }
        await p.clear();
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'cleared': 'all'}),
        );
      },
    );
  }
}
