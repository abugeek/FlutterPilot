import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// FlutterPilot plugin that exposes [FlutterSecureStorage] to AI agents.
///
/// Provides visibility into:
/// - **List keys**: enumerate stored keys (values redacted by default)
/// - **Read key**: read a specific key's value (opt-in, redacted by default)
/// - **Write key**: set a key-value pair for testing
/// - **Delete key**: remove a key or clear all storage
///
/// ## Security
/// Values are **redacted by default**. Pass `showValues: true` to reveal them.
/// This prevents accidental exposure of tokens, passwords, and API keys.
///
/// ## Setup
/// ```dart
/// const storage = FlutterSecureStorage();
/// SecureStoragePilotInspector.register(storage);
/// ```
class SecureStoragePilotInspector {
  SecureStoragePilotInspector._();

  static bool _registered = false;
  static FlutterSecureStorage? _storage;

  /// Sensitive key patterns that trigger automatic redaction even when
  /// `showValues` is true. Override via [register]'s `alwaysRedactPatterns`.
  static Set<String> _alwaysRedactPatterns = {
    'password',
    'secret',
    'private_key',
    'api_key',
    'apikey',
  };

  /// Registers a [FlutterSecureStorage] instance with FlutterPilot.
  ///
  /// ```dart
  /// const storage = FlutterSecureStorage();
  /// SecureStoragePilotInspector.register(storage);
  /// ```
  ///
  /// [alwaysRedactPatterns] — key substrings that are always redacted,
  /// even when `showValues: true`. Defaults to password/secret/key patterns.
  static void register(
    FlutterSecureStorage storage, {
    Set<String>? alwaysRedactPatterns,
  }) {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] SecureStoragePilotInspector.register called before '
        'FlutterPilot.initialize(). Extensions will not be registered.',
      );
      return;
    }
    if (_registered) return;
    _registered = true;
    _storage = storage;
    if (alwaysRedactPatterns != null) {
      _alwaysRedactPatterns = alwaysRedactPatterns;
    }
    _registerExtensions();
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _storage = null;
    _registered = false;
    _alwaysRedactPatterns = {
      'password',
      'secret',
      'private_key',
      'api_key',
      'apikey',
    };
  }

  /// Returns `true` if [key] matches any always-redact pattern.
  static bool _isAlwaysRedacted(String key) {
    final lower = key.toLowerCase();
    return _alwaysRedactPatterns.any((p) => lower.contains(p));
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getSecureStorageKeys ---------------------------------
    registerExtension('ext.flutterpilot.getSecureStorageKeys', (
      method,
      parameters,
    ) async {
      final storage = _storage;
      if (storage == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FlutterSecureStorage not registered.',
        );
      }

      try {
        final all = await storage.readAll();
        final showValues = parameters['showValues'] == 'true';

        final entries = <String, dynamic>{};
        for (final entry in all.entries) {
          if (!showValues || _isAlwaysRedacted(entry.key)) {
            entries[entry.key] = {
              'hasValue': entry.value.isNotEmpty,
              'length': entry.value.length,
              'redacted': true,
            };
          } else {
            entries[entry.key] = {
              'value': entry.value,
              'length': entry.value.length,
              'redacted': false,
            };
          }
        }

        return ServiceExtensionResponse.result(json.encode({
          'keys': entries,
          'count': entries.length,
          'showValues': showValues,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to read secure storage: $e',
        );
      }
    });

    // -- ext.flutterpilot.readSecureStorageKey ---------------------------------
    registerExtension('ext.flutterpilot.readSecureStorageKey', (
      method,
      parameters,
    ) async {
      final storage = _storage;
      if (storage == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FlutterSecureStorage not registered.',
        );
      }

      final key = parameters['key'];
      if (key == null || key.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing "key" parameter.',
        );
      }

      try {
        final value = await storage.read(key: key);
        if (value == null) {
          return ServiceExtensionResponse.result(json.encode({
            'key': key,
            'exists': false,
          }));
        }

        if (_isAlwaysRedacted(key)) {
          return ServiceExtensionResponse.result(json.encode({
            'key': key,
            'exists': true,
            'redacted': true,
            'reason': 'Key matches always-redact pattern.',
            'length': value.length,
          }));
        }

        return ServiceExtensionResponse.result(json.encode({
          'key': key,
          'exists': true,
          'value': value,
          'length': value.length,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to read key "$key": $e',
        );
      }
    });

    // -- ext.flutterpilot.setSecureStorageKey ----------------------------------
    registerExtension('ext.flutterpilot.setSecureStorageKey', (
      method,
      parameters,
    ) async {
      final storage = _storage;
      if (storage == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FlutterSecureStorage not registered.',
        );
      }

      final key = parameters['key'];
      final value = parameters['value'];
      if (key == null || key.isEmpty || value == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing "key" or "value" parameter.',
        );
      }

      try {
        await storage.write(key: key, value: value);
        return ServiceExtensionResponse.result(json.encode({
          'status': 'success',
          'key': key,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to write key "$key": $e',
        );
      }
    });

    // -- ext.flutterpilot.deleteSecureStorageKey --------------------------------
    registerExtension('ext.flutterpilot.deleteSecureStorageKey', (
      method,
      parameters,
    ) async {
      final storage = _storage;
      if (storage == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FlutterSecureStorage not registered.',
        );
      }

      final key = parameters['key'];
      try {
        if (key != null && key.isNotEmpty) {
          await storage.delete(key: key);
          return ServiceExtensionResponse.result(json.encode({
            'status': 'success',
            'deleted': key,
          }));
        } else {
          await storage.deleteAll();
          return ServiceExtensionResponse.result(json.encode({
            'status': 'success',
            'deleted': 'all',
          }));
        }
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to delete: $e',
        );
      }
    });
  }
}
