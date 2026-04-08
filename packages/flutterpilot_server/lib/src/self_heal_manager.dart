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

  /// Formats the report as a Markdown string for AI agents.
  String toMarkdown() {
    final buffer = StringBuffer()..writeln('# 🚨 Critical App Crash Report');
    buffer.writeln('\n**Timestamp:** $timestamp');
    buffer.writeln('\n## Exception\n$exception');

    _addSection(buffer, 'Recent Errors', errorData);
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
    if (data == null || (data is String && data == 'N/A')) {
      buffer.writeln('No data available.');
    } else {
      buffer.writeln('```json\n$data\n```');
    }
  }

  dynamic _truncateTree(dynamic tree) {
    // Basic truncation to keep the prompt context reasonable
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

  SelfHealManager({required this.server});

  /// Marks the app as unstable and starts gathering diagnostic data.
  Future<void> handleCrash({
    required String exception,
    required Future<dynamic> Function(String extension) callExtension,
  }) async {
    isUnstable = true;
    final timestamp = DateTime.now().toIso8601String();

    // Proactive Notification (Logging Message)
    _sendProactiveAlert(exception);

    // Parallel data gathering — individual failures return 'N/A' instead of crashing the whole report.
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

    lastCrashReport = CrashReport(
      timestamp: timestamp,
      exception: exception,
      errorData: results[0],
      riverpodData: results[1],
      blocData: results[2],
      networkData: results[3],
      navigationData: results[4],
      widgetTreeData: results[5],
    );
  }

  void _sendProactiveAlert(String exception) {
    // Log crash alert so terminal/agent sees it immediately.
    _log.severe(
      '🚨 CRITICAL APP CRASH — call `get_latest_crash_report` for diagnostics. Exception: $exception',
    );

    try {
      server.sendLoggingMessage(
        LoggingMessageNotification(
          level: LoggingLevel.critical,
          logger: 'FlutterPilot.SelfHeal',
          data:
              'CRITICAL APP CRASH: $exception. Self-Heal sequence initiated. Call `get_latest_crash_report` for full context.',
        ),
      );
    } catch (_) {
      // Notification delivery is best-effort; crash data is still available via get_latest_crash_report.
    }
  }

  /// Resets the unstable flag (usually after a hot reload).
  void reset() {
    isUnstable = false;
  }
}
