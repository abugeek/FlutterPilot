import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// FlutterPilot plugin that exposes Firebase services state to AI agents.
///
/// Provides visibility into:
/// - **Crashlytics**: crash collection status, forced crashes for testing
/// - **Analytics**: log events, get current screen, observer reference
/// - **Performance**: custom traces, metrics, collection status
/// - **Messaging**: FCM token, notification permission status, topic subscriptions
///
/// ## Setup
/// ```dart
/// await Firebase.initializeApp();
/// FirebasePilotInspector.register(
///   crashlytics: FirebaseCrashlytics.instance,
///   analytics: FirebaseAnalytics.instance,
///   performance: FirebasePerformance.instance,
///   messaging: FirebaseMessaging.instance,
/// );
/// ```
///
/// All parameters are optional — register only the services you use.
class FirebasePilotInspector {
  FirebasePilotInspector._();

  static bool _registered = false;
  static FirebaseCrashlytics? _crashlytics;
  static FirebaseAnalytics? _analytics;
  static FirebasePerformance? _performance;
  static FirebaseMessaging? _messaging;
  static final List<Map<String, dynamic>> _analyticsLog = [];
  static final Map<String, Trace> _activeTraces = {};
  static const int _maxAnalyticsLog = 200;

  /// Registers Firebase services with FlutterPilot.
  ///
  /// All parameters are optional. Only registered services will have
  /// their extensions available.
  static void register({
    FirebaseCrashlytics? crashlytics,
    FirebaseAnalytics? analytics,
    FirebasePerformance? performance,
    FirebaseMessaging? messaging,
  }) {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] FirebasePilotInspector.register called before '
        'FlutterPilot.initialize(). Extensions will not be registered.',
      );
      return;
    }
    if (_registered) return;
    _registered = true;
    _crashlytics = crashlytics;
    _analytics = analytics;
    _performance = performance;
    _messaging = messaging;
    _registerExtensions();
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _analyticsLog.clear();
    for (final trace in _activeTraces.values) {
      trace.stop();
    }
    _activeTraces.clear();
    _crashlytics = null;
    _analytics = null;
    _performance = null;
    _messaging = null;
    _registered = false;
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getFirebaseStatus ------------------------------------
    registerExtension('ext.flutterpilot.getFirebaseStatus', (
      method,
      parameters,
    ) async {
      final result = <String, dynamic>{
        'crashlytics': _crashlytics != null
            ? {
                'available': true,
                'isCrashlyticsCollectionEnabled':
                    _crashlytics!.isCrashlyticsCollectionEnabled,
              }
            : {'available': false},
        'analytics': {'available': _analytics != null},
        'performance': _performance != null
            ? {
                'available': true,
                'isPerformanceCollectionEnabled':
                    _performance!.isPerformanceCollectionEnabled(),
              }
            : {'available': false},
        'messaging': {'available': _messaging != null},
      };

      if (_messaging != null) {
        try {
          final settings = await _messaging!.getNotificationSettings();
          result['messaging'] = {
            'available': true,
            'authorizationStatus': settings.authorizationStatus.name,
            'alert': settings.alert.name,
            'badge': settings.badge.name,
            'sound': settings.sound.name,
          };
        } catch (_) {
          // Permission check may fail on some platforms
        }
      }

      return ServiceExtensionResponse.result(json.encode(result));
    });

    // -- ext.flutterpilot.getFcmToken -----------------------------------------
    registerExtension('ext.flutterpilot.getFcmToken', (
      method,
      parameters,
    ) async {
      if (_messaging == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FirebaseMessaging not registered.',
        );
      }

      try {
        final token = await _messaging!.getToken();
        return ServiceExtensionResponse.result(json.encode({
          'token': token != null
              ? '${token.substring(0, (token.length > 20 ? 20 : token.length))}...'
              : null,
          'tokenLength': token?.length,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to get FCM token: $e',
        );
      }
    });

    // -- ext.flutterpilot.logAnalyticsEvent ------------------------------------
    registerExtension('ext.flutterpilot.logAnalyticsEvent', (
      method,
      parameters,
    ) async {
      if (_analytics == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FirebaseAnalytics not registered.',
        );
      }

      final name = parameters['name'];
      if (name == null || name.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing "name" parameter.',
        );
      }

      final paramsJson = parameters['params'];
      Map<String, Object>? eventParams;
      if (paramsJson != null) {
        try {
          final decoded = json.decode(paramsJson);
          if (decoded is Map) {
            eventParams = decoded.map((k, v) => MapEntry(k.toString(), v as Object));
          }
        } catch (_) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'Invalid JSON for "params" parameter.',
          );
        }
      }

      try {
        await _analytics!.logEvent(name: name, parameters: eventParams);
        _analyticsLog.add({
          'event': name,
          'params': eventParams,
          'timestamp': DateTime.now().toIso8601String(),
        });
        while (_analyticsLog.length > _maxAnalyticsLog) {
          _analyticsLog.removeAt(0);
        }
        return ServiceExtensionResponse.result(json.encode({
          'status': 'success',
          'event': name,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to log event: $e',
        );
      }
    });

    // -- ext.flutterpilot.getAnalyticsLog -------------------------------------
    registerExtension('ext.flutterpilot.getAnalyticsLog', (
      method,
      parameters,
    ) async {
      final limitStr = parameters['limit'];
      final limit = (int.tryParse(limitStr ?? '') ?? _maxAnalyticsLog)
          .clamp(1, _maxAnalyticsLog);
      final entries = _analyticsLog.length > limit
          ? _analyticsLog.sublist(_analyticsLog.length - limit)
          : _analyticsLog;

      return ServiceExtensionResponse.result(json.encode({
        'events': entries,
        'count': entries.length,
        'total': _analyticsLog.length,
      }));
    });

    // -- ext.flutterpilot.startPerformanceTrace --------------------------------
    registerExtension('ext.flutterpilot.startPerformanceTrace', (
      method,
      parameters,
    ) async {
      if (_performance == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FirebasePerformance not registered.',
        );
      }

      final name = parameters['name'];
      if (name == null || name.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing "name" parameter.',
        );
      }

      if (_activeTraces.containsKey(name)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Trace "$name" is already running. Stop it first.',
        );
      }

      try {
        final trace = _performance!.newTrace(name);
        await trace.start();
        _activeTraces[name] = trace;
        return ServiceExtensionResponse.result(json.encode({
          'status': 'started',
          'trace': name,
          'activeTraces': _activeTraces.keys.toList(),
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to start trace: $e',
        );
      }
    });

    // -- ext.flutterpilot.stopPerformanceTrace ---------------------------------
    registerExtension('ext.flutterpilot.stopPerformanceTrace', (
      method,
      parameters,
    ) async {
      final name = parameters['name'];
      if (name == null || name.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing "name" parameter.',
        );
      }

      final trace = _activeTraces.remove(name);
      if (trace == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No active trace named "$name".',
        );
      }

      try {
        await trace.stop();
        return ServiceExtensionResponse.result(json.encode({
          'status': 'stopped',
          'trace': name,
          'activeTraces': _activeTraces.keys.toList(),
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to stop trace: $e',
        );
      }
    });

    // -- ext.flutterpilot.recordCrashlyticsError --------------------------------
    registerExtension('ext.flutterpilot.recordCrashlyticsError', (
      method,
      parameters,
    ) async {
      if (_crashlytics == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'FirebaseCrashlytics not registered.',
        );
      }

      final message = parameters['message'] ?? 'FlutterPilot test error';
      final fatal = parameters['fatal'] == 'true';

      try {
        await _crashlytics!.recordError(
          Exception(message),
          null,
          reason: 'FlutterPilot: $message',
          fatal: fatal,
        );
        return ServiceExtensionResponse.result(json.encode({
          'status': 'recorded',
          'message': message,
          'fatal': fatal,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to record error: $e',
        );
      }
    });
  }
}
