import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FlutterPilot plugin that exposes Supabase state to AI agents.
///
/// Provides visibility into:
/// - **Auth state**: current user, session, JWT expiry, auth events
/// - **Realtime**: active channel subscriptions and their status
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
    registerExtension('ext.flutterpilot.getSupabaseAuth', (
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
    registerExtension('ext.flutterpilot.getSupabaseRealtime', (
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
      final channelCount = channels.length;

      return ServiceExtensionResponse.result(json.encode({
        'channelCount': channelCount,
        'hasActiveChannels': channelCount > 0,
      }));
    });

    // -- ext.flutterpilot.supabaseSignOut --------------------------------------
    registerExtension('ext.flutterpilot.supabaseSignOut', (
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
    registerExtension('ext.flutterpilot.supabaseRefreshSession', (
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
