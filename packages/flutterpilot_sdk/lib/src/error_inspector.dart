import 'ring_buffer.dart';
import 'package:flutter/widgets.dart';
import 'redaction.dart';

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

  /// Manually records an uncaught error and stack trace into the buffer.
  static void recordError(Object error, StackTrace? stack) {
    final details = FlutterErrorDetails(exception: error, stack: stack);
    _captureError(details);
    onErrorCaptured?.call(details);
  }

  /// A frame in Flutter, the Dart SDK, FlutterPilot or stack_trace, in the
  /// VM format (`#3  f (package:flutter/…:1:2)`) or the web one
  /// (`package:flutter/… 1:2  f`, `dart-sdk/lib/… 3:4  g`).
  static final _frameworkFrame = RegExp(
    r'(^|\()(package:flutter/|package:flutterpilot|package:stack_trace/|'
    r'dart:|dart-sdk/)',
  );

  static final _webFrame = RegExp(r'^(\S+\.dart) (\d+):(\d+)\s+(.*)$');

  /// Compacts a raw stack trace to the app's own frames: Flutter, the Dart
  /// SDK (`dart:`), FlutterPilot itself (it is on the stack when an agent's
  /// tap triggers the error) and async-gap markers are counted, not shown.
  static String? compactStackTrace(String? rawStack) {
    if (rawStack == null || rawStack.isEmpty) return null;
    final lines = rawStack.split('\n');
    final compacted = <String>[];
    int skippedFrameworkFrames = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final isFramework =
          trimmed == '<asynchronous suspension>' ||
          _frameworkFrame.hasMatch(trimmed);
      if (!isFramework) {
        if (skippedFrameworkFrames > 0) {
          compacted.add(
            '  ... [$skippedFrameworkFrames framework frames skipped]',
          );
          skippedFrameworkFrames = 0;
        }
        // Web frames ("package:app/main.dart 12:5  f") in the VM's form,
        // so an app frame always reads "f (package:app/main.dart:12:5)".
        final web = _webFrame.firstMatch(trimmed);
        compacted.add(
          web == null ? trimmed : '${web[4]} (${web[1]}:${web[2]}:${web[3]})',
        );
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
      // An exception message may quote a URL or body with credentials.
      'exception': Redaction.text(details.exceptionAsString()),
      'stackTrace': compactStackTrace(rawStack),
      'rawStackTrace': rawStack,
      'library': details.library,
      'context': details.context?.toString(),
      'widget': _culpritWidget(details),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Flutter's "The relevant error-causing widget was: Row file:///…:24:17"
  /// line — for layout errors the stack is framework-only, so this is the
  /// only pointer to the user's source.
  static String? _culpritWidget(FlutterErrorDetails details) {
    try {
      final lines = details.toString().split('\n');
      final i = lines.indexWhere(
        (l) => l.contains('relevant error-causing widget was'),
      );
      if (i < 0) return null;
      final text = lines
          .skip(i + 1)
          .take(3)
          .takeWhile((l) => l.trim().isNotEmpty)
          .map((l) => l.trim())
          .join(' ');
      // "Row Row:file:///…/app/lib/main.dart:81:44" → "Row (lib/main.dart:81:44)"
      final source = RegExp(
        r'file://\S*/((?:lib|test|bin|integration_test)/\S+?:\d+:\d+)',
      ).firstMatch(text)?.group(1);
      if (source == null) return text;
      return '${text.split(RegExp(r'[\s:]')).first} ($source)';
    } catch (_) {
      return null;
    }
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
