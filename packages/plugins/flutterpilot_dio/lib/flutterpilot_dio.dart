import 'dart:developer';
import 'dart:convert';
import 'package:dio/dio.dart';

/// A Dio interceptor that captures network requests and responses for FlutterPilot.
class DioPilotInterceptor extends Interceptor {
  static final List<Map<String, dynamic>> _logs = [];
  static bool _extensionRegistered = false;

  DioPilotInterceptor() {
    if (!_extensionRegistered) {
      _extensionRegistered = true;
      _registerExtension();
    }
  }

  void _registerExtension() {
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
