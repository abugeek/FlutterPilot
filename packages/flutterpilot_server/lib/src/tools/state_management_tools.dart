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

  /// A list provider prints every element; its first 200 chars say enough.
  static String _clip(String value) => value.length <= 200
      ? value
      : '${value.substring(0, 200)}… (${value.length} chars)';

  void _registerStateManagementTools() {
    _tool(
      'get_state',
      description:
          'Current values of the app\'s Riverpod providers and Blocs/Cubits '
          '(name: value (type)), as their plugins observe them. type limits '
          'it to one of the two.',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(enumValues: ['riverpod', 'bloc']),
        },
      ),
      callback: (p, e) async {
        final sections = <String>[];
        String? lastError;
        for (final (type, ext, valueKey) in [
          ('riverpod', 'ext.flutterpilot.getRiverpodStates', 'value'),
          ('bloc', 'ext.flutterpilot.getBlocStates', 'state'),
        ]) {
          if (p['type'] != null && p['type'] != type) continue;
          final res = await _callExtensionRaw(ext, {});
          if (res.isError) {
            lastError = res.errorMessage;
            continue;
          }
          final states = res.data?['states'] as Map?;
          sections.add(
            states == null || states.isEmpty
                ? '$type: nothing observed yet.'
                : '$type:\n${states.entries.map((e) => '  ${e.key}: ${_clip('${e.value[valueKey]}')} (${e.value['type']})').join('\n')}',
          );
        }
        if (sections.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    lastError ??
                    'Neither the Riverpod nor the Bloc plugin is registered.',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: FlutterPilotServer._boundToolText(sections.join('\n')),
            ),
          ],
        );
      },
    );

    _tool(
      'set_state',
      description:
          'Sets a Riverpod provider or Bloc/Cubit state in memory: name + '
          'value, or several at once with states. Names come from get_state; '
          'type is inferred. Works for bool/number/String/List/Map states; '
          'for class-typed states it explains why not — drive the UI instead.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description:
                'Provider or bloc name from get_state (e.g. "counterProvider", "CounterCubit#2").',
          ),
          'value': JsonSchema.fromJson({
            'description': 'New value: plain (42, true, "text") or JSON.',
          }),
          'states': JsonSchema.object(
            description:
                'Several at once: {"counterProvider": 10, "themeProvider": "dark"}.',
          ),
          'type': JsonSchema.string(
            enumValues: ['riverpod', 'bloc'],
            description: 'Only needed if the name is not observed yet.',
          ),
        },
      ),
      callback: (p, e) async {
        String encode(Object? v) => v is String ? v : json.encode(v);
        final states = p['states'];
        if (states is Map && states.isNotEmpty) {
          final type =
              p['type']?.toString() ??
              await _stateTypeOf(states.keys.first.toString());
          final res = await _callExtensionRaw(
            'ext.flutterpilot.batchSetState',
            {'type': type, 'states': json.encode(states)},
          );
          if (res.isError) return res.toCallToolResult();
          return CallToolResult(
            content: [
              TextContent(
                text:
                    '${res.data?['updatedCount'] ?? 0} of ${states.length} $type state(s) updated.',
              ),
            ],
          );
        }
        final name = p['name'] ?? p['provider'] ?? p['cubit'] ?? p['target'];
        if (name == null || !p.containsKey('value')) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Pass name and value, or states: {name: value}.',
              ),
            ],
          );
        }
        final res = await _callExtensionRaw('ext.flutterpilot.setState', {
          'type': p['type']?.toString() ?? await _stateTypeOf(name.toString()),
          'name': name.toString(),
          'value': encode(p['value']),
        });
        return res.toCallToolResult();
      },
    );

    _registerAppTool(
      name: 'get_network_logs',
      description:
          'Recent Dio requests and responses: method, URL, status, error, '
          'body (truncated, secrets redacted), and whether a mock answered. '
          'Use when an API call failed or to check what was sent.',
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
          'Keys and values of the Hive boxes the app registered with '
          'HivePilotInspector.registerBox, e.g. to check the UI saved '
          'something.',
      extension: 'ext.flutterpilot.getHiveContents',
    );

    _tool(
      'exec_sql_query',
      description:
          'Run a read-only SQL query (SELECT, WITH, PRAGMA, EXPLAIN) on the '
          'app\'s local database — Drift or sqflite, whichever is wired. Rows '
          'come back as JSON. List tables with '
          '"SELECT name FROM sqlite_master WHERE type=\'table\'". If the app '
          'registers several databases, a call without database names them.',
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
              // "No … databases registered", not "Multiple databases
              // registered (a, b)": that one names them.
              RegExp(r'No \w+ databases registered').hasMatch(m);
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
          'redacted by default — pass showSensitive=true to reveal them.',
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
          'Writes a SharedPreferences key (type: string (default), int, '
          'double, bool, stringList as a JSON array). remove:true deletes the '
          'key; no key with confirm "CLEAR_ALL" clears every preference. '
          'Needs --allow-destructive.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The key. Omit only to clear all (with confirm).',
          ),
          'remove': JsonSchema.boolean(description: 'Delete the key.'),
          'confirm': JsonSchema.string(
            description: '"CLEAR_ALL" to clear every preference (no key).',
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
      ),
      callback: (p, e) async {
        if (!allowDestructive) return _destructiveOperationDenied();
        if (p['remove'] == true || p['key'] == null) {
          return (await _callExtensionRaw(
            'ext.flutterpilot.clearSharedPreferences',
            {
              if (p['key'] != null) 'key': p['key'].toString(),
              if (p['confirm'] != null) 'confirm': p['confirm'].toString(),
            },
          )).toCallToolResult();
        }
        if (p['value'] == null) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Pass a value (or remove: true).')],
          );
        }
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
      'simulate_network',
      description:
          'Makes every Dio request slow (slow_3g, fast_4g), fail (offline) or '
          'normal again, to test loading and offline states.',
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
          'clear:true removes the mock for urlPattern, or all mocks without '
          'one — do that when done.',
      inputSchema: ToolInputSchema(
        properties: {
          'urlPattern': JsonSchema.string(
            description: 'Substring of the URL to match (e.g. "/api/users")',
          ),
          'clear': JsonSchema.boolean(
            description: 'Remove mocks instead of adding one.',
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
      ),
      callback: (p, e) async {
        if (p['clear'] == true) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.clearHttpMocks',
            {
              if (p['urlPattern'] != null)
                'urlPattern': p['urlPattern'].toString(),
            },
          );
          if (!res.isError) {
            await _noteTestStep({
              'type': 'clearMocks',
              'urlPattern': ?p['urlPattern']?.toString(),
            });
          }
          return res.toCallToolResult();
        }
        if (p['urlPattern'] == null || p['statusCode'] == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Pass urlPattern and statusCode (and body).'),
            ],
          );
        }
        final mapped = {
          'urlPattern': p['urlPattern']?.toString(),
          'statusCode': p['statusCode']?.toString(),
          'body': p['body']?.toString() ?? '',
          if (p['delayMs'] != null) 'delayMs': p['delayMs'].toString(),
        };
        final res = await _callExtensionRaw(
          'ext.flutterpilot.addHttpMock',
          mapped,
        );
        if (!res.isError) {
          await _noteTestStep({
            'type': 'mock',
            'urlPattern': mapped['urlPattern'],
            'statusCode': int.tryParse('${p['statusCode']}') ?? 200,
            'body': mapped['body'],
            'delayMs': int.tryParse('${p['delayMs'] ?? 0}') ?? 0,
          });
        }
        return res.toCallToolResult();
      },
    );
  }
}
