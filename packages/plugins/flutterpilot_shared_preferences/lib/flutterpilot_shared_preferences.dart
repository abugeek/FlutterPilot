import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void _safeRegisterExtension(
  String method,
  Future<ServiceExtensionResponse> Function(String, Map<String, String>)
  handler,
) {
  try {
    registerExtension(method, handler);
  } on ArgumentError {
    // Already registered — safe to ignore during re-initialization.
  }
}

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
///
/// ## Security
/// Values whose keys match common sensitive patterns (token, password, secret,
/// api_key, etc.) are **redacted by default**. Pass `showSensitive=true` to
/// the `get_shared_preferences` tool to reveal them.
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

  /// Key substrings that trigger automatic redaction of the stored value.
  static const Set<String> _sensitivePatterns = {
    'token',
    'password',
    'secret',
    'api_key',
    'apikey',
    'private_key',
    'auth',
    'credential',
    'session',
    'refresh',
    'access_key',
  };

  static bool _isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    return _sensitivePatterns.any(lower.contains);
  }

  /// The set of key substrings that trigger automatic value redaction.
  /// Exposed for testing.
  @visibleForTesting
  static const Set<String> sensitivePatterns = _sensitivePatterns;

  /// Returns true if [key] matches a sensitive pattern and would be redacted.
  /// Exposed for testing.
  @visibleForTesting
  static bool isSensitiveKey(String key) => _isSensitiveKey(key);

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

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _prefs = null;
    _registered = false;
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getSharedPreferences --------------------------------
    _safeRegisterExtension('ext.flutterpilot.getSharedPreferences', (
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
      final showSensitive = parameters['showSensitive'] == 'true';
      final keysOnly = parameters['keysOnly'] == 'true';
      final exactKey = parameters['key'];
      final truncateLength = int.tryParse(parameters['truncateLength'] ?? '200') ?? 200;

      final keys = p.getKeys();
      if (keysOnly) {
        return ServiceExtensionResponse.result(
          json.encode({'keys': keys.toList(), 'count': keys.length}),
        );
      }

      final data = <String, dynamic>{};
      final targetKeys = exactKey != null && exactKey.isNotEmpty ? [exactKey] : keys;

      for (final key in targetKeys) {
        if (!p.containsKey(key)) continue;
        if (!showSensitive && _isSensitiveKey(key)) {
          data[key] = '[redacted — pass showSensitive=true to reveal]';
        } else {
          final val = p.get(key);
          if (exactKey == null && val is String && val.length > truncateLength) {
            data[key] = '${val.substring(0, truncateLength)}... [truncated ${val.length} chars, pass key="$key" for full value]';
          } else {
            data[key] = val;
          }
        }
      }
      return ServiceExtensionResponse.result(
        json.encode({'prefs': data, 'count': data.length}),
      );
    });

    // -- ext.flutterpilot.setSharedPreference --------------------------------
    _safeRegisterExtension('ext.flutterpilot.setSharedPreference', (
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
    _safeRegisterExtension('ext.flutterpilot.clearSharedPreferences', (
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
      if (key != null && key.isNotEmpty) {
        await p.remove(key);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'removed': key}),
        );
      }
      // Require explicit confirmation to wipe all preferences
      final confirm = parameters['confirm'];
      if (confirm != 'CLEAR_ALL') {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Clearing ALL SharedPreferences requires confirm="CLEAR_ALL". '
          'This is a destructive operation that cannot be undone.',
        );
      }
      await p.clear();
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'cleared': 'all'}),
      );
    });
  }
}
