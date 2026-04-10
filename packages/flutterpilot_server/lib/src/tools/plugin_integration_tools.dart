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

    server.registerTool(
      'supabase_sign_out',
      description:
          '⚠ MAKES REAL NETWORK CALL — signs out the current Supabase user '
          'via the Supabase Auth API. This affects the real session. '
          'Scope: "local" (default, this device only), "global" (all devices), '
          '"others" (other sessions only). Only use in dev/test environments.',
      inputSchema: ToolInputSchema(
        properties: {
          'scope': JsonSchema.string(
            description:
                'Sign-out scope: "local" (this device), "global" (all devices), "others".',
            enumValues: ['local', 'global', 'others'],
          ),
        },
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.supabaseSignOut',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    _registerAppTool(
      name: 'supabase_refresh_session',
      description:
          '⚠ MAKES REAL NETWORK CALL — force-refreshes the current Supabase '
          'session token via the Supabase Auth API. Use when testing token '
          'expiry flows. Only use in dev/test environments.',
      extension: 'ext.flutterpilot.supabaseRefreshSession',
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

    server.registerTool(
      'gorouter_navigate',
      description:
          'Navigate using GoRouter. Actions: "go" (replace stack), "push" (add to stack), '
          '"replace" (replace current), "pop" (go back). Requires location for go/push/replace.',
      inputSchema: ToolInputSchema(
        properties: {
          'location': JsonSchema.string(
            description: 'The route path to navigate to (e.g. "/home", "/user/123").',
          ),
          'action': JsonSchema.string(
            description: 'Navigation action.',
            enumValues: ['go', 'push', 'replace', 'pop'],
          ),
        },
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.goRouterNavigate',
        p,
      ).then((res) => res.toCallToolResult()),
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
        final simulated = json['simulatedOffline'] == true;
        final buf = StringBuffer();
        buf.writeln('Online: $isOnline');
        buf.writeln('Connectivity: ${connectivity.join(', ')}');
        if (simulated) buf.writeln('⚠ Simulated offline mode is ACTIVE');
        if (json['hasWifi'] == true) buf.writeln('  ✓ WiFi');
        if (json['hasMobile'] == true) buf.writeln('  ✓ Mobile');
        if (json['hasEthernet'] == true) buf.writeln('  ✓ Ethernet');
        if (json['hasVpn'] == true) buf.writeln('  ✓ VPN');
        return buf.toString();
      },
    );

    _registerAppTool(
      name: 'get_connectivity_history',
      description:
          'View timestamped log of connectivity state transitions.',
      extension: 'ext.flutterpilot.getConnectivityHistory',
      properties: {
        'limit': JsonSchema.string(
          description: 'Max number of entries to return (default: 100).',
        ),
      },
    );

    server.registerTool(
      'simulate_offline',
      description:
          'Toggle simulated offline mode. When enabled, '
          'ConnectivityPilotInspector.isSimulatedOffline returns true. '
          'App code can check this flag to simulate offline behavior for testing.',
      inputSchema: ToolInputSchema(
        properties: {
          'enabled': JsonSchema.string(
            description: '"true" to enable simulated offline, "false" to disable.',
            enumValues: ['true', 'false'],
          ),
        },
        required: ['enabled'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.simulateOffline',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    // =========================================================================
    // Firebase
    // =========================================================================

    _registerAppTool(
      name: 'get_firebase_status',
      description:
          'Check which Firebase services are registered and their status '
          '(Crashlytics, Analytics, Performance, Messaging).',
      extension: 'ext.flutterpilot.getFirebaseStatus',
      formatResult: (json) {
        final buf = StringBuffer('Firebase Services:\n');
        for (final service in ['crashlytics', 'analytics', 'performance', 'messaging']) {
          final info = json[service] as Map? ?? {};
          final available = info['available'] == true;
          buf.writeln('  $service: ${available ? '✓ registered' : '✗ not registered'}');
          if (service == 'crashlytics' && available) {
            buf.writeln('    Collection enabled: ${info['isCrashlyticsCollectionEnabled']}');
          }
          if (service == 'messaging' && available) {
            buf.writeln('    Authorization: ${info['authorizationStatus']}');
          }
        }
        return buf.toString();
      },
    );

    _registerAppTool(
      name: 'get_fcm_token',
      description: 'Get the Firebase Cloud Messaging token (truncated for security).',
      extension: 'ext.flutterpilot.getFcmToken',
    );

    server.registerTool(
      'log_analytics_event',
      description:
          '⚠ MAKES REAL NETWORK CALL — logs a custom Firebase Analytics event '
          'to your Firebase project (visible in the Firebase console). '
          'Useful for verifying analytics instrumentation during development. '
          'Do not call in production test runs to avoid polluting analytics data.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description: 'Event name (e.g. "button_pressed", "screen_view").',
          ),
          'params': JsonSchema.string(
            description:
                'Optional JSON object of event parameters (e.g. \'{"button_id":"submit"}\').',
          ),
        },
        required: ['name'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.logAnalyticsEvent',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    _registerAppTool(
      name: 'get_analytics_log',
      description:
          'View recent analytics events logged through FlutterPilot.',
      extension: 'ext.flutterpilot.getAnalyticsLog',
      properties: {
        'limit': JsonSchema.string(
          description: 'Max number of events to return (default: 200).',
        ),
      },
    );

    server.registerTool(
      'start_performance_trace',
      description:
          'Start a named Firebase Performance trace. Use stop_performance_trace to end it.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description: 'Trace name (e.g. "checkout_flow", "data_sync").',
          ),
        },
        required: ['name'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.startPerformanceTrace',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'stop_performance_trace',
      description: 'Stop a previously started Firebase Performance trace.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description: 'Trace name that was passed to start_performance_trace.',
          ),
        },
        required: ['name'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.stopPerformanceTrace',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'record_crashlytics_error',
      description:
          '⚠ MAKES REAL NETWORK CALL — records a test error in Firebase '
          'Crashlytics (appears in your Firebase console). Useful for verifying '
          'crash reporting instrumentation. Do not call repeatedly or in CI — '
          'it pollutes your production Crashlytics dashboard.',
      inputSchema: ToolInputSchema(
        properties: {
          'message': JsonSchema.string(
            description: 'Error message to record.',
          ),
          'fatal': JsonSchema.string(
            description: '"true" for fatal error, "false" for non-fatal (default).',
            enumValues: ['true', 'false'],
          ),
        },
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.recordCrashlyticsError',
        p,
      ).then((res) => res.toCallToolResult()),
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

    server.registerTool(
      'read_secure_storage_key',
      description:
          'Read a specific key from FlutterSecureStorage. '
          'Keys matching password/secret/api_key patterns are always redacted.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The key to read.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.readSecureStorageKey',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
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
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.setSecureStorageKey',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'delete_secure_storage_key',
      description:
          '⚠ DESTRUCTIVE — Delete a specific key from FlutterSecureStorage. '
          'To wipe ALL keys, omit "key" and pass confirm="DELETE_ALL". '
          'Deletion cannot be undone.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key to delete. Omit to clear ALL secure storage (requires confirm).',
          ),
          'confirm': JsonSchema.string(
            description:
                'Required when wiping all keys (no "key" given). '
                'Must be exactly "DELETE_ALL" to proceed.',
          ),
        },
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.deleteSecureStorageKey',
        {
          if (p['key'] != null) 'key': p['key'].toString(),
          if (p['confirm'] != null) 'confirm': p['confirm'].toString(),
        },
      ).then((res) => res.toCallToolResult()),
    );
  }
}
