part of '../../fp_server.dart';

/// Tools for reading and injecting state (Riverpod, Bloc, SharedPreferences,
/// Hive, Drift), and for simulating/mocking network conditions.
mixin _StateManagementToolsMixin on _FlutterPilotServerBase {
  /// A state's value as shown: hidden when its name looks like a
  /// credential (authTokenProvider), tokens masked in any other.
  static String _stateValue(String name, String value) =>
      Redaction.sensitiveName.hasMatch(name)
      ? '${Redaction.mask} (the name looks like a credential)'
      : _clip(Redaction.text(value));

  /// A list provider prints every element; its first 200 chars say enough.
  static String _clip(String value) => value.length <= 200
      ? value
      : '${value.substring(0, 200)}… (${value.length} chars)';

  static const _sqlTablesQuery =
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name";

  /// A table name safe to put in a PRAGMA.
  static final _sqlName = RegExp(r'^\w+$');

  /// The `name` column of [query]'s rows, from the plugin at [extension].
  Future<List<String>> _sqlNames(
    String extension,
    String? database,
    String query,
  ) async {
    final res = await _callExtensionRaw(extension, {
      'sql': query,
      'dbName': ?database,
    });
    return [
      for (final row in res.data?['results'] as List? ?? const [])
        if (row is Map && row['name'] != null) '${row['name']}',
    ];
  }

  /// For a query that failed on a column or table that isn't there: the
  /// columns of the tables it reads, or the database's tables. Empty for any
  /// other failure, or when the schema can't be read either.
  Future<String> _sqlSchemaHint(
    String extension,
    String? database,
    String sql,
    String error,
  ) async {
    final miss = sqlMissIn(error);
    if (miss == null) return '';
    Future<List<String>> names(String query) async {
      final res = await _callExtensionRaw(extension, {
        'sql': query,
        'dbName': ?database,
      });
      return [
        for (final row in res.data?['results'] as List? ?? const [])
          if (row is Map && row['name'] != null) '${row['name']}',
      ];
    }

    final tables = await names(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    if (miss.isTable) {
      return tables.isEmpty
          ? ''
          : 'HINT: ${schemaHint('tables here', miss.name, tables)}';
    }
    final lines = <String>[];
    for (final table in tablesIn(sql)) {
      // Only a name the database has (and so safe to put in a PRAGMA).
      if (!tables.contains(table)) continue;
      final columns = await names('PRAGMA table_info("$table")');
      if (columns.isNotEmpty) {
        lines.add(schemaHint('columns of $table', miss.name, columns));
      }
    }
    return lines.isEmpty ? '' : 'HINT: ${lines.join('\n')}';
  }

  void _registerStateManagementTools() {
    _tool(
      'get_state',
      description:
          'Current values of the app\'s Riverpod providers and '
          'Blocs/Cubits (name: value (type)). history:true lists the '
          'recent changes instead, oldest first with times: each value '
          'with the one it replaced, providers created and disposed, and '
          'the route changes between them — how the state got to where it '
          'is.',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(
            enumValues: ['riverpod', 'bloc'],
            description: 'Only this kind.',
          ),
          'name': JsonSchema.string(description: 'Only names containing this.'),
          'history': JsonSchema.boolean(),
          'clear': JsonSchema.boolean(
            description:
                'Empty the history after returning it: do that before an action '
                'to see only its effects.',
          ),
        },
      ),
      callback: (p, e) async {
        if (p['history'] == true || p['clear'] == true) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.getStateHistory',
            {if (p['clear'] == true) 'clear': 'true'},
          );
          if (res.isError) return res.toCallToolResult();
          return CallToolResult(
            content: [
              TextContent(
                text: FlutterPilotServer._boundToolText(
                  formatStateHistory(
                    [
                      for (final c in (res.data?['changes'] as List? ?? []))
                        (c as Map).cast<String, Object?>(),
                    ],
                    dropped: res.data?['dropped'] as int? ?? 0,
                    type: p['type']?.toString(),
                    cleared: p['clear'] == true,
                  ),
                ),
              ),
            ],
          );
        }
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
          var states = res.data?['states'] as Map?;
          // One provider is what is usually wanted: in field sessions agents
          // passed a name the tool did not take, and got nothing.
          final wanted = p['name']?.toString().toLowerCase();
          if (states != null && wanted != null && wanted.isNotEmpty) {
            final all = states;
            states = {
              for (final e in all.entries)
                if ('${e.key}'.toLowerCase().contains(wanted)) e.key: e.value,
            };
            if (states.isEmpty && all.isNotEmpty) {
              sections.add(
                '$type: no state named like "${p['name']}". There are: '
                '${all.keys.take(40).join(', ')}'
                '${all.length > 40 ? ', …' : ''}.',
              );
              continue;
            }
          }
          sections.add(
            states == null || states.isEmpty
                ? '$type: nothing observed yet.'
                : '$type:\n${states.entries.map((e) => '  ${e.key}: ${_stateValue('${e.key}', '${e.value[valueKey]}')} (${e.value['type']})').join('\n')}',
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
          'for enum or class states it explains why not — drive the UI instead.',
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

    // No `clear: true` here, unlike get_debug_logs and get_http_profile:
    // ext.flutterpilot.getNetworkLogs takes no parameters and answers from the
    // plugin's own ring buffer, so emptying it needs a parameter on that
    // extension or a new one — an SDK protocol change (round 1/2 rule). The
    // eval runner's `shop_detail_requests` counts entries in the newest
    // window instead (field test #330).
    _tool(
      'get_network_logs',
      description:
          'Dio network requests (including mocks). Filter by query or errorsOnly, with limit.',
      inputSchema: ToolInputSchema(
        properties: {
          'query': JsonSchema.string(description: 'URL or message filter.'),
          'errorsOnly': JsonSchema.boolean(
            description: 'Only failed requests (status >= 400 or error).',
          ),
          'limit': JsonSchema.integer(
            description: 'Max entries to return (default 50).',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getNetworkLogs',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        var logs =
            (res.data?['logs'] as List?)
                ?.whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            [];
        if (p['errorsOnly'] == true) {
          logs = logs.where((l) {
            final code = l['statusCode'] as num?;
            final hasError = l['message'] != null || l['error'] != null;
            return hasError || (code != null && code >= 400);
          }).toList();
        }
        final query = p['query']?.toString().toLowerCase();
        if (query != null && query.isNotEmpty) {
          logs = logs.where((l) {
            final uri = (l['uri'] ?? '').toString().toLowerCase();
            final msg = (l['message'] ?? '').toString().toLowerCase();
            final body = (l['body'] ?? '').toString().toLowerCase();
            return uri.contains(query) ||
                msg.contains(query) ||
                body.contains(query);
          }).toList();
        }
        final limit = (p['limit'] as num?)?.toInt().clamp(1, 200) ?? 50;
        if (logs.length > limit) {
          logs = logs.sublist(logs.length - limit);
        }
        if (logs.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No network traffic captured.')],
          );
        }
        final formatted = logs
            .map((l) {
              final type = l['type']?.toString().toUpperCase() ?? 'LOG';
              final method = l['method'] != null ? '${l['method']} ' : '';
              final uri = l['uri'] ?? '';
              final status =
                  l['statusCode'] != null ? ' ${l['statusCode']}' : '';
              final mocked = l['mocked'] == true ? ' [MOCKED]' : '';
              final msg =
                  l['message'] != null ? ' error="${l['message']}"' : '';
              final body = l['body'] != null ? ' body=${l['body']}' : '';
              return '[${l['timestamp']}] $type $method$uri$status$mocked$msg$body';
            })
            .join('\n');
        return CallToolResult(content: [TextContent(text: formatted)]);
      },
    );

    _registerAppTool(
      name: 'get_hive_contents',
      description:
          'Keys and values of registered Hive boxes. Supports box and '
          'substring query filter.',
      extension: 'ext.flutterpilot.getHiveContents',
      properties: {
        'box': JsonSchema.string(
          description: 'Optional Hive box name to filter.',
        ),
        'query': JsonSchema.string(
          description: 'Substring filter for keys and values.',
        ),
      },
    );

    _tool(
      'exec_sql_query',
      description:
          'Run read-only SQL (SELECT, PRAGMA, EXPLAIN) or inspect schema '
          '(omit sql). query filters tables or rows.',
      inputSchema: ToolInputSchema(
        properties: {
          'sql': JsonSchema.string(
            description: 'SQL statement; omit for the schema.',
          ),
          'database': JsonSchema.string(
            description:
                'Database name, only needed when the app registers several.',
          ),
          'query': JsonSchema.string(
            description:
                'Substring filter for table names or row content.',
          ),
          'limit': JsonSchema.integer(
            description: 'Max rows or tables to return (default 50, max 200).',
          ),
        },
      ),
      callback: (p, e) async {
        final asked = p['sql']?.toString().trim() ?? '';
        // Results follow switch_device: say whose database answered.
        final origin =
            'Device "${_fleetManager.activeDeviceId ?? 'default'}", local '
            'app database (not the server)';
        // No query: the schema, so the first real one need not guess.
        final schemaOnly = asked.isEmpty;
        final sql = schemaOnly ? _sqlTablesQuery : asked;
        if (!isReadOnlySqlStatement(sql)) {
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
        var answeredBy = '';
        for (final ext in [
          'ext.flutterpilot.queryDrift',
          'ext.flutterpilot.querySqflite',
        ]) {
          final r = await _callExtensionRaw(ext, args);
          if (!r.isError || !absent(r)) {
            res = r;
            answeredBy = ext;
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
        if (res.isError) {
          final failed = res.toCallToolResult();
          final hint = await _sqlSchemaHint(
            answeredBy,
            db,
            sql,
            res.errorMessage ?? '',
          );
          if (hint.isEmpty) return failed;
          return CallToolResult(
            isError: true,
            content: [
              ...failed.content,
              TextContent(text: hint),
            ],
          );
        }
        final rows = res.data?['results'] as List? ?? const [];
        final shown = _activeContext?.sqlTablesShown ?? <String>{};
        final query = p['query']?.toString().toLowerCase();
        final rawLimit = (p['limit'] as num?)?.toInt();
        final limit = rawLimit != null ? rawLimit.clamp(1, 200) : 50;

        if (schemaOnly) {
          final lines = <String>[];
          for (final row in rows) {
            final table = row is Map ? '${row['name']}' : '';
            if (!_sqlName.hasMatch(table)) continue;
            if (query != null &&
                query.isNotEmpty &&
                !table.toLowerCase().contains(query)) {
              continue;
            }
            final columns = await _sqlNames(
              answeredBy,
              db,
              'PRAGMA table_info("$table")',
            );
            shown.add('$db/$table');
            lines.add('$table(${columns.take(40).join(', ')})');
            if (lines.length >= limit) break;
          }
          return CallToolResult(
            content: [
              TextContent(
                text: FlutterPilotServer._boundToolText(
                  '$origin: ${lines.length} tables'
                  '${rows.length > lines.length ? ' (${lines.length} shown)' : ''}:\n'
                  '${lines.join('\n')}',
                ),
              ),
            ],
          );
        }
        var filteredRows = rows;
        if (query != null && query.isNotEmpty) {
          filteredRows = rows
              .where((row) => jsonEncode(row).toLowerCase().contains(query))
              .toList();
        }
        final displayRows = filteredRows.take(limit).toList();
        final pluginTotal = (res.data?['total'] as num?)?.toInt();
        final note = truncationNote(
          shown: displayRows.length,
          total: res.data?['truncated'] == true
              ? pluginTotal
              : filteredRows.length,
          what: 'rows (first kept)',
          how:
              'Page with LIMIT/OFFSET in the SQL, or narrow with query/WHERE.',
        );
        final buf = StringBuffer('$origin: ${displayRows.length} row(s)');
        if (note != null) buf.write('\n$note');
        for (final row in displayRows) {
          buf.write('\n${jsonEncode(row)}');
        }
        // The first time a table is read, its columns: the next query on it
        // then has names to use instead of guesses (6 of 39 queries in
        // field sessions failed on a guessed column).
        var listed = 0;
        for (final table in tablesIn(sql)) {
          if (listed == 3) break;
          if (!_sqlName.hasMatch(table) ||
              table.toLowerCase().startsWith('sqlite_') ||
              table.toLowerCase().startsWith('pragma_') ||
              !shown.add('$db/$table')) {
            continue;
          }
          final columns = await _sqlNames(
            answeredBy,
            db,
            'PRAGMA table_info("$table")',
          );
          if (columns.isEmpty) continue;
          listed++;
          buf.write('\nColumns of $table: ${columns.take(40).join(', ')}');
        }
        return CallToolResult(content: [TextContent(text: buf.toString())]);
      },
    );

    _tool(
      'get_shared_preferences',
      description:
          'Reads SharedPreferences. Filter with key or query; sensitive '
          'keys are redacted.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'Specific key to read.'),
          'query': JsonSchema.string(
            description: 'Key substring filter.',
          ),
          'showSensitive': JsonSchema.boolean(
            description: 'Reveal sensitive values.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getSharedPreferences',
          {
            if (p['key'] != null) 'key': p['key'].toString(),
            if (p['showSensitive'] == true) 'showSensitive': 'true',
          },
        );
        if (res.isError) return res.toCallToolResult();
        var data = res.data ?? <String, dynamic>{};
        final query = p['query']?.toString().toLowerCase();
        if (query != null && query.isNotEmpty && data['prefs'] is Map) {
          final rawPrefs = (data['prefs'] as Map).cast<String, dynamic>();
          final filtered = Map.fromEntries(
            rawPrefs.entries.where(
              (entry) => entry.key.toLowerCase().contains(query),
            ),
          );
          data = {'prefs': filtered, 'count': filtered.length};
        }
        final text = jsonEncode(data);
        return CallToolResult(
          content: [TextContent(text: FlutterPilotServer._boundToolText(text))],
        );
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
                '"true"/"false", "42", or for a stringList a JSON array of '
                'strings.',
          ),
          'type': JsonSchema.string(
            enumValues: ['string', 'bool', 'int', 'double', 'stringList'],
            description: 'Default "string".',
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
          'Makes every HTTP request (http, dart:io, Dio) slow, fail '
          '(offline/chaos) or normal again. errorRate (0.0-1.0) and '
          'statusCode (e.g. 500) inject network chaos; delayMs holds '
          'each one that long. restore:true clears.',
      inputSchema: ToolInputSchema(
        properties: {
          'condition': JsonSchema.string(
            enumValues: ['normal', 'slow_3g', 'fast_4g', 'offline'],
          ),
          'delayMs': JsonSchema.integer(description: 'Up to 60000.'),
          'errorRate': JsonSchema.number(
            description: 'Chaos failure rate 0.0-1.0 (e.g. 0.5 for 50% drops).',
          ),
          'statusCode': JsonSchema.integer(
            description: 'HTTP status code on failure, e.g. 500, 503, 404.',
          ),
          'restore': JsonSchema.boolean(
            description: 'Restore normal network conditions.',
          ),
        },
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.simulateNetwork',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    _tool(
      'mock_http_response',
      description:
          'Canned Dio responses or errors (timeout/connection). Single endpoint '
          'or batch via mocks:[...]; clear:true resets.',
      inputSchema: ToolInputSchema(
        properties: {
          'urlPattern': JsonSchema.string(
            description: 'Part of the URL, e.g. "/api/users".',
          ),
          'clear': JsonSchema.boolean(
            description:
                'Remove the mock for urlPattern, or every mock without one.',
          ),
          'statusCode': JsonSchema.integer(),
          'body': JsonSchema.string(
            description:
                'Response body as a JSON string, e.g. \'{"error":"not found"}\'.',
          ),
          'delayMs': JsonSchema.integer(
            description: 'Delay before the response or failure (default 0).',
          ),
          'error': JsonSchema.string(
            enumValues: ['timeout', 'connection'],
            description:
                'In place of statusCode: the server never answers (timeout) or '
                'can\'t be reached (connection).',
          ),
          'mocks': JsonSchema.array(
            description:
                'Batch of mocks: [{urlPattern, statusCode, body, delayMs, error}].',
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

        final rawMocks = p['mocks'];
        if (rawMocks is List && rawMocks.isNotEmpty) {
          final items = rawMocks
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
          final results = <String>[];
          var failedCount = 0;
          for (final item in items) {
            final mapped = {
              'urlPattern': item['urlPattern']?.toString(),
              'statusCode': (item['statusCode'] ?? 200).toString(),
              'body': item['body']?.toString() ?? '',
              if (item['delayMs'] != null)
                'delayMs': item['delayMs'].toString(),
              if (item['error'] != null) 'error': item['error'].toString(),
            };
            final res = await _callExtensionRaw(
              'ext.flutterpilot.addHttpMock',
              mapped,
            );
            if (res.isError) {
              failedCount++;
              results.add(
                '✗ Mock failed for ${item['urlPattern']}: ${res.errorMessage}',
              );
            } else {
              results.add(
                '✓ Mocked ${item['urlPattern']} (status: ${item['statusCode'] ?? 200})',
              );
              await _noteTestStep({
                'type': 'mock',
                'urlPattern': mapped['urlPattern'],
                'statusCode': int.tryParse('${item['statusCode']}') ?? 200,
                'body': mapped['body'],
                'delayMs': int.tryParse('${item['delayMs'] ?? 0}') ?? 0,
                if (item['error'] != null) 'error': item['error'].toString(),
              });
            }
          }
          return CallToolResult(
            isError: failedCount > 0 && failedCount == items.length,
            content: [TextContent(text: results.join('\n'))],
          );
        }

        final error = p['error']?.toString();
        if (p['urlPattern'] == null ||
            (p['statusCode'] == null && error == null)) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Pass urlPattern and statusCode (and body), or '
                    'urlPattern and error ("timeout" / "connection"), or mocks: [...].',
              ),
            ],
          );
        }
        final mapped = {
          'urlPattern': p['urlPattern']?.toString(),
          'statusCode': (p['statusCode'] ?? 0).toString(),
          'body': p['body']?.toString() ?? '',
          if (p['delayMs'] != null) 'delayMs': p['delayMs'].toString(),
          'error': ?error,
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
            'error': ?error,
          });
        }
        return res.toCallToolResult();
      },
    );
  }
}
