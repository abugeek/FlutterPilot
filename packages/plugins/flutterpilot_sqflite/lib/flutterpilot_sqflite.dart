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
/// - `exec_sql_query` with "SELECT name FROM sqlite_master" — list tables
/// - `exec_sql_query` — run a read-only SELECT/EXPLAIN/PRAGMA query
class SqflitePilotInspector {
  SqflitePilotInspector._();

  static final Map<String, Database> _databases = {};
  static bool _initialized = false;
  static const int _maxResults = 1000;

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
  /// Validates that SQL is a safe read-only statement (FlutterPilot's
  /// shared check: prefix checks let `WITH … DELETE` through).
  static bool _isSafeReadOnly(String sql) => FlutterPilot.isReadOnlySql(sql);

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
        'ext.flutterpilot.dumpSqflite',
        'ext.flutterpilot.restoreSqflite',
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
      if (sql == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: sql',
        );
      }

      final resolvedDbName =
          dbName ?? (_databases.length == 1 ? _databases.keys.first : null);
      if (resolvedDbName == null) {
        if (_databases.isEmpty) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'No sqflite databases registered.',
          );
        }
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Multiple databases registered (${_databases.keys.join(', ')}). Specify dbName.',
        );
      }

      if (!_isSafeReadOnly(sql)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Only SELECT/EXPLAIN/PRAGMA/WITH queries are allowed. '
          'Write operations are blocked for safety.',
        );
      }

      final db = _databases[resolvedDbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Database "$resolvedDbName" not found. Registered: ${_databases.keys.join(', ')}',
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
      final resolvedDbName =
          dbName ?? (_databases.length == 1 ? _databases.keys.first : null);
      if (resolvedDbName == null) {
        if (_databases.isEmpty) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'No sqflite databases registered.',
          );
        }
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Multiple databases registered (${_databases.keys.join(', ')}). Specify dbName.',
        );
      }

      final db = _databases[resolvedDbName];
      if (db == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Database "$resolvedDbName" not found. Registered: ${_databases.keys.join(', ')}',
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

    // -- ext.flutterpilot.dumpSqflite -------------------------------------------
    // Every registered database's rows, for a scenario file.
    _safeRegisterExtension('ext.flutterpilot.dumpSqflite', (
      method,
      parameters,
    ) async {
      try {
        return ServiceExtensionResponse.result(
          json.encode({
            'databases': {
              for (final MapEntry(key: name, value: db) in _databases.entries)
                name: await SqlSnapshot.dump(db.rawQuery),
            },
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Could not read the database: $e',
        );
      }
    });

    // -- ext.flutterpilot.restoreSqflite ----------------------------------------
    // data: {dbName: {tables: {name: [rows]}, sequences: {...}}}. Each
    // database is replaced in one transaction, or not at all.
    _safeRegisterExtension('ext.flutterpilot.restoreSqflite', (
      method,
      parameters,
    ) async {
      final Map<String, dynamic> data;
      try {
        data = (json.decode(parameters['data'] ?? '{}') as Map)
            .cast<String, dynamic>();
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'data is not JSON: $e',
        );
      }
      final restored = <String, Object?>{};
      final errors = <String, String>{};
      for (final MapEntry(key: name, value: snapshot) in data.entries) {
        final db = _databases[name];
        if (db == null) {
          errors[name] =
              'no sqflite database registered as "$name" '
              '(registered: ${_databases.keys.join(', ')})';
          continue;
        }
        try {
          restored[name] = await db.transaction(
            (txn) => SqlSnapshot.restore(
              ((snapshot as Map)['tables'] as Map? ?? const {})
                  .cast<String, Object?>(),
              (snapshot['sequences'] as Map? ?? const {})
                  .cast<String, Object?>(),
              select: txn.rawQuery,
              execute: txn.execute,
            ),
          );
        } catch (e) {
          errors[name] = e is StateError ? e.message : '$e';
        }
      }
      return ServiceExtensionResponse.result(
        json.encode({'restored': restored, 'errors': errors}),
      );
    });
  }
}
