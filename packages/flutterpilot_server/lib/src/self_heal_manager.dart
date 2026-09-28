import 'dart:async';
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';

final _log = logging.Logger('SelfHealManager');

/// Represents a structured diagnostic report of an application crash.
class CrashReport {
  final String timestamp;
  final String exception;
  final dynamic errorData;
  final dynamic riverpodData;
  final dynamic blocData;
  final dynamic networkData;
  final dynamic navigationData;
  final dynamic widgetTreeData;

  CrashReport({
    required this.timestamp,
    required this.exception,
    this.errorData,
    this.riverpodData,
    this.blocData,
    this.networkData,
    this.navigationData,
    this.widgetTreeData,
  });

  /// Formats the report as a compact Markdown string (<4KB budget) for AI agents.
  /// Only the crashing error's compacted stack — the full error list and
  /// raw stacks made reports ~40 KB. Other errors are one get_errors away.
  String? _crashStack(dynamic data) {
    final errors = data is Map ? data['errors'] : null;
    if (errors is! List || errors.isEmpty) return null;
    Object? match = errors.last;
    for (final e in errors.reversed) {
      if (e is Map && e['exception']?.toString() == exception) {
        match = e;
        break;
      }
    }
    if (match is! Map) return null;
    final lines = (match['stackTrace'] ?? '').toString().split('\n');
    return [
      if (match['widget'] != null) 'Widget: ${match['widget']}',
      ...lines.take(12),
    ].join('\n');
  }

  String toMarkdown() {
    final buffer = StringBuffer()..writeln('# 🚨 Critical App Crash Report');
    buffer.writeln('\n**Timestamp:** $timestamp');
    buffer.writeln('\n## Exception\n$exception');

    _addSection(buffer, 'Recent Errors', _crashStack(errorData) ?? errorData);
    _addSection(buffer, 'Riverpod State', riverpodData);
    _addSection(buffer, 'Bloc State', blocData);
    _addSection(buffer, 'Network Logs', networkData);
    _addSection(buffer, 'Navigation Stack', navigationData);
    _addSection(buffer, 'Widget Tree Snippet', _truncateTree(widgetTreeData));

    buffer.writeln('\n\n---');
    buffer.writeln(
      '\n**DIRECTIVE FOR AI:** Analyze the stack trace and states above. Propose a code fix, apply it using your filesystem tools, and call the `hot_reload` tool to verify.',
    );

    return buffer.toString();
  }

  void _addSection(StringBuffer buffer, String title, dynamic data) {
    buffer.writeln('\n## $title');
    if (data == null || (data is String && (data == 'N/A' || data.isEmpty))) {
      buffer.writeln('No data available.');
    } else {
      final str = data.toString();
      final clipped = str.length > 2000
          ? '${str.substring(0, 2000)}... [Truncated]'
          : str;
      buffer.writeln('```json\n$clipped\n```');
    }
  }

  dynamic _truncateTree(dynamic tree) {
    if (tree == null) return null;
    final str = tree.toString();
    if (str.length > 2000) return '${str.substring(0, 2000)}... [Truncated]';
    return str;
  }
}

/// Manages the Self-Heal lifecycle and proactive diagnostic reporting.
class SelfHealManager {
  final McpServer server;
  bool isUnstable = false;
  CrashReport? lastCrashReport;
  String? _lastCrashException;
  String? _lastCrashTimestamp;
  String? _lastCrashDeviceId;
  String? get lastCrashDeviceId => _lastCrashDeviceId;
  DateTime? _lastCrashTime;
  String? _lastDebouncedException;

  CrashReport? _cachedReport;
  DateTime? _cachedReportTime;

  SelfHealManager({required this.server});

  /// Handles an error event from the app.
  /// Debounces repeated identical errors within 2s, classifies severity,
  /// and defers diagnostic data collection until [getLatestReport] is called
  /// (or immediately if [callExtension] is provided).
  Future<void> handleCrash({
    required String exception,
    String severity = 'critical',
    String? deviceId,
    Future<dynamic> Function(String extension)? callExtension,
  }) async {
    final now = DateTime.now();
    if (_lastDebouncedException == exception &&
        _lastCrashTime != null &&
        now.difference(_lastCrashTime!) < const Duration(seconds: 2)) {
      return; // Debounced repeated error
    }
    _lastDebouncedException = exception;
    _lastCrashTime = now;

    if (severity == 'warning') {
      _log.warning('⚠️ Layout overflow / warning detected: $exception');
      return;
    }

    isUnstable = true;
    _lastCrashException = exception;
    _lastCrashTimestamp = now.toIso8601String();
    _lastCrashDeviceId = deviceId;
    _cachedReport = null;
    _cachedReportTime = null;

    _sendProactiveAlert(exception);

    if (callExtension != null) {
      await getLatestReport(callExtension);
    }
  }

  /// Lazily fetches and constructs the crash report, caching it for 5s.
  Future<CrashReport?> getLatestReport(
    Future<dynamic> Function(String extension) callExtension,
  ) async {
    if (_cachedReport != null &&
        _cachedReportTime != null &&
        DateTime.now().difference(_cachedReportTime!) <
            const Duration(seconds: 5)) {
      return _cachedReport;
    }

    if (_lastCrashException == null && lastCrashReport == null) {
      return null;
    }

    final exception =
        _lastCrashException ?? lastCrashReport?.exception ?? 'Unknown';
    final timestamp = _lastCrashTimestamp ?? DateTime.now().toIso8601String();

    final results = await Future.wait([
      callExtension('ext.flutterpilot.getErrors').catchError((_) => 'N/A'),
      callExtension(
        'ext.flutterpilot.getRiverpodStates',
      ).catchError((_) => 'N/A'),
      callExtension('ext.flutterpilot.getBlocStates').catchError((_) => 'N/A'),
      callExtension('ext.flutterpilot.getNetworkLogs').catchError((_) => 'N/A'),
      callExtension(
        'ext.flutterpilot.getNavigationStack',
      ).catchError((_) => 'N/A'),
      callExtension('ext.flutterpilot.getWidgetTree').catchError((_) => 'N/A'),
    ]);

    final report = CrashReport(
      timestamp: timestamp,
      exception: exception,
      errorData: results[0],
      riverpodData: results[1],
      blocData: results[2],
      networkData: results[3],
      navigationData: results[4],
      widgetTreeData: results[5],
    );

    _cachedReport = report;
    _cachedReportTime = DateTime.now();
    lastCrashReport = report;
    return report;
  }

  void _sendProactiveAlert(String exception) {
    // Log crash alert so terminal/agent sees it immediately.
    _log.severe(
      '🚨 CRITICAL APP CRASH — call `get_errors(report: true)` for diagnostics. Exception: $exception',
    );

    try {
      server.sendLoggingMessage(
        LoggingMessageNotification(
          level: LoggingLevel.critical,
          logger: 'FlutterPilot.SelfHeal',
          data:
              'CRITICAL APP CRASH: $exception. Self-Heal sequence initiated. Call `get_errors(report: true)` for full context.',
        ),
      );
    } catch (e) {
      // Notification delivery is best-effort; crash data is still available via get_errors(report: true).
      _log.warning('Failed to send crash notification: $e');
    }
  }

  /// Resets the unstable flag (usually after a hot reload).
  ///
  /// Preserves [lastCrashReport] for post-mortem inspection by default,
  /// unless [clearReport] is set to true.
  void reset({bool clearReport = false}) {
    isUnstable = false;
    _lastCrashException = null;
    _lastCrashTimestamp = null;
    _lastCrashDeviceId = null;
    _cachedReport = null;
    _cachedReportTime = null;
    if (clearReport) {
      lastCrashReport = null;
    }
  }

  /// Explicitly clears the recorded crash report.
  void clearCrashReport() {
    lastCrashReport = null;
    _lastCrashException = null;
    _lastCrashTimestamp = null;
    _cachedReport = null;
    _cachedReportTime = null;
  }
}
