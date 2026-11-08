part of '../../fp_server.dart';

/// Tools for Supabase, Connectivity, Firebase, and Secure Storage
/// plugin integrations.
mixin _PluginIntegrationToolsMixin on _FlutterPilotServerBase {
  void _registerPluginIntegrationTools() {
    // =========================================================================
    // Supabase
    // =========================================================================

    String formatSupabaseAuth(Map<String, dynamic> json) {
      final isAuth = json['isAuthenticated'] == true;
      if (!isAuth) return 'Not authenticated. No active session.';
      final user = json['user'] as Map?;
      final session = json['session'] as Map?;
      final events = json['authEvents'] as List? ?? [];
      final buf = StringBuffer('Authenticated\n');
      if (user != null) {
        buf.writeln('  Role: ${user['role']}');
        buf.writeln('  Email: ${user['email']}');
        buf.writeln('  Created: ${user['createdAt']}');
      }
      if (session != null) {
        buf.writeln('  Token expired: ${session['isExpired']}');
        buf.writeln('  Expires at: ${session['expiresAt']}');
      }
      if (events.isNotEmpty) {
        buf.writeln('  Last ${events.length} auth events:');
        for (final e in events.reversed.take(5)) {
          buf.writeln('    [${e['timestamp']}] ${e['event']}');
        }
      }
      return buf.toString();
    }

    _tool(
      'get_supabase_auth',
      description:
          'Supabase session and user state; realtime:true adds channels, '
          'showSensitive:true reveals email/phone.',
      inputSchema: ToolInputSchema(
        properties: {
          'showSensitive': JsonSchema.boolean(
            description: 'Reveal email/phone/user_id.',
          ),
          'realtime': JsonSchema.boolean(
            description: 'Include Realtime channel subscriptions.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getSupabaseAuth',
          {if (p['showSensitive'] == true) 'showSensitive': 'true'},
        );
        if (res.isError) return res.toCallToolResult();
        final buf = StringBuffer(formatSupabaseAuth(res.data!));
        if (p['realtime'] == true) {
          final rt = await _callExtensionRaw(
            'ext.flutterpilot.getSupabaseRealtime',
            {},
          );
          final channels = rt.data?['channels'] as List? ?? const [];
          buf.write(
            rt.isError
                ? '\nRealtime: ${rt.errorMessage}'
                : channels.isEmpty
                ? '\nNo active Realtime channels.'
                : '\nRealtime channels:\n${channels.map((c) => '  ${c['topic']} — joined: ${c['isJoined']}, closed: ${c['isClosed']}').join('\n')}',
          );
        }
        return CallToolResult(content: [TextContent(text: buf.toString())]);
      },
    );

    _registerAppTool(
      name: 'query_supabase_table',
      description:
          'Rows of a Supabase table read with the app\'s own client and '
          'session, so row-level security applies.',
      extension: 'ext.flutterpilot.querySupabaseTable',
      properties: {
        'table': JsonSchema.string(description: 'Supabase table name.'),
        'limit': JsonSchema.integer(description: '1–200, default 20.'),
        'filter': JsonSchema.string(
          description: 'One equality filter, "column=value".',
        ),
        'query': JsonSchema.string(
          description: 'Case-insensitive substring filter across row data.',
        ),
      },
      required: ['table'],
      formatResultWithParams: (json, params) {
        final table = json['table'];
        final rowCount = json['rowCount'] ?? 0;
        var rows = (json['rows'] as List? ?? []).cast<dynamic>();
        final q = params['query']?.toString().toLowerCase();
        if (q != null && q.isNotEmpty) {
          rows = rows.where((r) => jsonEncode(r).toLowerCase().contains(q)).toList();
        }
        if (rows.isEmpty) return 'Table "$table": 0 rows returned.';
        final note = truncationNote(
          shown: rows.length > 50 ? 50 : rows.length,
          total: rowCount is num ? rowCount.toInt() : rows.length,
          what: 'rows',
          how: 'Raise limit (1–200) or narrow with filter.',
        );
        final buf = StringBuffer('Table "$table": ${rows.length} row(s)\n');
        for (final row in rows.take(50)) {
          buf.writeln('  ${jsonEncode(row)}');
        }
        if (note != null) buf.writeln('  $note');
        return buf.toString();
      },
    );

    _tool(
      'supabase_session',
      description:
          'Performs Supabase Auth action ("refresh" or "sign_out"). Needs --allow-destructive.',
      inputSchema: ToolInputSchema(
        properties: {
          'action': JsonSchema.string(enumValues: ['refresh', 'sign_out']),
          'scope': JsonSchema.string(
            enumValues: ['local', 'global', 'others'],
            description: 'For sign_out.',
          ),
        },
        required: ['action'],
      ),
      callback: (p, e) async {
        if (!allowDestructive) return _destructiveOperationDenied();
        final res = p['action'] == 'sign_out'
            ? await _callExtensionRaw('ext.flutterpilot.supabaseSignOut', {
                if (p['scope'] != null) 'scope': p['scope'].toString(),
              })
            : await _callExtensionRaw(
                'ext.flutterpilot.supabaseRefreshSession',
                {},
              );
        return res.toCallToolResult();
      },
    );

    // =========================================================================
    // Connectivity
    // =========================================================================

    String formatConnectivity(Map<String, dynamic> json) {
      final connectivity = json['connectivity'] as List? ?? [];
      final isOnline = json['isOnline'] == true;
      final buf = StringBuffer();
      buf.writeln('Online: $isOnline');
      buf.writeln('Connectivity: ${connectivity.join(', ')}');
      if (json['hasWifi'] == true) buf.writeln('  ✓ WiFi');
      if (json['hasMobile'] == true) buf.writeln('  ✓ Mobile');
      if (json['hasEthernet'] == true) buf.writeln('  ✓ Ethernet');
      if (json['hasVpn'] == true) buf.writeln('  ✓ VPN');
      return buf.toString();
    }

    _tool(
      'get_connectivity',
      description:
          'Network connectivity (wifi, mobile, none) and online status. '
          'waitForStatus polls until state matches.',
      inputSchema: ToolInputSchema(
        properties: {
          'waitForStatus': JsonSchema.string(
            enumValues: ['online', 'offline', 'wifi', 'mobile', 'none'],
            description: 'Poll until network status matches this condition.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout in ms for waitForStatus (default 3000).',
          ),
          'history': JsonSchema.boolean(
            description: 'Include the connectivity changes.',
          ),
          'limit': JsonSchema.integer(
            description: 'Max history entries (default 100).',
          ),
        },
      ),
      callback: (p, e) async {
        final waitForStatus = p['waitForStatus']?.toString().toLowerCase();
        final timeoutMs =
            (p['timeoutMs'] as num?)?.toInt().clamp(100, 30000) ?? 3000;

        if (waitForStatus != null && waitForStatus.isNotEmpty) {
          final stopwatch = Stopwatch()..start();
          while (stopwatch.elapsedMilliseconds < timeoutMs) {
            final check = await _callExtensionRaw(
              'ext.flutterpilot.getConnectivity',
              {},
            );
            if (!check.isError && check.data != null) {
              final connList = (check.data!['connectivity'] as List?)
                      ?.map((e) => e.toString().toLowerCase())
                      .toList() ??
                  const [];
              final isOnline = check.data!['isOnline'] == true ||
                  check.data!['online'] == true;
              final matched = switch (waitForStatus) {
                'online' => isOnline,
                'offline' => !isOnline,
                _ => connList.contains(waitForStatus) ||
                    connList.any((c) => c.contains(waitForStatus)),
              };
              if (matched) break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }

        final res = await _callExtensionRaw(
          'ext.flutterpilot.getConnectivity',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final buf = StringBuffer(formatConnectivity(res.data!));
        if (p['history'] == true) {
          final h = await _callExtensionRaw(
            'ext.flutterpilot.getConnectivityHistory',
            {if (p['limit'] != null) 'limit': p['limit'].toString()},
          );
          buf.write(
            'History: ${h.isError ? h.errorMessage : jsonEncode(h.data)}',
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: FlutterPilotServer._boundToolText(buf.toString()),
            ),
          ],
        );
      },
    );

    // =========================================================================
    // Firebase (fp_firebase)
    // =========================================================================

    _registerAppTool(
      name: 'get_firebase_auth',
      description:
          'Firebase Auth user, token, claims, and project id; '
          'showSensitive:true reveals email/name/phone.',
      extension: 'ext.flutterpilot.getFirebaseAuth',
      properties: {
        'showSensitive': JsonSchema.boolean(
          description: 'Reveal email, display name and phone number.',
        ),
      },
      formatResult: (json) {
        final buf = StringBuffer('Project: ${json['projectId']}\n');
        final user = json['user'] as Map?;
        if (user == null) {
          buf.writeln('Not signed in.');
        } else {
          buf.writeln(
            'Signed in: uid ${user['uid']}'
            '${user['isAnonymous'] == true ? ' (anonymous)' : ''}',
          );
          for (final field in ['email', 'displayName', 'phoneNumber']) {
            if (user[field] != null) buf.writeln('  $field: ${user[field]}');
          }
          buf.writeln(
            '  providers: ${(user['providers'] as List).join(', ')}; '
            'email verified: ${user['emailVerified']}',
          );
          final token = json['token'] as Map?;
          if (token?['expiresAt'] != null) {
            buf.writeln('  token expires: ${token!['expiresAt']}');
          }
          final claims = token?['customClaims'] as Map?;
          if (claims != null && claims.isNotEmpty) {
            buf.writeln('  custom claims: ${jsonEncode(claims)}');
          }
        }
        final events = json['events'] as List? ?? const [];
        if (events.isNotEmpty) {
          buf.writeln('Recent auth events:');
          for (final e in events.reversed.take(5)) {
            buf.writeln(
              '  ${e['at']} ${e['event']}'
              '${e['provider'] != null ? ' (${e['provider']})' : ''}',
            );
          }
        }
        return buf.toString().trim();
      },
    );

    _registerAppTool(
      name: 'query_firestore',
      description:
          'Reads Firestore through the app\'s own connection and signed-in '
          'user, so security rules apply as in the app.',
      extension: 'ext.flutterpilot.queryFirestore',
      properties: {
        'path': JsonSchema.string(
          description:
              'A collection ("users/UID/notes") or a document ("users/UID").',
        ),
        'where': JsonSchema.string(
          description:
              'One filter, "field op value" with == != < <= > >= or '
              'array-contains, e.g. "done == false".',
        ),
        'orderBy': JsonSchema.string(
          description: 'A field, optionally followed by "desc".',
        ),
        'limit': JsonSchema.integer(description: '1–100, default 20.'),
        'query': JsonSchema.string(
          description: 'Case-insensitive substring filter in document data/id.',
        ),
        'source': JsonSchema.string(
          enumValues: ['server', 'cache'],
          description: 'cache: what the app has locally instead of the server.',
        ),
      },
      required: ['path'],
      formatResultWithParams: (json, params) {
        final path = json['path'];
        final from = json['source'] == 'cache' ? ' (from the local cache)' : '';
        if (json['kind'] == 'document') {
          return json['exists'] == true
              ? 'Document $path$from:\n${jsonEncode(json['data'])}'
              : 'Document $path does not exist$from.';
        }
        var docs = (json['docs'] as List? ?? const []).cast<dynamic>();
        final q = params['query']?.toString().toLowerCase();
        if (q != null && q.isNotEmpty) {
          docs = docs.where((d) {
            final id = d['id']?.toString().toLowerCase() ?? '';
            final dataStr = jsonEncode(d['data']).toLowerCase();
            return id.contains(q) || dataStr.contains(q);
          }).toList();
        }
        if (docs.isEmpty) return 'Collection $path: no documents match$from.';
        final note = docs.length == json['limit']
            ? truncationNote(
                shown: docs.length,
                total: null,
                what: 'documents',
                how: 'Raise limit (1–100) or narrow with where/orderBy.',
              )
            : null;
        return [
          'Collection $path: ${docs.length} document(s)$from',
          for (final d in docs) '- ${d['id']}: ${jsonEncode(d['data'])}',
          ?note,
        ].join('\n');
      },
    );

    // =========================================================================
    // Secure Storage
    // =========================================================================

    String formatSecureStorage(Map<String, dynamic> json, {String? query}) {
      var keys = (json['keys'] as Map? ?? {}).cast<dynamic, dynamic>();
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        keys = Map.fromEntries(
          keys.entries.where(
            (e) => e.key.toString().toLowerCase().contains(q),
          ),
        );
      }
      if (keys.isEmpty) {
        return query != null && query.isNotEmpty
            ? 'No keys matching "$query" in secure storage.'
            : 'Secure storage is empty.';
      }
      final count = keys.length;
      final buf = StringBuffer('$count key(s) in secure storage:\n');
      for (final entry in keys.entries) {
        final info = entry.value as Map;
        if (info['redacted'] == true) {
          buf.writeln('  ${entry.key}: [${info['length']} chars, redacted]');
        } else {
          buf.writeln('  ${entry.key}: ${info['value']}');
        }
      }
      return buf.toString();
    }

    _tool(
      'get_secure_storage',
      description:
          'FlutterSecureStorage keys (redacted). Filter with key or query; '
          'showValues reveals non-sensitive values.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'Read only this key.'),
          'query': JsonSchema.string(
            description: 'Key substring filter.',
          ),
          'showValues': JsonSchema.boolean(
            description: 'Reveal values (except always-redacted keys).',
          ),
        },
      ),
      callback: (p, e) async {
        if (p['key'] != null) {
          return (await _callExtensionRaw(
            'ext.flutterpilot.readSecureStorageKey',
            {'key': p['key'].toString()},
          )).toCallToolResult();
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getSecureStorageKeys',
          {if (p['showValues'] == true) 'showValues': 'true'},
        );
        if (res.isError) return res.toCallToolResult();
        final query = p['query']?.toString();
        return CallToolResult(
          content: [
            TextContent(text: formatSecureStorage(res.data!, query: query)),
          ],
        );
      },
    );

    _tool(
      'set_secure_storage_key',
      description:
          'Writes a FlutterSecureStorage key (test data). delete:true removes '
          'it; no key with delete:true and confirm "DELETE_ALL" wipes all '
          'keys. Needs --allow-destructive.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'The key.'),
          'value': JsonSchema.string(description: 'The value to store.'),
          'delete': JsonSchema.boolean(description: 'Delete instead of write.'),
          'confirm': JsonSchema.string(
            description: '"DELETE_ALL" to wipe every key (no key given).',
          ),
        },
      ),
      callback: (p, e) async {
        if (!allowDestructive) return _destructiveOperationDenied();
        if (p['delete'] == true) {
          return (await _callExtensionRaw(
            'ext.flutterpilot.deleteSecureStorageKey',
            {
              if (p['key'] != null) 'key': p['key'].toString(),
              if (p['confirm'] != null) 'confirm': p['confirm'].toString(),
            },
          )).toCallToolResult();
        }
        if (p['key'] == null || p['value'] == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Pass key and value (or delete: true).'),
            ],
          );
        }
        return (await _callExtensionRaw(
          'ext.flutterpilot.setSecureStorageKey',
          {'key': p['key'].toString(), 'value': p['value'].toString()},
        )).toCallToolResult();
      },
    );
  }
}
