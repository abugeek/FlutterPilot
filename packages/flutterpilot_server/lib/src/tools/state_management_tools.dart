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

    _tool(
      'set_riverpod_state',
      description:
          'Inject a new state into a Riverpod provider. Use the provider name or notifier name from `get_riverpod_state`. Accepts plain values (e.g. 42, "active", true) or JSON.',
      inputSchema: ToolInputSchema(
        properties: {
          'provider': JsonSchema.string(
            description:
                'The Riverpod provider name (e.g. "counterProvider", "FeedNotifier").',
          ),
          'name': JsonSchema.string(description: 'Alias for provider.'),
          'target': JsonSchema.string(description: 'Alias for provider.'),
          'value': JsonSchema.fromJson({
            'description':
                'The new state value to inject. Can be a primitive value (int, bool, string) or JSON string.',
          }),
        },
        required: ['value'],
      ),
      callback: (p, e) async {
        // Memory-only write: allowed by default without --allow-destructive
        final provider = p['provider'] ?? p['name'] ?? p['target'];
        if (provider == null) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'Missing required parameter: provider (or target/name)',
              ),
            ],
            isError: true,
          );
        }
        final val = p['value'];
        final valueStr = val is String ? val : json.encode(val);
        final res = await _callExtensionRaw('ext.flutterpilot.setState', {
          'type': 'riverpod',
          'name': provider.toString(),
          'value': valueStr,
        });
        return res.toCallToolResult();
      },
    );

    _tool(
      'batch_set_state',
      description:
          'Atomic multi-state setter: Injects multiple state values at once (Riverpod, Bloc) in 1ms. '
          'Eliminates multi-turn LLM latency when seeding test fixtures or forms.',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(
            description:
                'State management type: "riverpod" or "bloc" (default: "riverpod").',
          ),
          'states': JsonSchema.object(
            description:
                'Map of provider/bloc names to their new values, e.g. {"counterProvider": 10, "themeProvider": "dark", "isLoggedIn": true}.',
          ),
        },
        required: ['states'],
      ),
      callback: (p, e) async {
        if (!allowDestructive) return _destructiveOperationDenied();
        final type = (p['type'] as String?) ?? 'riverpod';
        final states = p['states'];
        final res = await _callExtensionRaw('ext.flutterpilot.batchSetState', {
          'type': type,
          'states': json.encode(states),
        });
        if (res.isError) return res.toCallToolResult();
        final count = res.data?['updatedCount'] ?? 0;
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '⚡ Batch state update complete: $count state(s) updated for type "$type".',
            ),
          ],
        );
      },
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

    _tool(
      'set_bloc_state',
      description:
          'Emit a new state into a live Bloc/Cubit (in memory only). Works when '
          'the state is a bool/number/String/List/Map; for class-typed states '
          'it explains why not — drive the UI instead. Names come from get_bloc_state.',
      inputSchema: ToolInputSchema(
        properties: {
          'cubit': JsonSchema.string(
            description:
                'Name from get_bloc_state (e.g. "CounterCubit", or "CounterCubit#2" for a second instance).',
          ),
          'state': JsonSchema.fromJson({
            'description':
                'New state as a plain value or JSON, e.g. 42, true, "text", [1,2].',
          }),
        },
        required: ['cubit', 'state'],
      ),
      callback: (p, e) async {
        final val = p['state'];
        final res = await _callExtensionRaw('ext.flutterpilot.setState', {
          'type': 'bloc',
          'name': p['cubit'],
          'value': val is String ? val : json.encode(val),
        });
        return res.toCallToolResult();
      },
    );

    _registerAppTool(
      name: 'get_network_logs',
      description:
          'View recent HTTP requests and responses (bodies truncated and redacted; mock status shown). CALL THIS if an API call failed or to verify network payload accuracy.',
      extension: 'ext.flutterpilot.getNetworkLogs',
      formatResult: (json) {
        final logs = json['logs'] as List?;
        if (logs == null || logs.isEmpty) return 'No network traffic captured.';
        return logs
            .map((l) {
              final type = l['type']?.toString().toUpperCase() ?? 'LOG';
              final method = l['method'] != null ? '${l['method']} ' : '';
              final uri = l['uri'] ?? '';
              final status = l['statusCode'] != null
                  ? ' ${l['statusCode']}'
                  : '';
              final mocked = l['mocked'] == true ? ' [MOCKED]' : '';
              final msg = l['message'] != null
                  ? ' error="${l['message']}"'
                  : '';
              final body = l['body'] != null ? ' body=${l['body']}' : '';
              return '[${l['timestamp']}] $type $method$uri$status$mocked$msg$body';
            })
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

    _tool(
      'exec_sql_query',
      description:
          'Run a read-only SQL query (SELECT, WITH, PRAGMA, EXPLAIN) on the '
          'app\'s local database — Drift or sqflite, whichever is wired. Rows '
          'come back as JSON. List tables with '
          '"SELECT name FROM sqlite_master WHERE type=\'table\'".',
      inputSchema: ToolInputSchema(
        properties: {
          'sql': JsonSchema.string(description: 'SQL statement to execute.'),
          'database': JsonSchema.string(
            description:
                'Database name, only needed when the app registers several.',
          ),
        },
        required: ['sql'],
      ),
      callback: (p, e) async {
        final sql = p['sql']?.toString().trim() ?? '';
        if (!_isReadOnlySql(sql)) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'exec_sql_query is read-only: use SELECT, WITH, PRAGMA or '
                    'EXPLAIN. To change data, drive the app\'s UI.',
              ),
            ],
            isError: true,
          );
        }
        final db = (p['database'] ?? p['dbName'])?.toString();
        final args = {'sql': sql, 'dbName': ?db};

        // Use whichever plugin is wired; a real SQL error from it wins over
        // the other plugin's "not installed".
        bool absent(_ExtensionResult r) {
          final m = r.errorMessage ?? '';
          return m.contains('is not registered in the running Flutter app') ||
              m.contains('databases registered');
        }

        _ExtensionResult? res;
        for (final ext in [
          'ext.flutterpilot.queryDrift',
          'ext.flutterpilot.querySqflite',
        ]) {
          final r = await _callExtensionRaw(ext, args);
          if (!r.isError || !absent(r)) {
            res = r;
            break;
          }
        }
        if (res == null) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'No database registered. Wire one in main(): '
                    'DriftPilotInspector.registerDatabase(\'main\', db) or '
                    'SqflitePilotInspector.registerDatabase(\'main\', db).',
              ),
            ],
            isError: true,
          );
        }
        if (res.isError) return res.toCallToolResult();
        final rows = res.data?['results'] as List? ?? const [];
        final buf = StringBuffer('${rows.length} row(s)');
        if (res.data?['truncated'] == true) {
          buf.write(' (truncated from ${res.data?['total']})');
        }
        for (final row in rows.take(50)) {
          buf.write('\n${jsonEncode(row)}');
        }
        if (rows.length > 50) buf.write('\n… ${rows.length - 50} more');
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

    _tool(
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
        if (!allowDestructive) return _destructiveOperationDenied();
        final res =
            await _callExtensionRaw('ext.flutterpilot.setSharedPreference', {
              'key': p['key'].toString(),
              'value': p['value'].toString(),
              if (p['type'] != null) 'type': p['type'].toString(),
            });
        return res.toCallToolResult();
      },
    );

    _tool(
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
        if (!allowDestructive) return _destructiveOperationDenied();
        final res =
            await _callExtensionRaw('ext.flutterpilot.clearSharedPreferences', {
              if (p['key'] != null) 'key': p['key'].toString(),
              if (p['confirm'] != null) 'confirm': p['confirm'].toString(),
            });
        return res.toCallToolResult();
      },
    );

    _tool(
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

    _tool(
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

    _tool(
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

    // -- Time-Travel State Snapshots -----------------------------------------

    // -- Network Fixture Record & Replay -------------------------------------
  }
}
