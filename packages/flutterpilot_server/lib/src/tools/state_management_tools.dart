part of '../../flutterpilot_server.dart';

/// Tools for reading and injecting state (Riverpod, Bloc, SharedPreferences,
/// Hive, Drift), and for simulating/mocking network conditions.
mixin _StateManagementToolsMixin on _FlutterPilotServerBase {
  /// Returns `true` when [sql] is a read-only SQL statement safe for
  /// untrusted execution against the app's Drift database.
  static bool _isReadOnlySql(String sql) {
    final normalized = sql.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    // Strip SQL comments before validation
    final stripped = normalized
        .replaceAll(RegExp(r'--.*$', multiLine: true), '')
        .replaceAll(RegExp(r'/\*.*?\*/'), '')
        .trim();
    if (stripped.isEmpty) return false;
    // Block multi-statement
    if (stripped.contains(';') && stripped.indexOf(';') < stripped.length - 1) {
      return false;
    }
    // Block SELECT INTO
    if (stripped.contains('SELECT') && stripped.contains(' INTO ')) {
      return false;
    }
    // Block dangerous PRAGMAs
    for (final pragma in _Constants.dangerousPragmas) {
      if (stripped.startsWith(pragma)) return false;
    }
    // Must start with allowed prefix
    return _Constants.allowedSqlPrefixes.any((p) => stripped.startsWith(p));
  }

  void _registerStateManagementTools() {
    _registerAppTool(
      name: 'get_riverpod_state',
      description:
          'Inspect current values of all active Riverpod providers. '
          'Returns provider name, current value (as string), value type, and timestamp. '
          'PREREQUISITES: App must use flutterpilot_riverpod plugin with RiverpodPilotObserver. '
          'Use get_capabilities first to check if the riverpod plugin is loaded. '
          'COMMON ERRORS: Empty result means no providers are active or plugin is not registered.',
      extension: 'ext.flutterpilot.getRiverpodStates',
      formatResult: (json) {
        final states = json['states'] as Map?;
        if (states == null || states.isEmpty) {
          return 'No observed Riverpod providers. Ensure RiverpodPilotObserver is registered.';
        }
        return states.entries
            .map((e) => '${e.key}: ${e.value['value']} (${e.value['type']})')
            .join('\n');
      },
    );

    server.registerTool(
      'set_riverpod_state',
      description:
          'Inject a new state into a Riverpod provider. Use the provider name (type) from `get_riverpod_state`. The `value` should be a JSON-compatible string (e.g. "42", "true", "\\"hello\\"").',
      inputSchema: ToolInputSchema(
        properties: {
          'provider': JsonSchema.string(
            description:
                'The Riverpod provider name as registered with FlutterPilot.registerStateSetter (e.g. "counterProvider").',
          ),
          'value': JsonSchema.string(
            description:
                'The new state value to inject. Use JSON-serializable types. Complex objects should be JSON strings.',
          ),
        },
        required: ['provider', 'value'],
      ),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setState', {
        'type': 'riverpod',
        'name': p['provider'],
        'value': p['value'],
      }).then((res) => res.toCallToolResult()),
    );

    _registerAppTool(
      name: 'get_bloc_state',
      description:
          'Inspect the current states of all active Blocs and Cubits. CALL THIS to verify business logic transitions.',
      extension: 'ext.flutterpilot.getBlocStates',
      formatResult: (json) {
        final states = json['states'] as Map?;
        if (states == null || states.isEmpty) {
          return 'No observed Blocs. Ensure BlocPilotObserver is registered.';
        }
        return states.entries
            .map((e) => '${e.key}: ${e.value['state']} (${e.value['type']})')
            .join('\n');
      },
    );

    server.registerTool(
      'set_bloc_state',
      description:
          'Force a new state into a Bloc or Cubit. Use the Bloc/Cubit class name from `get_bloc_state`. The `state` should be a JSON string (e.g. "42", "true").',
      inputSchema: ToolInputSchema(
        properties: {
          'cubit': JsonSchema.string(
            description:
                'The Bloc/Cubit class name as registered (e.g. "CounterCubit", "AuthBloc").',
          ),
          'state': JsonSchema.string(
            description:
                'The new state value to inject. Use JSON-serializable representation.',
          ),
        },
        required: ['cubit', 'state'],
      ),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setState', {
        'type': 'bloc',
        'name': p['cubit'],
        'value': p['state'],
      }).then((res) => res.toCallToolResult()),
    );

    _registerAppTool(
      name: 'get_network_logs',
      description:
          'View the last 50 HTTP requests and responses. CALL THIS if an API call failed or to verify network payload accuracy.',
      extension: 'ext.flutterpilot.getNetworkLogs',
      formatResult: (json) {
        final logs = json['logs'] as List?;
        if (logs == null || logs.isEmpty) return 'No network traffic captured.';
        return logs
            .map(
              (l) =>
                  '[${l['timestamp']}] ${l['type'].toUpperCase()} ${l['method'] ?? ''} ${l['uri']} ${l['statusCode'] ?? ''}',
            )
            .join('\n');
      },
    );

    _registerAppTool(
      name: 'get_hive_contents',
      description:
          'Dump the contents of all registered Hive boxes. CALL THIS to verify local persistent storage.',
      extension: 'ext.flutterpilot.getHiveContents',
    );

    _registerAppTool(
      name: 'list_drift_tables',
      description: 'List all tables in the SQLite (Drift) database.',
      extension: 'ext.flutterpilot.listDriftTables',
      properties: {
        'dbName': JsonSchema.string(
          description: 'The Drift database name registered via FlutterPilot.',
        ),
      },
    );

    server.registerTool(
      'query_drift',
      description:
          'Execute a raw SQL SELECT query on the local database. CALL THIS to verify complex data relationships or transaction history.',
      inputSchema: ToolInputSchema(
        properties: {
          'dbName': JsonSchema.string(
            description: 'The Drift database name registered via FlutterPilot.',
          ),
          'sql': JsonSchema.string(
            description:
                'A SQL SELECT, EXPLAIN, or WITH query. Write-operations (INSERT/UPDATE/DELETE) are blocked.',
          ),
        },
        required: ['dbName', 'sql'],
      ),
      callback: (params, extra) async {
        final sqlParam = params['sql'] as String?;
        if (sqlParam == null || sqlParam.trim().isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'sql parameter is required')],
            isError: true,
          );
        }
        final sql = sqlParam.trim();
        if (!allowDestructive && !_isReadOnlySql(sql)) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Security: Only SELECT/EXPLAIN/PRAGMA/WITH queries are allowed. Start server with --allow-destructive to enable write operations.',
              ),
            ],
            isError: true,
          );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.queryDrift',
          params,
        );
        if (res.isError) return res.toCallToolResult();
        final results = res.data?['results'] ?? 'No results returned';
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Results:\n$results\n\nHINT: If data is missing, check get_network_logs to see if the last sync failed.',
            ),
          ],
        );
      },
    );

    // =========================================================================
    // sqflite
    // =========================================================================

    _registerAppTool(
      name: 'list_sqflite_databases',
      description:
          'List all sqflite databases registered with FlutterPilot. '
          'PREREQUISITES: App must use flutterpilot_sqflite plugin.',
      extension: 'ext.flutterpilot.listSqfliteDatabases',
      formatResult: (json) {
        final dbs = json['databases'] as List? ?? [];
        if (dbs.isEmpty) return 'No sqflite databases registered.';
        return 'Registered databases: ${dbs.join(', ')}';
      },
    );

    _registerAppTool(
      name: 'list_sqflite_tables',
      description:
          'List all tables in a sqflite database. '
          'PREREQUISITES: App must use flutterpilot_sqflite plugin.',
      extension: 'ext.flutterpilot.listSqfliteTables',
      properties: {
        'dbName': JsonSchema.string(
          description: 'The sqflite database name registered via FlutterPilot.',
        ),
      },
      formatResult: (json) {
        final dbName = json['dbName'] ?? '?';
        final tables = json['tables'] as List? ?? [];
        if (tables.isEmpty) return 'Database "$dbName": no tables found.';
        return 'Database "$dbName" tables: ${tables.join(', ')}';
      },
    );

    server.registerTool(
      'query_sqflite',
      description:
          'Execute a read-only SQL SELECT query on a sqflite database. '
          'Only SELECT/EXPLAIN/PRAGMA/WITH are allowed — write operations are blocked. '
          'PREREQUISITES: App must use flutterpilot_sqflite plugin.',
      inputSchema: ToolInputSchema(
        properties: {
          'dbName': JsonSchema.string(
            description: 'The sqflite database name registered via FlutterPilot.',
          ),
          'sql': JsonSchema.string(
            description:
                'A read-only SQL query (SELECT, EXPLAIN, PRAGMA, WITH). Write operations are blocked.',
          ),
        },
        required: ['dbName', 'sql'],
      ),
      callback: (params, extra) async {
        final sqlParam = params['sql'] as String?;
        if (sqlParam == null || sqlParam.trim().isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'sql parameter is required')],
            isError: true,
          );
        }
        final sql = sqlParam.trim();
        if (!allowDestructive && !_isReadOnlySql(sql)) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Security: Only SELECT/EXPLAIN/PRAGMA/WITH queries are allowed.',
              ),
            ],
            isError: true,
          );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.querySqflite',
          params,
        );
        if (res.isError) return res.toCallToolResult();
        final results = res.data?['results'] ?? 'No results returned';
        final rowCount = res.data?['rowCount'] ?? 0;
        final truncated = res.data?['truncated'] == true;
        final buf = StringBuffer('$rowCount row(s)\n');
        if (results is List) {
          for (final row in results.take(50)) {
            buf.writeln('  $row');
          }
          if (truncated) buf.writeln('  (results truncated)');
        }
        return CallToolResult(content: [TextContent(text: buf.toString())]);
      },
    );

    _registerAppTool(
      name: 'get_shared_preferences',
      description:
          'Returns all SharedPreferences keys and their typed values '
          '(String, int, double, bool, List<String>). Values matching '
          'sensitive key patterns (token, password, secret, auth, etc.) are '
          'redacted by default — pass showSensitive=true to reveal them. '
          'Requires the flutterpilot_shared_preferences plugin.',
      extension: 'ext.flutterpilot.getSharedPreferences',
      properties: {
        'showSensitive': JsonSchema.string(
          description:
              'Set to "true" to reveal values for sensitive-looking keys. Default: redacted.',
        ),
      },
    );

    server.registerTool(
      'set_shared_preference',
      description:
          'Writes a key-value pair to SharedPreferences. '
          'Specify type as: string (default), int, double, bool, or '
          'stringList (JSON array, e.g. \'["a","b"]\').',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The SharedPreferences key to set.',
          ),
          'value': JsonSchema.string(
            description:
                'The value to set as a string. Booleans: "true"/"false". Numbers: numeric string.',
          ),
          'type': JsonSchema.string(
            description:
                'Value type: "string", "bool", "int", "double", or "stringList" (comma-separated).',
          ),
        },
        required: ['key', 'value'],
      ),
      callback: (p, e) async {
        final res =
            await _callExtensionRaw('ext.flutterpilot.setSharedPreference', {
              'key': p['key'].toString(),
              'value': p['value'].toString(),
              if (p['type'] != null) 'type': p['type'].toString(),
            });
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'clear_shared_preferences',
      description:
          '⚠ DESTRUCTIVE — Removes SharedPreferences entries. '
          'If key is specified, only that key is removed. '
          'To clear ALL preferences, omit key and pass confirm="CLEAR_ALL". '
          'Cannot be undone.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The specific key to remove. Omit to clear ALL preferences (requires confirm).',
          ),
          'confirm': JsonSchema.string(
            description:
                'Required when clearing all keys (no "key" given). Must be "CLEAR_ALL".',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.clearSharedPreferences',
          {
            if (p['key'] != null) 'key': p['key'].toString(),
            if (p['confirm'] != null) 'confirm': p['confirm'].toString(),
          },
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'simulate_network',
      description:
          'Simulates a network condition for all Dio HTTP requests. Use to test offline states, loading skeletons, and slow-connection UX. Conditions: normal | slow_3g | fast_4g | offline.',
      inputSchema: ToolInputSchema(
        properties: {
          'condition': JsonSchema.string(
            enumValues: ['normal', 'slow_3g', 'fast_4g', 'offline'],
          ),
        },
        required: ['condition'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.simulateNetwork',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'mock_http_response',
      description:
          'Registers a URL pattern mock so that any Dio request whose URL contains '
          'urlPattern returns a synthetic response instead of hitting the network. '
          'Use to test error states, empty states, or edge-case API responses. '
          'Call clear_http_mocks to remove mocks when done.',
      inputSchema: ToolInputSchema(
        properties: {
          'urlPattern': JsonSchema.string(
            description: 'Substring of the URL to match (e.g. "/api/users")',
          ),
          'statusCode': JsonSchema.integer(
            description: 'HTTP status code (e.g. 200, 404, 500)',
          ),
          'body': JsonSchema.string(
            description:
                'Response body as a JSON string (e.g. \'{"error":"not found"}\')',
          ),
          'delayMs': JsonSchema.integer(
            description:
                'Artificial delay in milliseconds before returning the mock (default 0)',
          ),
        },
        required: ['urlPattern', 'statusCode', 'body'],
      ),
      callback: (p, e) {
        final mapped = {
          'urlPattern': p['urlPattern']?.toString(),
          'statusCode': p['statusCode']?.toString(),
          'body': p['body']?.toString(),
          if (p['delayMs'] != null) 'delayMs': p['delayMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.addHttpMock',
          mapped,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'clear_http_mocks',
      description:
          'Removes a specific URL pattern mock, or all mocks if urlPattern is omitted. '
          'Always call this after testing a mocked flow to restore real network behaviour.',
      inputSchema: ToolInputSchema(
        properties: {
          'urlPattern': JsonSchema.string(
            description: 'Pattern to remove. Omit to clear ALL mocks.',
          ),
        },
      ),
      callback: (p, e) {
        final mapped = <String, String?>{
          if (p['urlPattern'] != null) 'urlPattern': p['urlPattern'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.clearHttpMocks',
          mapped,
        ).then((res) => res.toCallToolResult());
      },
    );
  }
}
