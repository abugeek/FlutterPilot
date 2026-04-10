import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// FlutterPilot plugin that exposes Supabase state to AI agents.
///
/// Provides visibility into:
/// - **Auth state**: current user, session, JWT expiry, auth events
/// - **Realtime**: active channel subscriptions and their status
/// - **Database**: query Supabase tables directly (read-only, limit-capped)
/// - **Auth actions**: sign out, refresh session (for testing)
///
/// ## Setup
/// ```dart
/// await Supabase.initialize(url: '...', anonKey: '...');
/// SupabasePilotInspector.register(Supabase.instance.client);
/// ```
class SupabasePilotInspector {
  SupabasePilotInspector._();

  static bool _registered = false;
  static SupabaseClient? _client;
  static final List<Map<String, dynamic>> _authEvents = [];
  static StreamSubscription<AuthState>? _authSub;
  static const int _maxAuthEvents = 50;

  /// Registers a [SupabaseClient] with FlutterPilot.
  ///
  /// Call once after [Supabase.initialize] resolves:
  /// ```dart
  /// SupabasePilotInspector.register(Supabase.instance.client);
  /// ```
  static void register(SupabaseClient client) {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] SupabasePilotInspector.register called before '
        'FlutterPilot.initialize(). Extensions will not be registered.',
      );
      return;
    }
    if (_registered) return;
    _registered = true;
    _client = client;
    _listenAuthEvents();
    _registerExtensions();
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _authSub?.cancel();
    _authSub = null;
    _authEvents.clear();
    _client = null;
    _registered = false;
  }

  static void _listenAuthEvents() {
    _authSub = _client?.auth.onAuthStateChange.listen((data) {
      _authEvents.add({
        'event': data.event.name,
        'timestamp': DateTime.now().toIso8601String(),
        'hasSession': data.session != null,
      });
      while (_authEvents.length > _maxAuthEvents) {
        _authEvents.removeAt(0);
      }
    });
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getSupabaseAuth --------------------------------------
    _safeRegisterExtension('ext.flutterpilot.getSupabaseAuth', (
      method,
      parameters,
    ) async {
      final client = _client;
      if (client == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'SupabaseClient not registered.',
        );
      }

      final session = client.auth.currentSession;
      final user = client.auth.currentUser;
      final showSensitive = parameters['showSensitive'] == 'true';

      final result = <String, dynamic>{
        'isAuthenticated': user != null,
        'authEvents': _authEvents,
      };

      if (user != null) {
        result['user'] = {
          'id': showSensitive ? user.id : '***redacted***',
          'email': showSensitive ? user.email : _redact(user.email),
          'phone': showSensitive ? user.phone : _redact(user.phone),
          'role': user.role,
          'createdAt': user.createdAt,
          'lastSignInAt': user.lastSignInAt,
          'appMetadata': user.appMetadata,
          'userMetadata': showSensitive ? user.userMetadata : '***redacted***',
          'identities': user.identities?.map((i) => {
            'provider': i.provider,
            'createdAt': i.createdAt,
          }).toList(),
        };
      }

      if (session != null) {
        result['session'] = {
          'accessTokenPrefix': session.accessToken.substring(
            0,
            (session.accessToken.length > 20 ? 20 : session.accessToken.length),
          ) + '...',
          'tokenType': session.tokenType,
          'expiresIn': session.expiresIn,
          'expiresAt': session.expiresAt != null
              ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
                  .toIso8601String()
              : null,
          'isExpired': session.isExpired,
          'refreshTokenPrefix': session.refreshToken != null
              ? '${session.refreshToken!.substring(0, (session.refreshToken!.length > 10 ? 10 : session.refreshToken!.length))}...'
              : null,
        };
      }

      return ServiceExtensionResponse.result(json.encode(result));
    });

    // -- ext.flutterpilot.getSupabaseRealtime ----------------------------------
    _safeRegisterExtension('ext.flutterpilot.getSupabaseRealtime', (
      method,
      parameters,
    ) async {
      final client = _client;
      if (client == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'SupabaseClient not registered.',
        );
      }

      final channels = client.getChannels();
      // ignore: invalid_use_of_internal_member — RealtimeChannel exposes these
      // only as @internal but they are stable and essential for inspection.
      final channelList = channels.map((c) {
        // ignore: invalid_use_of_internal_member
        final topic = c.topic;
        // ignore: invalid_use_of_internal_member
        final isJoined = c.isJoined;
        // ignore: invalid_use_of_internal_member
        final isClosed = c.isClosed;
        return {
          'topic': topic,
          'isJoined': isJoined,
          'isClosed': isClosed,
        };
      }).toList();

      return ServiceExtensionResponse.result(json.encode({
        'channels': channelList,
        'channelCount': channelList.length,
        'hasActiveChannels': channelList.isNotEmpty,
      }));
    });

    // -- ext.flutterpilot.querySupabaseTable -----------------------------------
    _safeRegisterExtension('ext.flutterpilot.querySupabaseTable', (
      method,
      parameters,
    ) async {
      final client = _client;
      if (client == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'SupabaseClient not registered.',
        );
      }

      final table = parameters['table'];
      if (table == null || table.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Required parameter "table" is missing.',
        );
      }

      final limitStr = parameters['limit'] ?? '20';
      final limit = int.tryParse(limitStr) ?? 20;
      if (limit < 1 || limit > 200) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'limit must be between 1 and 200.',
        );
      }

      try {
        var query = client.from(table).select();
        final filter = parameters['filter'];
        if (filter != null && filter.isNotEmpty) {
          // filter format: "column=value" (simple equality only — safe)
          final parts = filter.split('=');
          if (parts.length == 2) {
            query = query.eq(parts[0].trim(), parts[1].trim());
          }
        }
        final data = await query.limit(limit);
        return ServiceExtensionResponse.result(json.encode({
          'table': table,
          'rowCount': (data as List).length,
          'rows': data,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Query failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.supabaseSignOut --------------------------------------
    _safeRegisterExtension('ext.flutterpilot.supabaseSignOut', (
      method,
      parameters,
    ) async {
      final client = _client;
      if (client == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'SupabaseClient not registered.',
        );
      }

      try {
        final scope = parameters['scope'] ?? 'local';
        switch (scope) {
          case 'global':
            await client.auth.signOut(scope: SignOutScope.global);
          case 'others':
            await client.auth.signOut(scope: SignOutScope.others);
          default:
            await client.auth.signOut(scope: SignOutScope.local);
        }
        return ServiceExtensionResponse.result(json.encode({
          'status': 'success',
          'scope': scope,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Sign out failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.supabaseRefreshSession --------------------------------
    _safeRegisterExtension('ext.flutterpilot.supabaseRefreshSession', (
      method,
      parameters,
    ) async {
      final client = _client;
      if (client == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'SupabaseClient not registered.',
        );
      }

      try {
        final response = await client.auth.refreshSession();
        return ServiceExtensionResponse.result(json.encode({
          'status': 'success',
          'hasSession': response.session != null,
          'hasUser': response.user != null,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Session refresh failed: $e',
        );
      }
    });
  }

  /// Redacts a value for privacy — shows first 2 chars + length hint.
  static String? _redact(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length <= 2) return '***';
    return '${value.substring(0, 2)}***[${value.length} chars]';
  }
}
