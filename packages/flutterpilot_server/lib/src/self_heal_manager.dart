import 'dart:async';
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';

final _log = logging.Logger('SelfHealManager');

/// What the app looked like when an uncaught exception happened: the
/// exception, its app frames, and the state around it. Kept under ~4 KB:
/// only sections with data, clipped; the widget tree is one
/// get_widget_tree away.
class CrashReport {
  final String timestamp;
  final String exception;
  final dynamic errorData;
  final dynamic riverpodData;
  final dynamic blocData;
  final dynamic networkData;
  final dynamic navigationData;

  CrashReport({
    required this.timestamp,
    required this.exception,
    this.errorData,
    this.riverpodData,
    this.blocData,
    this.networkData,
    this.navigationData,
  });

  /// The crashing error's compacted stack (the SDK keeps app frames only).
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
    ].join('\n').trim();
  }

  static String _clip(Object? value, [int max = 200]) {
    final text = '$value';
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  /// "name: value" lines from a plugin's {'states': {name: {key: …}}}.
  static List<String> _states(dynamic data, String valueKey) {
    final states = data is Map ? data['states'] : null;
    if (states is! Map) return const [];
    return [
      for (final MapEntry(:key, :value) in states.entries)
        '$key: ${_clip(value is Map ? value[valueKey] : value, 120)}',
    ];
  }

  /// The last requests, one line each: "GET url → 200".
  static List<String> _network(dynamic data) {
    final logs = data is Map ? data['logs'] : null;
    if (logs is! List) return const [];
    return [
      for (final l
          in logs.whereType<Map>().toList().reversed.take(6).toList().reversed)
        [
          l['type'],
          l['method'],
          _clip(l['uri'], 120),
          l['statusCode'],
          if (l['mocked'] == true) '(mocked)',
          if (l['message'] != null) _clip(l['message'], 120),
        ].whereType<Object>().join(' '),
    ];
  }

  String toMarkdown() {
    final buffer = StringBuffer('# Uncaught exception\n\n$exception\n');
    buffer.writeln('\nAt: $timestamp');
    final stack = _crashStack(errorData);
    if (stack != null && stack.isNotEmpty) {
      buffer.writeln('\n## Stack (app frames)\n$stack');
    }
    final route = navigationData is Map ? navigationData['stack'] : null;
    if (route is List && route.isNotEmpty) {
      buffer.writeln('\n## Route\n${route.join(' -> ')}');
    }
    final state = [
      ..._states(riverpodData, 'value'),
      ..._states(blocData, 'state'),
    ];
    if (state.isNotEmpty) {
      buffer.writeln('\n## State\n${state.take(15).join('\n')}');
    }
    final network = _network(networkData);
    if (network.isNotEmpty) {
      buffer.writeln('\n## Last requests\n${network.join('\n')}');
    }
    buffer.writeln(
      '\nFix the app frame above, hot_reload, and repeat the steps '
      '(get_flight_log shows them).',
    );
    return buffer.toString();
  }
}

/// Tracks uncaught exceptions (not layout warnings) since the last hot
/// reload, tells the client once per distinct exception, and builds the
/// report on demand.
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

  /// Exceptions the client was already told about since the last reset.
  final Set<String> _notified = {};

  CrashReport? _cachedReport;
  DateTime? _cachedReportTime;

  /// [clock] lets tests step past the debounce.
  SelfHealManager({required this.server, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

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
    final now = _clock();
    if (_lastDebouncedException == exception &&
        _lastCrashTime != null &&
        now.difference(_lastCrashTime!) < const Duration(seconds: 2)) {
      return; // Debounced repeated error
    }
    _lastDebouncedException = exception;
    _lastCrashTime = now;

    if (severity == 'warning') {
      _log.fine('Layout warning (not an uncaught exception): $exception');
      return;
    }

    isUnstable = true;
    _lastCrashException = exception;
    _lastCrashTimestamp = now.toIso8601String();
    _lastCrashDeviceId = deviceId;
    _cachedReport = null;
    _cachedReportTime = null;

    // A handler that throws on every frame or tap would flood the client.
    if (_notified.add(exception)) _sendProactiveAlert(exception);

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
    ]);

    final report = CrashReport(
      timestamp: timestamp,
      exception: exception,
      errorData: results[0],
      riverpodData: results[1],
      blocData: results[2],
      networkData: results[3],
      navigationData: results[4],
    );

    _cachedReport = report;
    _cachedReportTime = DateTime.now();
    lastCrashReport = report;
    return report;
  }

  void _sendProactiveAlert(String exception) {
    _log.warning('Uncaught exception in the app: $exception');
    try {
      server.sendLoggingMessage(
        LoggingMessageNotification(
          level: LoggingLevel.error,
          logger: 'FlutterPilot',
          data:
              'Uncaught exception in the app: $exception. '
              'get_errors(report: true) has its stack and the app state.',
        ),
      );
    } catch (e) {
      // Best-effort; get_errors has it either way.
      _log.warning('Failed to send the exception notification: $e');
    }
  }

  /// Clears the exception flag (after a hot reload or restart).
  ///
  /// Preserves [lastCrashReport] for post-mortem inspection by default,
  /// unless [clearReport] is set to true.
  void reset({bool clearReport = false}) {
    isUnstable = false;
    _notified.clear();
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
