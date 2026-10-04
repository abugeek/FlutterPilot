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
  static const int maxLogEntries = 500;
  static final RingBuffer<Map<String, dynamic>> _logs = RingBuffer(
    maxLogEntries,
  );
  static bool _initialized = false;
  static NetworkCondition _condition = NetworkCondition.normal;
  static final Map<String, Map<String, dynamic>> _mocks = {};
  static const int _maxDelayMs = 60000;

  static final RegExp _sensitiveKeys = RegExp(
    r'(password|token|secret|auth|bearer|apikey|api_key|credit_card)',
    caseSensitive: false,
  );

  DioPilotInterceptor() {
    register();
  }

  /// Explicitly registers Dio capabilities with FlutterPilot.
  /// Answers requests whose URL contains [urlPattern] with [statusCode] and
  /// [body] (JSON is decoded) instead of the network. What
  /// `mock_http_response` sets, and what tests generated from it call.
  ///
  /// [error] fails them without a response instead, as the network does:
  /// `"timeout"` (the server never answers: a receive timeout) or
  /// `"connection"` (it can't be reached), after [delayMs].
  static void mock(
    String urlPattern, {
    int statusCode = 200,
    String body = '',
    int delayMs = 0,
    String? error,
  }) {
    _mocks[urlPattern] = {
      'statusCode': statusCode,
      'body': body,
      'delayMs': delayMs.clamp(0, _maxDelayMs),
      'error': ?error,
    };
  }

  /// The failures [mock] can stand in for.
  static const mockErrors = ['timeout', 'connection'];

  /// Removes the mock for [urlPattern], or all of them.
  static void clearMocks([String? urlPattern]) {
    if (urlPattern != null) {
      _mocks.remove(urlPattern);
    } else {
      _mocks.clear();
    }
  }

  static void register() {
    if (!_initialized) {
      _initialized = true;
      _registerExtensions();
      // A scenario loaded with a hot restart: its mocks answer the app's
      // very first requests.
      final pending = FlutterPilot.takeRestartData('httpMocks');
      if (pending is List) {
        for (final m in pending.whereType<Map>()) {
          mock(
            '${m['urlPattern']}',
            statusCode: (m['statusCode'] as num?)?.toInt() ?? 200,
            body: '${m['body'] ?? ''}',
            delayMs: (m['delayMs'] as num?)?.toInt() ?? 0,
            error: m['error'] as String?,
          );
        }
      }
    }
  }

  static dynamic _sanitizeData(dynamic data, {int maxLen = 2048}) {
    if (data == null) return null;
    try {
      if (data is Map) {
        final sanitized = <String, dynamic>{};
        for (final entry in data.entries) {
          final k = entry.key.toString();
          if (_sensitiveKeys.hasMatch(k)) {
            sanitized[k] = '[REDACTED]';
          } else {
            sanitized[k] = _sanitizeData(entry.value, maxLen: maxLen);
          }
        }
        return sanitized;
      }
      if (data is List) {
        return data
            .take(20)
            .map((e) => _sanitizeData(e, maxLen: maxLen))
            .toList();
      }
      // Text bodies (form data, raw JSON) may carry credentials too.
      final str = FlutterPilot.redactText(data.toString());
      if (str.length > maxLen) {
        return '${str.substring(0, maxLen)}... [Truncated]';
      }
      return str;
    } catch (_) {
      return '[Unparseable payload]';
    }
  }

  static void _registerExtensions() {
    FlutterPilot.registerCapability(
      'dio',
      version: '1',
      extensions: [
        'ext.flutterpilot.getNetworkLogs',
        'ext.flutterpilot.simulateNetwork',
        'ext.flutterpilot.addHttpMock',
        'ext.flutterpilot.clearHttpMocks',
      ],
      mutating: true,
    );
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
      return ServiceExtensionResponse.result(
        json.encode({'logs': _logs.toList()}),
      );
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
      final error = parameters['error'];
      final statusCodeStr =
          parameters['statusCode'] ?? (error == null ? null : '0');
      final body = parameters['body'] ?? (error == null ? null : '');

      if (urlPattern == null || statusCodeStr == null || body == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing urlPattern, statusCode, or body',
        );
      }
      if (error != null && !mockErrors.contains(error)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'error must be one of: ${mockErrors.join(', ')}',
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
      mock(
        urlPattern,
        statusCode: statusCode,
        body: body,
        delayMs: delayMs,
        error: error,
      );
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'urlPattern': urlPattern,
          // Not "error": the server reads that key as the call failing.
          if (error == null) 'statusCode': statusCode else 'failsWith': error,
        }),
      );
    });

    // -- ext.flutterpilot.getHttpMocks ----------------------------------------
    registerExtension('ext.flutterpilot.getHttpMocks', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'mocks': [
            for (final e in _mocks.entries) {'urlPattern': e.key, ...e.value},
          ],
        }),
      );
    });

    // -- ext.flutterpilot.clearHttpMocks ---------------------------------------
    registerExtension('ext.flutterpilot.clearHttpMocks', (
      method,
      parameters,
    ) async {
      clearMocks(parameters['urlPattern']);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'remaining': _mocks.length}),
      );
    });
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _onRequestAsync(options, handler);
  }

  Future<void> _onRequestAsync(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final reqBody = _sanitizeData(options.data, maxLen: 2048);
    _addLog({
      'type': 'request',
      'method': options.method,
      'uri': FlutterPilot.redactText(options.uri.toString()),
      if (reqBody != null) 'body': reqBody,
      if (options.contentType != null) 'contentType': options.contentType,
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
      options.extra['flutterpilot_mocked'] = true;
      final error = mock['error'];
      if (error != null) {
        handler.reject(
          error == 'timeout'
              ? DioException.receiveTimeout(
                  timeout: options.receiveTimeout ?? Duration.zero,
                  requestOptions: options,
                )
              : DioException.connectionError(
                  requestOptions: options,
                  reason: '[FlutterPilot] mocked connection error',
                ),
          true, // run onError so the mocked failure is logged too
        );
        return;
      }
      dynamic decodedBody;
      try {
        decodedBody = json.decode(mock['body'] as String);
      } catch (_) {
        decodedBody = mock['body'];
      }
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: mock['statusCode'] as int,
        data: decodedBody,
        extra: {'flutterpilot_mocked': true},
      );
      // A status the app's Dio rejects (5xx, 404 by default) must fail the
      // way the server's would: resolve() skips validateStatus, and the app
      // got a "successful" 500 with the error body as its data.
      if (!options.validateStatus(response.statusCode)) {
        handler.reject(
          DioException.badResponse(
            statusCode: response.statusCode!,
            requestOptions: options,
            response: response,
          ),
          true, // run onError so the mocked failure is logged too
        );
        return;
      }
      handler.resolve(
        response,
        true, // run onResponse so mocked responses are logged too
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
    final isMocked =
        response.requestOptions.extra['flutterpilot_mocked'] == true ||
        response.extra['flutterpilot_mocked'] == true;
    final resBody = _sanitizeData(response.data, maxLen: 4096);
    _addLog({
      'type': 'response',
      'statusCode': response.statusCode,
      'uri': FlutterPilot.redactText(response.requestOptions.uri.toString()),
      if (isMocked) 'mocked': true,
      if (resBody != null) 'body': resBody,
      'timestamp': DateTime.now().toIso8601String(),
    });
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final errBody = _sanitizeData(err.response?.data, maxLen: 2048);
    _addLog({
      'type': 'error',
      'statusCode': err.response?.statusCode,
      'uri': FlutterPilot.redactText(err.requestOptions.uri.toString()),
      'message': err.message == null
          ? null
          : FlutterPilot.redactText(err.message!),
      'errorType': err.type.name,
      // A mocked timeout or connection error has no response to carry it.
      if (err.response?.extra['flutterpilot_mocked'] == true ||
          err.requestOptions.extra['flutterpilot_mocked'] == true)
        'mocked': true,
      if (errBody != null) 'body': errBody,
      'timestamp': DateTime.now().toIso8601String(),
    });
    super.onError(err, handler);
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _logs.clear();
    _mocks.clear();
    _condition = NetworkCondition.normal;
    _initialized = false;
  }

  void _addLog(Map<String, dynamic> log) {
    _logs.add(log);
  }
}
