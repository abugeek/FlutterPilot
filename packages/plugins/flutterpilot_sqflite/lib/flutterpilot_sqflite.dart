import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:sqflite/sqflite.dart';

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

/// FlutterPilot plugin that exposes sqflite [Database] instances to AI agents.
///
/// Provides read-only SQL access and table listing for any number of sqflite
/// databases registered by name. Write queries are blocked at the SDK level.
///
/// ## Setup
/// ```dart
/// final db = await openDatabase('my_app.db');
/// SqflitePilotInspector.registerDatabase('main', db);
/// ```
///
/// ## What AI agents can do
/// - `list_sqflite_tables` — list all tables in a named database
/// - `query_sqflite` — run a read-only SELECT/EXPLAIN/PRAGMA query
class SqflitePilotInspector {
  SqflitePilotInspector._();

  static final Map<String, Database> _databases = {};
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

  /// Registers a sqflite [Database] with FlutterPilot under [name].
  ///
  /// Call after [openDatabase] resolves:
  /// ```dart
  /// final db = await openDatabase('my_app.db');
  /// SqflitePilotInspector.registerDatabase('main', db);
  /// ```
  static void registerDatabase(String name, Database db) {
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

  /// Returns names of all registered databases.
  static List<String> get registeredDatabases => _databases.keys.toList();

  /// Validates that SQL is a safe read-only statement.
  static bool _isSafeReadOnly(String sql) {
    var cleaned = sql.replaceAll(RegExp(r'--[^\n]*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final normalized = cleaned
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
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
    FlutterPilot.registerCapability(
      'sqflite',
      version: '1',
      extensions: [
        'ext.flutterpilot.listSqfliteDatabases',
        'ext.flutterpilot.listSqfliteTables',
        'ext.flutterpilot.querySqflite',
      ],
    );
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: SqflitePilotInspector registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    // -- ext.flutterpilot.querySqflite ------------------------------------------
    _safeRegisterExtension('ext.flutterpilot.querySqflite', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      final sql = parameters['sql'];
      if (dbName == null || sql == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameters: dbName, sql',
        );
      }

      if (!_isSafeReadOnly(sql)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Only SELECT/EXPLAIN/PRAGMA/WITH queries are allowed. '
          'Write operations are blocked for safety.',
        );
      }

      final db = _databases[dbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Database "$dbName" not found. Registered: ${_databases.keys.join(', ')}',
        );
      }

      try {
        final results = await db.rawQuery(sql);
        final limited = results.take(_maxResults).toList();
        final response = <String, dynamic>{
          'results': limited,
          'rowCount': limited.length,
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

    // -- ext.flutterpilot.listSqfliteTables -------------------------------------
    _safeRegisterExtension('ext.flutterpilot.listSqfliteTables', (
      method,
      parameters,
    ) async {
      final dbName = parameters['dbName'];
      if (dbName == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: dbName',
        );
      }

      final db = _databases[dbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Database "$dbName" not found. Registered: ${_databases.keys.join(', ')}',
        );
      }

      try {
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        );
        return ServiceExtensionResponse.result(
          json.encode({
            'dbName': dbName,
            'tables': tables.map((r) => r['name']).toList(),
            'tableCount': tables.length,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to list tables: $e',
        );
      }
    });

    // -- ext.flutterpilot.listSqfliteDatabases ----------------------------------
    _safeRegisterExtension('ext.flutterpilot.listSqfliteDatabases', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'databases': _databases.keys.toList(),
          'count': _databases.length,
        }),
      );
    });
  }
}
