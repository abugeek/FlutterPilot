import 'package:flutter/widgets.dart';

/// Intercepts and buffers errors for FlutterPilot.
class ErrorInspector {
  static final List<Map<String, dynamic>> _errorBuffer = [];
  static bool _initialized = false;
  
  /// Callback triggered when an error is captured.
  static void Function(FlutterErrorDetails details)? onErrorCaptured;

  /// Initializes error interception. Safe to call multiple times —
  /// subsequent calls are no-ops.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _captureError(details);
      onErrorCaptured?.call(details);
      originalOnError?.call(details);
    };

    final originalOnPlatformError = WidgetsBinding.instance.platformDispatcher.onError;
    WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) {
      final details = FlutterErrorDetails(exception: error, stack: stack);
      _captureError(details);
      onErrorCaptured?.call(details);
      return originalOnPlatformError?.call(error, stack) ?? false;
    };
  }

  static void _captureError(FlutterErrorDetails details) {
    _errorBuffer.add({
      'exception': details.exceptionAsString(),
      'stackTrace': details.stack?.toString(),
      'library': details.library,
      'context': details.context?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_errorBuffer.length > 10) _errorBuffer.removeAt(0);
  }

  /// Retrieves the current error buffer.
  static List<Map<String, dynamic>> get errors => List.unmodifiable(_errorBuffer);
}
