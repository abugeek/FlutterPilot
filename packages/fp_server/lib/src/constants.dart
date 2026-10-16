part of '../fp_server.dart';

/// Named constants for buffer sizes, timeouts, and truncation limits.
abstract final class _Constants {
  static const int eventBufferMax = 50;
  static const int debugLogBufferMax = 500;
  static const int eventBufferMaxBytes = 512 * 1024;
  static const int debugLogBufferMaxBytes = 512 * 1024;
  static const int maxScreenshotBaselines = 20;
  static const int maxScreenshotBaselineBytes = 32 * 1024 * 1024;
  static const int maxToolResponseBytes = 512 * 1024;
  static const Duration vmServiceTimeout = Duration(seconds: 10);
  static const Duration extensionCallTimeout = Duration(seconds: 15);

  /// Most error entries `flutterpilot://app/errors` lists before it adds a
  /// truncation note (task 06 §10). Bounding the *items* keeps the encoded JSON
  /// complete and parseable, where cutting the serialized string would not; the
  /// `count`/`beforeReloadCount` totals stay accurate.
  static const int maxResourceErrorItems = 50;

  /// Longest a single error field (exception text or source location) may be,
  /// so a few pathological entries cannot blow the response up.
  static const int maxResourceErrorFieldChars = 600;

  /// Most child keys `flutterpilot://app/widgets/{key}` lists before it reports
  /// the total instead.
  static const int maxResourceChildKeys = 200;

  /// Most navigation-stack entries and matched routes a route template lists.
  static const int maxResourceRouteItems = 100;

  /// Most console entries `flutterpilot://app/logs` renders (newest kept); the
  /// server buffer is smaller, but SDK-buffered lines can add to it.
  static const int maxResourceLogEntries = 500;

  // SQL injection prevention
}
