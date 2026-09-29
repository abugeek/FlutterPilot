part of '../flutterpilot_server.dart';

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

  // SQL injection prevention
}
