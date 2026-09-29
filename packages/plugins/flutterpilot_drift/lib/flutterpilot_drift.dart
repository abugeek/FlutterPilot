import 'dart:developer';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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

/// Inspects Drift [GeneratedDatabase] instances for FlutterPilot.
///
/// Exposes `ext.flutterpilot.queryDrift` (read-only SQL) and
/// `ext.flutterpilot.listDriftTables` service extensions.
///
/// ## Setup
/// ```dart
/// final db = AppDatabase();
/// DriftPilotInspector.registerDatabase('main', db);
/// ```
class DriftPilotInspector {
  static final Map<String, GeneratedDatabase> _databases = {};
  static bool _initialized = false;
  static const int _maxResults = 1000;

  static void registerDatabase(String name, GeneratedDatabase db) {
    _databases[name] = db;
    if (!_initialized) {
      _initialized = true;
      _registerExtensions();
    }
  }

  /// Removes a previously registered database.
  static void unregister(String name) {
    _databases.remove(name);
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _databases.clear();
    _initialized = false;
  }

  /// Validates that SQL is a safe read-only statement.
  /// Validates that SQL is a safe read-only statement (FlutterPilot's
  /// shared check: prefix checks let `WITH … DELETE` through).
  static bool _isSafeReadOnly(String sql) => FlutterPilot.isReadOnlySql(sql);

  /// Exposes [_isSafeReadOnly] for unit testing.
  @visibleForTesting
  static bool isSafeReadOnlyForTest(String sql) => _isSafeReadOnly(sql);

  static void _registerExtensions() {
    FlutterPilot.registerCapability(
      'drift',
      version: '1',
      extensions: [
        'ext.flutterpilot.listDriftTables',
        'ext.flutterpilot.queryDrift',
      ],
    );
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: DriftPilotInspector registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    _safeRegisterExtension('ext.flutterpilot.queryDrift', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      final sql = parameters['sql'];
      if (sql == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing sql parameter',
        );
      }

      final resolvedDbName =
          dbName ?? (_databases.length == 1 ? _databases.keys.first : null);
      if (resolvedDbName == null) {
        if (_databases.isEmpty) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'No Drift databases registered.',
          );
        }
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Multiple Drift databases registered (${_databases.keys.join(', ')}). Specify dbName.',
        );
      }

      if (!_isSafeReadOnly(sql)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Drift queries are read-only: use SELECT, EXPLAIN, PRAGMA or WITH.',
        );
      }

      final db = _databases[resolvedDbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'DB "$resolvedDbName" not found',
        );
      }
      try {
        final results = await db.customSelect(sql).get();
        final limited = results.take(_maxResults).toList();
        final response = <String, dynamic>{
          'results': limited.map((r) => r.data).toList(),
        };
        if (results.length > _maxResults) {
          response['truncated'] = true;
          response['total'] = results.length;
        }
        return ServiceExtensionResponse.result(json.encode(response));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Query failed: $e',
        );
      }
    });

    _safeRegisterExtension('ext.flutterpilot.listDriftTables', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      final resolvedDbName =
          dbName ?? (_databases.length == 1 ? _databases.keys.first : null);
      if (resolvedDbName == null) {
        if (_databases.isEmpty) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'No Drift databases registered.',
          );
        }
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Multiple Drift databases registered (${_databases.keys.join(', ')}). Specify dbName.',
        );
      }
      final db = _databases[resolvedDbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'DB "$resolvedDbName" not found',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'tables': db.allTables.map((t) => t.actualTableName).toList(),
        }),
      );
    });
  }
}
