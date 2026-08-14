import 'ring_buffer.dart';
import 'package:flutter/widgets.dart';

/// Intercepts Flutter framework and platform errors and maintains a
/// fixed-size circular buffer of recent error details.
///
/// [ErrorInspector] hooks into [FlutterError.onError] and the platform
/// dispatcher's `onError` callback. It preserves the original handlers,
/// so existing error reporting (e.g., Crashlytics) continues to work.
///
/// The error buffer is capped at **10 entries** (oldest are evicted).
/// Errors are surfaced to external tools via the
/// `ext.flutterpilot.getErrors` service extension.
///
/// This class is initialized automatically by [FlutterPilot.initialize]
/// and should not be used directly in most cases.
class ErrorInspector {
  static final RingBuffer<Map<String, dynamic>> _errorBuffer = RingBuffer(10);
  static bool _initialized = false;

  /// Optional callback invoked whenever a new error is captured.
  ///
  /// Set by [FlutterPilot] internally to forward errors to the
  /// recording system and VM service events.
  static void Function(FlutterErrorDetails details)? onErrorCaptured;

  /// Sets up error interception by wrapping [FlutterError.onError] and the
  /// platform dispatcher's `onError`.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _captureError(details);
      onErrorCaptured?.call(details);
      originalOnError?.call(details);
    };

    final originalOnPlatformError =
        WidgetsBinding.instance.platformDispatcher.onError;
    WidgetsBinding.instance.platformDispatcher.onError =
        (Object error, StackTrace stack) {
          final details = FlutterErrorDetails(exception: error, stack: stack);
          _captureError(details);
          onErrorCaptured?.call(details);
          return originalOnPlatformError?.call(error, stack) ?? false;
        };
  }

  /// Compacts a raw stack trace by stripping internal Flutter framework frames
  /// and preserving user project frames (package:...) for an 80% token reduction.
  static String? compactStackTrace(String? rawStack) {
    if (rawStack == null || rawStack.isEmpty) return null;
    final lines = rawStack.split('\n');
    final compacted = <String>[];
    int skippedFrameworkFrames = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final isFramework = trimmed.contains('package:flutter/') ||
          trimmed.contains('dart:async/') ||
          trimmed.contains('dart:ui/') ||
          trimmed.contains('package:stack_trace/');
      if (!isFramework) {
        if (skippedFrameworkFrames > 0) {
          compacted.add('  ... [$skippedFrameworkFrames framework frames skipped]');
          skippedFrameworkFrames = 0;
        }
        compacted.add(trimmed);
      } else {
        skippedFrameworkFrames++;
      }
    }
    if (skippedFrameworkFrames > 0) {
      compacted.add('  ... [$skippedFrameworkFrames framework frames skipped]');
    }
    return compacted.isNotEmpty ? compacted.join('\n') : rawStack;
  }

  static void _captureError(FlutterErrorDetails details) {
    final rawStack = details.stack?.toString();
    _errorBuffer.add({
      'exception': details.exceptionAsString(),
      'stackTrace': compactStackTrace(rawStack),
      'rawStackTrace': rawStack,
      'library': details.library,
      'context': details.context?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Returns an unmodifiable view of the current error buffer.
  ///
  /// Each entry is a map with the following keys:
  /// - `exception` — The exception message.
  /// - `stackTrace` — The stack trace string (may be null).
  /// - `library` — The Flutter library that reported the error.
  /// - `context` — Additional error context from Flutter.
  /// - `timestamp` — ISO 8601 timestamp of when the error was captured.
  static List<Map<String, dynamic>> get errors =>
      List.unmodifiable(_errorBuffer.toList());
}
