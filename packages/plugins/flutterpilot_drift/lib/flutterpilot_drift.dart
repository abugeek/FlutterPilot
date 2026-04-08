import 'dart:developer';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// Allowed SQL statement prefixes for read-only mode.
const _readOnlyPrefixes = ['SELECT', 'EXPLAIN', 'PRAGMA'];

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

  static void registerDatabase(String name, GeneratedDatabase db) {
    _databases[name] = db;
    if (!_initialized) {
      _initialized = true;
      _registerExtensions();
    }
  }

  /// Validates that SQL is a safe read-only statement.
  static bool _isSafeReadOnly(String sql) {
    final trimmed = sql.trimLeft().toUpperCase();
    return _readOnlyPrefixes.any((prefix) => trimmed.startsWith(prefix));
  }

  static void _registerExtensions() {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: DriftPilotInspector registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    registerExtension('ext.flutterpilot.queryDrift', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      final sql = parameters['sql'];
      if (dbName == null || sql == null)
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing dbName/sql',
        );

      // Block destructive SQL unless the server was started with --allow-destructive.
      // The server-side check is the primary gate; this is defense-in-depth.
      if (!_isSafeReadOnly(sql)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Only SELECT/EXPLAIN/PRAGMA queries are allowed in the SDK. '
          'Start the server with --allow-destructive to enable write operations.',
        );
      }

      final db = _databases[dbName];
      if (db == null)
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'DB not found',
        );
      try {
        final results = await db.customSelect(sql).get();
        return ServiceExtensionResponse.result(
          json.encode({'results': results.map((r) => r.data).toList()}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Query error: $e',
        );
      }
    });

    registerExtension('ext.flutterpilot.listDriftTables', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      if (dbName == null)
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing dbName',
        );
      final db = _databases[dbName];
      if (db == null)
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'DB not found',
        );
      return ServiceExtensionResponse.result(
        json.encode({
          'tables': db.allTables.map((t) => t.actualTableName).toList(),
        }),
      );
    });
  }
}
