import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    FlutterPilot.registerCapability(
      'secure_storage',
      version: '1',
      extensions: [
        'ext.flutterpilot.getSecureStorageKeys',
        'ext.flutterpilot.readSecureStorageKey',
        'ext.flutterpilot.setSecureStorageKey',
        'ext.flutterpilot.deleteSecureStorageKey',
      ],
      mutating: true,
    );
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
    _safeRegisterExtension('ext.flutterpilot.getSecureStorageKeys', (
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
        final keysOnly = parameters['keysOnly'] == 'true';
        final exactKey = parameters['key'];
        final truncateLength = int.tryParse(parameters['truncateLength'] ?? '150') ?? 150;

        if (keysOnly) {
          return ServiceExtensionResponse.result(
            json.encode({
              'keys': all.keys.toList(),
              'count': all.length,
            }),
          );
        }

        final entries = <String, dynamic>{};
        final targetEntries = exactKey != null && exactKey.isNotEmpty
            ? all.entries.where((e) => e.key == exactKey)
            : all.entries;

        for (final entry in targetEntries) {
          if (!showValues || _isAlwaysRedacted(entry.key)) {
            entries[entry.key] = {
              'hasValue': entry.value.isNotEmpty,
              'length': entry.value.length,
              'redacted': true,
            };
          } else {
            final val = entry.value;
            final isTruncated = exactKey == null && val.length > truncateLength;
            entries[entry.key] = {
              'value': isTruncated ? '${val.substring(0, truncateLength)}... [truncated]' : val,
              'length': val.length,
              'redacted': false,
              if (isTruncated) 'truncated': true,
            };
          }
        }

        return ServiceExtensionResponse.result(
          json.encode({
            'keys': entries,
            'count': entries.length,
            'showValues': showValues,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to read secure storage: $e',
        );
      }
    });

    // -- ext.flutterpilot.readSecureStorageKey ---------------------------------
    _safeRegisterExtension('ext.flutterpilot.readSecureStorageKey', (
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
          return ServiceExtensionResponse.result(
            json.encode({'key': key, 'exists': false}),
          );
        }

        if (_isAlwaysRedacted(key)) {
          return ServiceExtensionResponse.result(
            json.encode({
              'key': key,
              'exists': true,
              'redacted': true,
              'reason': 'Key matches always-redact pattern.',
              'length': value.length,
            }),
          );
        }

        return ServiceExtensionResponse.result(
          json.encode({
            'key': key,
            'exists': true,
            'value': value,
            'length': value.length,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to read key "$key": $e',
        );
      }
    });

    // -- ext.flutterpilot.setSecureStorageKey ----------------------------------
    _safeRegisterExtension('ext.flutterpilot.setSecureStorageKey', (
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
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'key': key}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to write key "$key": $e',
        );
      }
    });

    // -- ext.flutterpilot.deleteSecureStorageKey --------------------------------
    _safeRegisterExtension('ext.flutterpilot.deleteSecureStorageKey', (
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
      final confirm = parameters['confirm'];
      try {
        if (key != null && key.isNotEmpty) {
          await storage.delete(key: key);
          return ServiceExtensionResponse.result(
            json.encode({'status': 'success', 'deleted': key}),
          );
        } else {
          // Require explicit confirmation to wipe all storage
          if (confirm != 'DELETE_ALL') {
            return ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError,
              'Wiping ALL secure storage requires confirm="DELETE_ALL". '
              'This is a destructive operation that cannot be undone.',
            );
          }
          await storage.deleteAll();
          return ServiceExtensionResponse.result(
            json.encode({'status': 'success', 'deleted': 'all'}),
          );
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
