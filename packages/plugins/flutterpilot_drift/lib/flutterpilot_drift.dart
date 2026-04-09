import 'dart:developer';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

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

  static const Set<String> _allowedPrefixes = {
    'SELECT',
    'EXPLAIN',
    'PRAGMA',
    'WITH',
  };
  static const Set<String> _dangerousPragmas = {
    'PRAGMA JOURNAL_MODE',
    'PRAGMA WAL',
    'PRAGMA SYNCHRONOUS',
    'PRAGMA FOREIGN_KEYS',
    'PRAGMA WRITABLE_SCHEMA',
  };

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

  /// Validates that SQL is a safe read-only statement.
  static bool _isSafeReadOnly(String sql) {
    // Strip SQL comments before validation to prevent comment-based injection
    var cleaned = sql.replaceAll(RegExp(r'--[^\n]*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final normalized =
        cleaned.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    if (normalized.isEmpty) return false;
    // Block multi-statement injection
    if (normalized.contains(';') &&
        normalized.indexOf(';') < normalized.length - 1) {
      return false;
    }
    // Block SELECT INTO
    if (normalized.contains('SELECT') && normalized.contains(' INTO ')) {
      return false;
    }
    // Block dangerous PRAGMAs
    for (final p in _dangerousPragmas) {
      if (normalized.startsWith(p)) return false;
    }
    return _allowedPrefixes.any((p) => normalized.startsWith(p));
  }

  /// Exposes [_isSafeReadOnly] for unit testing.
  @visibleForTesting
  static bool isSafeReadOnlyForTest(String sql) => _isSafeReadOnly(sql);

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
      if (dbName == null || sql == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing dbName/sql',
        );
      }

      if (!_isSafeReadOnly(sql)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Only SELECT/EXPLAIN/PRAGMA/WITH queries are allowed in the SDK. '
          'Start the server with --allow-destructive to enable write operations.',
        );
      }

      final db = _databases[dbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'DB not found',
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
          'Query execution failed. Check SQL syntax.',
        );
      }
    });

    registerExtension('ext.flutterpilot.listDriftTables', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      if (dbName == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing dbName',
        );
      }
      final db = _databases[dbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'DB not found',
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
