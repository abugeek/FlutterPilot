part of '../../flutterpilot_server.dart';

/// Tools for Supabase, GoRouter, Connectivity, Firebase, and Secure Storage
/// plugin integrations.
mixin _PluginIntegrationToolsMixin on _FlutterPilotServerBase {
  void _registerPluginIntegrationTools() {
    // =========================================================================
    // Supabase
    // =========================================================================

    _registerAppTool(
      name: 'get_supabase_auth',
      description:
          'Inspect current Supabase auth state: user profile, session, JWT expiry, '
          'and recent auth events. Pass showSensitive=true to reveal email/phone. '
          'PREREQUISITES: App must use flutterpilot_supabase plugin.',
      extension: 'ext.flutterpilot.getSupabaseAuth',
      properties: {
        'showSensitive': JsonSchema.string(
          description:
              'Set to "true" to reveal email/phone/user_id. Default: redacted.',
        ),
      },
      formatResult: (json) {
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
      },
    );

    _registerAppTool(
      name: 'get_supabase_realtime',
      description:
          'List all active Supabase Realtime channel subscriptions. '
          'Shows topic, join status, and close status.',
      extension: 'ext.flutterpilot.getSupabaseRealtime',
      formatResult: (json) {
        final channels = json['channels'] as List? ?? [];
        if (channels.isEmpty) return 'No active Realtime channels.';
        return channels
            .map(
              (c) =>
                  '${c['topic']} — joined: ${c['isJoined']}, closed: ${c['isClosed']}',
            )
            .join('\n');
      },
    );

    _registerAppTool(
      name: 'query_supabase_table',
      description:
          'Query rows from a Supabase table using the project\'s own credentials. '
          'Returns up to `limit` rows (default 20, max 200). Optionally filter '
          'with "column=value" equality. Useful for inspecting data during debug. '
          'PREREQUISITES: App must use flutterpilot_supabase plugin.',
      extension: 'ext.flutterpilot.querySupabaseTable',
      properties: {
        'table': JsonSchema.string(
          description: 'Supabase table name (required).',
        ),
        'limit': JsonSchema.string(
          description: 'Max rows to return (1–200, default 20).',
        ),
        'filter': JsonSchema.string(
          description:
              'Optional equality filter in "column=value" format, e.g. "user_id=abc123".',
        ),
      },
      formatResult: (json) {
        final table = json['table'];
        final rowCount = json['rowCount'] ?? 0;
        final rows = json['rows'] as List? ?? [];
        if (rows.isEmpty) return 'Table "$table": 0 rows returned.';
        final buf = StringBuffer('Table "$table": $rowCount row(s)\n');
        for (final row in rows.take(50)) {
          buf.writeln('  ${jsonEncode(row)}');
        }
        if (rowCount > 50) buf.writeln('  ... and ${rowCount - 50} more rows');
        return buf.toString();
      },
    );

    _registerAppTool(
      name: 'supabase_sign_out',
      description:
          '⚠ MAKES REAL NETWORK CALL — signs out the current Supabase user '
          'via the Supabase Auth API. This affects the real session. '
          'Scope: "local" (default, this device only), "global" (all devices), '
          '"others" (other sessions only). Only use in dev/test environments.',
      extension: 'ext.flutterpilot.supabaseSignOut',
      destructive: true,
      properties: {
        'scope': JsonSchema.string(
          description:
              'Sign-out scope: "local" (this device), "global" (all devices), "others".',
          enumValues: ['local', 'global', 'others'],
        ),
      },
    );

    _registerAppTool(
      name: 'supabase_refresh_session',
      description:
          '⚠ MAKES REAL NETWORK CALL — force-refreshes the current Supabase '
          'session token via the Supabase Auth API. Use when testing token '
          'expiry flows. Only use in dev/test environments.',
      extension: 'ext.flutterpilot.supabaseRefreshSession',
      destructive: true,
    );

    // =========================================================================
    // GoRouter
    // =========================================================================

    _registerAppTool(
      name: 'get_gorouter_state',
      description:
          'Inspect the current GoRouter navigation state: location, path parameters, '
          'query parameters, matched routes, and whether pop is available.',
      extension: 'ext.flutterpilot.getGoRouterState',
      formatResult: (json) {
        final buf = StringBuffer('Location: ${json['currentLocation']}\n');
        final pathParams = json['pathParameters'] as Map? ?? {};
        if (pathParams.isNotEmpty) {
          buf.writeln('Path params: $pathParams');
        }
        final queryParams = json['queryParameters'] as Map? ?? {};
        if (queryParams.isNotEmpty) {
          buf.writeln('Query params: $queryParams');
        }
        buf.writeln('Can pop: ${json['canPop']}');
        final matched = json['matchedRoutes'] as List? ?? [];
        for (final m in matched) {
          buf.writeln('  Matched: ${m['matchedLocation']} → ${m['route']}');
        }
        return buf.toString();
      },
    );

    _registerAppTool(
      name: 'get_gorouter_config',
      description:
          'List all registered GoRouter routes and their configuration (paths, names, children).',
      extension: 'ext.flutterpilot.getGoRouterConfig',
    );

    _registerAppTool(
      name: 'get_gorouter_history',
      description:
          'View the recent navigation history — timestamped list of route changes.',
      extension: 'ext.flutterpilot.getGoRouterHistory',
    );

    _registerAppTool(
      name: 'gorouter_navigate',
      description:
          'Navigate using GoRouter. Actions: "go" (replace stack), "push" (add to stack), '
          '"replace" (replace current), "pop" (go back). Requires location for go/push/replace.',
      extension: 'ext.flutterpilot.goRouterNavigate',
      properties: {
        'location': JsonSchema.string(
          description:
              'The route path to navigate to (e.g. "/home", "/user/123").',
        ),
        'action': JsonSchema.string(
          description: 'Navigation action.',
          enumValues: ['go', 'push', 'replace', 'pop'],
        ),
      },
    );

    // =========================================================================
    // Connectivity
    // =========================================================================

    _registerAppTool(
      name: 'get_connectivity',
      description:
          'Check current network connectivity status: wifi, mobile, ethernet, vpn, none. '
          'Also shows whether simulated-offline mode is active.',
      extension: 'ext.flutterpilot.getConnectivity',
      formatResult: (json) {
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
      },
    );

    _registerAppTool(
      name: 'get_connectivity_history',
      description: 'View timestamped log of connectivity state transitions.',
      extension: 'ext.flutterpilot.getConnectivityHistory',
      properties: {
        'limit': JsonSchema.string(
          description: 'Max number of entries to return (default: 100).',
        ),
      },
    );

    // =========================================================================
    // Firebase (flutterpilot_firebase)
    // =========================================================================

    _registerAppTool(
      name: 'get_firebase_auth',
      description:
          'Who is signed in to Firebase Auth in the app: uid (for Firestore '
          'paths like users/{uid}/...), providers, anonymous/verified, token '
          'expiry and custom claims, recent sign-in/out events, and the '
          'Firebase project. Email/name/phone are redacted unless '
          'showSensitive=true. Needs the flutterpilot_firebase plugin.',
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
          'Read Firestore with the app\'s own connection and signed-in user '
          '(so security rules apply as in the app). path is a collection '
          '("users/UID/notes") or a document ("users/UID"). Optional where '
          '("done == false", ops == != < <= > >= array-contains), orderBy '
          '("createdAt desc"), limit (default 20, max 100), source "cache" to '
          'see what the app has locally instead of the server. Needs the '
          'flutterpilot_firebase plugin.',
      extension: 'ext.flutterpilot.queryFirestore',
      properties: {
        'path': JsonSchema.string(description: 'Collection or document path.'),
        'where': JsonSchema.string(
          description: 'One filter: "field op value".',
        ),
        'orderBy': JsonSchema.string(
          description: 'Field, optionally followed by "desc".',
        ),
        'limit': JsonSchema.integer(description: '1–100, default 20.'),
        'source': JsonSchema.string(
          description: '"server" (default) or "cache".',
          enumValues: ['server', 'cache'],
        ),
      },
      formatResult: (json) {
        final path = json['path'];
        final from = json['source'] == 'cache' ? ' (from the local cache)' : '';
        if (json['kind'] == 'document') {
          return json['exists'] == true
              ? 'Document $path$from:\n${jsonEncode(json['data'])}'
              : 'Document $path does not exist$from.';
        }
        final docs = json['docs'] as List? ?? const [];
        if (docs.isEmpty) return 'Collection $path: no documents match$from.';
        final more = docs.length == json['limit']
            ? ' (limit reached; there may be more)'
            : '';
        return [
          'Collection $path: ${docs.length} document(s)$from$more',
          for (final d in docs) '- ${d['id']}: ${jsonEncode(d['data'])}',
        ].join('\n');
      },
    );

    // =========================================================================
    // Secure Storage
    // =========================================================================

    _registerAppTool(
      name: 'get_secure_storage_keys',
      description:
          'List all keys in FlutterSecureStorage. Values are redacted by default. '
          'Pass showValues=true to reveal (sensitive keys like passwords are always redacted).',
      extension: 'ext.flutterpilot.getSecureStorageKeys',
      properties: {
        'showValues': JsonSchema.string(
          description: '"true" to reveal values (except always-redacted keys).',
        ),
      },
      formatResult: (json) {
        final keys = json['keys'] as Map? ?? {};
        if (keys.isEmpty) return 'Secure storage is empty.';
        final count = json['count'];
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
      },
    );

    _tool(
      'read_secure_storage_key',
      description:
          'Read a specific key from FlutterSecureStorage. '
          'Keys matching password/secret/api_key patterns are always redacted.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string(description: 'The key to read.')},
        required: ['key'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.readSecureStorageKey',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    _tool(
      'set_secure_storage_key',
      description:
          'Write a key-value pair to FlutterSecureStorage. Use for test data injection.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'The key to set.'),
          'value': JsonSchema.string(description: 'The value to store.'),
        },
        required: ['key', 'value'],
      ),
      callback: (p, e) {
        if (!allowDestructive) {
          return Future.value(_destructiveOperationDenied());
        }
        return _callExtensionRaw(
          'ext.flutterpilot.setSecureStorageKey',
          p,
        ).then((res) => res.toCallToolResult());
      },
    );

    _tool(
      'delete_secure_storage_key',
      description:
          '⚠ DESTRUCTIVE — Delete a specific key from FlutterSecureStorage. '
          'To wipe ALL keys, omit "key" and pass confirm="DELETE_ALL". '
          'Deletion cannot be undone.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'Key to delete. Omit to clear ALL secure storage (requires confirm).',
          ),
          'confirm': JsonSchema.string(
            description:
                'Required when wiping all keys (no "key" given). '
                'Must be exactly "DELETE_ALL" to proceed.',
          ),
        },
      ),
      callback: (p, e) {
        if (!allowDestructive) {
          return Future.value(_destructiveOperationDenied());
        }
        return _callExtensionRaw('ext.flutterpilot.deleteSecureStorageKey', {
          if (p['key'] != null) 'key': p['key'].toString(),
          if (p['confirm'] != null) 'confirm': p['confirm'].toString(),
        }).then((res) => res.toCallToolResult());
      },
    );
  }
}
