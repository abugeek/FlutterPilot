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

  static const Set<String> _validTypes = {
    'string',
    'int',
    'double',
    'bool',
    'stringList',
  };

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
    registerExtension('ext.flutterpilot.getSharedPreferences', (
      method,
      parameters,
    ) async {
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
    });

    // -- ext.flutterpilot.setSharedPreference --------------------------------
    registerExtension('ext.flutterpilot.setSharedPreference', (
      method,
      parameters,
    ) async {
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
      if (key.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          json.encode({'error': 'Key must not be empty'}),
        );
      }
      if (!_validTypes.contains(type)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          json.encode({
            'error':
                'Invalid type "$type". Must be one of: ${_validTypes.join(', ')}',
          }),
        );
      }
      try {
        switch (type) {
          case 'int':
            final parsed = int.tryParse(value);
            if (parsed == null) {
              return ServiceExtensionResponse.error(
                ServiceExtensionResponse.extensionError,
                json.encode({'error': 'Invalid integer: "$value"'}),
              );
            }
            await p.setInt(key, parsed);
          case 'double':
            final parsed = double.tryParse(value);
            if (parsed == null) {
              return ServiceExtensionResponse.error(
                ServiceExtensionResponse.extensionError,
                json.encode({'error': 'Invalid double: "$value"'}),
              );
            }
            await p.setDouble(key, parsed);
          case 'bool':
            final lower = value.toLowerCase().trim();
            if (lower != 'true' && lower != 'false') {
              return ServiceExtensionResponse.error(
                ServiceExtensionResponse.extensionError,
                json.encode({
                  'error':
                      'Boolean value must be "true" or "false", got: "$value"',
                }),
              );
            }
            await p.setBool(key, lower == 'true');
          case 'stringList':
            final List<String> list;
            try {
              final decoded = json.decode(value);
              if (decoded is! List) {
                return ServiceExtensionResponse.error(
                  ServiceExtensionResponse.extensionError,
                  json.encode({
                    'error':
                        'Invalid stringList value. Expected a JSON array, e.g. \'["a","b"]\'',
                  }),
                );
              }
              list = decoded.map((item) {
                if (item is! String) {
                  throw FormatException(
                    'Expected string in array, got ${item.runtimeType}',
                  );
                }
                return item;
              }).toList();
            } on FormatException catch (e) {
              return ServiceExtensionResponse.error(
                ServiceExtensionResponse.extensionError,
                json.encode({
                  'error':
                      'Invalid JSON for stringList: ${e.message}. Expected a JSON array of strings, e.g. \'["a","b"]\'',
                }),
              );
            }
            await p.setStringList(key, list);
          default:
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
    });

    // -- ext.flutterpilot.clearSharedPreferences ------------------------------
    registerExtension('ext.flutterpilot.clearSharedPreferences', (
      method,
      parameters,
    ) async {
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
    });
  }
}
