import 'dart:developer';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A Dio [Interceptor] that captures HTTP traffic for FlutterPilot.
///
/// Logs requests, responses, and errors, exposing them via the
/// `ext.flutterpilot.getNetworkLogs` service extension. Keeps the last 50
/// entries in a rolling buffer.
///
/// ## Setup
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(DioPilotInterceptor());
/// ```
class DioPilotInterceptor extends Interceptor {
  static final List<Map<String, dynamic>> _logs = [];
  static bool _initialized = false;

  DioPilotInterceptor() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  void _registerExtension() {
    if (!FlutterPilot.isInitialized) {
      debugPrint('FlutterPilot: DioPilotInterceptor registered before '
          'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.');
    }

    registerExtension('ext.flutterpilot.getNetworkLogs', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({'logs': _logs}));
    });
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _addLog({'type': 'request', 'method': options.method, 'uri': options.uri.toString(), 'timestamp': DateTime.now().toIso8601String()});
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _addLog({'type': 'response', 'statusCode': response.statusCode, 'uri': response.requestOptions.uri.toString(), 'timestamp': DateTime.now().toIso8601String()});
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _addLog({'type': 'error', 'statusCode': err.response?.statusCode, 'uri': err.requestOptions.uri.toString(), 'message': err.message, 'timestamp': DateTime.now().toIso8601String()});
    super.onError(err, handler);
  }

  void _addLog(Map<String, dynamic> log) {
    _logs.add(log);
    if (_logs.length > 50) _logs.removeAt(0);
  }
}
