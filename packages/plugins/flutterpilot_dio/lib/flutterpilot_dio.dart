import 'dart:developer';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// Network conditions that can be simulated by [DioPilotInterceptor].
enum NetworkCondition {
  /// Normal network — no artificial delay or errors.
  normal,

  /// Simulates a slow 3G connection (~1500ms latency per request).
  slow3g,

  /// Simulates a fast 4G connection (~100ms latency per request).
  fast4g,

  /// Simulates complete offline — every request fails with a connection error.
  offline,
}

/// A Dio [Interceptor] that captures HTTP traffic for FlutterPilot.
///
/// Logs requests, responses, and errors, exposing them via the
/// `ext.flutterpilot.getNetworkLogs` service extension. Keeps the last
/// [maxLogEntries] entries in a rolling buffer.
///
/// Also supports network condition simulation via
/// `ext.flutterpilot.simulateNetwork`.
///
/// ## Setup
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(DioPilotInterceptor());
/// ```
class DioPilotInterceptor extends Interceptor {
  static final List<Map<String, dynamic>> _logs = [];
  static bool _initialized = false;
  static NetworkCondition _condition = NetworkCondition.normal;
  static final Map<String, Map<String, dynamic>> _mocks = {};
  static const int maxLogEntries = 100;
  static const int _maxDelayMs = 60000;

  DioPilotInterceptor() {
    if (!_initialized) {
      _initialized = true;
      _registerExtensions();
    }
  }

  void _registerExtensions() {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: DioPilotInterceptor registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    registerExtension('ext.flutterpilot.getNetworkLogs', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(json.encode({'logs': _logs}));
    });

    registerExtension('ext.flutterpilot.simulateNetwork', (
      method,
      parameters,
    ) async {
      final conditionStr = parameters['condition'];
      final NetworkCondition condition;
      switch (conditionStr) {
        case 'offline':
          condition = NetworkCondition.offline;
        case 'slow_3g':
          condition = NetworkCondition.slow3g;
        case 'fast_4g':
          condition = NetworkCondition.fast4g;
        case 'normal':
          condition = NetworkCondition.normal;
        default:
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'condition must be: normal | slow_3g | fast_4g | offline',
          );
      }
      _condition = condition;
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'condition': conditionStr}),
      );
    });

    // -- ext.flutterpilot.addHttpMock ------------------------------------------
    registerExtension('ext.flutterpilot.addHttpMock', (
      method,
      parameters,
    ) async {
      final urlPattern = parameters['urlPattern'];
      final statusCodeStr = parameters['statusCode'];
      final body = parameters['body'];

      if (urlPattern == null || statusCodeStr == null || body == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing urlPattern, statusCode, or body',
        );
      }
      final statusCode = int.tryParse(statusCodeStr);
      if (statusCode == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'statusCode must be an integer',
        );
      }
      final delayMs = (int.tryParse(parameters['delayMs'] ?? '0') ?? 0).clamp(
        0,
        _maxDelayMs,
      );
      _mocks[urlPattern] = {
        'statusCode': statusCode,
        'body': body,
        'delayMs': delayMs,
      };
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'urlPattern': urlPattern,
          'statusCode': statusCode,
        }),
      );
    });

    // -- ext.flutterpilot.clearHttpMocks ---------------------------------------
    registerExtension('ext.flutterpilot.clearHttpMocks', (
      method,
      parameters,
    ) async {
      final urlPattern = parameters['urlPattern'];
      if (urlPattern != null) {
        _mocks.remove(urlPattern);
      } else {
        _mocks.clear();
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'remaining': _mocks.length}),
      );
    });
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    _onRequestAsync(options, handler);
  }

  Future<void> _onRequestAsync(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    _addLog({
      'type': 'request',
      'method': options.method,
      'uri': options.uri.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Check mocks first — mocks take priority over network condition simulation.
    final uri = options.uri.toString();
    MapEntry<String, Map<String, dynamic>>? mockEntry;
    for (final entry in _mocks.entries) {
      if (uri.contains(entry.key)) {
        mockEntry = entry;
        break;
      }
    }
    if (mockEntry != null) {
      final mock = mockEntry.value;
      final delayMs = ((mock['delayMs'] as int?) ?? 0).clamp(0, _maxDelayMs);
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      dynamic decodedBody;
      try {
        decodedBody = json.decode(mock['body'] as String);
      } catch (_) {
        decodedBody = mock['body'];
      }
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: mock['statusCode'] as int,
          data: decodedBody,
        ),
      );
      return;
    }

    // Capture condition snapshot to avoid race with simulateNetwork
    final condition = _condition;
    switch (condition) {
      case NetworkCondition.offline:
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: '[FlutterPilot] Network simulated offline',
          ),
          true,
        );
        return;
      case NetworkCondition.slow3g:
        await Future.delayed(const Duration(milliseconds: 1500));
      case NetworkCondition.fast4g:
        await Future.delayed(const Duration(milliseconds: 100));
      case NetworkCondition.normal:
        break;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _addLog({
      'type': 'response',
      'statusCode': response.statusCode,
      'uri': response.requestOptions.uri.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _addLog({
      'type': 'error',
      'statusCode': err.response?.statusCode,
      'uri': err.requestOptions.uri.toString(),
      'message': err.message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    super.onError(err, handler);
  }

  void _addLog(Map<String, dynamic> log) {
    if (_logs.length >= maxLogEntries) _logs.removeAt(0);
    _logs.add(log);
  }
}
