import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'src/self_heal_manager.dart';

final _log = logging.Logger('FlutterPilotServer');

class FlutterPilotServer {
  final McpServer server;
  final String vmServiceUri;
  final bool allowDestructive;
  /// Project root directory used by file-reading tools (read_dart_file etc).
  /// Defaults to [Directory.current] when not specified.
  final Directory _projectRoot;
  VmService? _vmService;
  final List<Map<String, dynamic>> _eventBuffer = [];
  final List<Map<String, dynamic>> _debugLogBuffer = [];
  static const int _debugLogBufferMax = 500;
  late final SelfHealManager _selfHealManager;
  final Map<String, Uint8List> _screenshotBaselines = {};

  // Reconnection state
  bool _isReconnecting = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  StreamSubscription<Event>? _eventStreamSubscription;
  StreamSubscription<Event>? _loggingStreamSubscription;
  StreamSubscription<Event>? _stdoutStreamSubscription;
  Duration _currentBackoff = const Duration(seconds: 1);
  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);
  static final Random _random = Random();

  FlutterPilotServer({
    required this.vmServiceUri,
    this.allowDestructive = false,
    Directory? projectRoot,
  })  : _projectRoot = projectRoot ?? Directory.current,
        server = McpServer(
          Implementation(name: 'FlutterPilot', version: '0.0.1'),
          options: McpServerOptions(
            capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
          ),
        ) {
    _selfHealManager = SelfHealManager(server: server);
    _registerTools();
  }

  Future<void> start() async {
    await _connectToVmService();

    // Start MCP server over stdio
    final stdioTransport = StdioServerTransport();
    await server.connect(stdioTransport);
    _log.info('FlutterPilot MCP Server started ��');
  }

  Future<void> _connectToVmService() async {
    _log.info('Connecting to VM Service: $vmServiceUri');
    _vmService = await vmServiceConnectUri(vmServiceUri);
    _log.info('Connected to VM Service');

    _currentBackoff = _minBackoff;

    // Monitor connection lifecycle — triggers reconnect on disconnect
    _vmService!.onDone.then((_) {
      if (!_disposed) {
        _log.warning('VM Service connection lost');
        _scheduleReconnect();
      }
    });

    await _setupEventStreaming();
  }

  void _scheduleReconnect() {
    if (_isReconnecting || _disposed) return;
    _isReconnecting = true;
    _vmService = null;
    _attemptReconnect();
  }

  void _attemptReconnect() {
    if (_disposed) return;

    // Add jitter: ±25% of current backoff
    final jitter =
        (_currentBackoff.inMilliseconds * 0.25 * (2 * _random.nextDouble() - 1))
            .round();
    final delay = Duration(
      milliseconds: _currentBackoff.inMilliseconds + jitter,
    );

    _log.info(
      'Reconnecting to VM Service in ${delay.inMilliseconds}ms '
      '(backoff: ${_currentBackoff.inSeconds}s)',
    );

    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      try {
        await _connectToVmService();
        _isReconnecting = false;
        _log.info('VM Service reconnected successfully');
      } catch (e) {
        _log.warning('Reconnection attempt failed', e);
        // Exponential backoff: double, capped at max
        _currentBackoff = Duration(
          milliseconds: (_currentBackoff.inMilliseconds * 2).clamp(
            _minBackoff.inMilliseconds,
            _maxBackoff.inMilliseconds,
          ),
        );
        _attemptReconnect();
      }
    });
  }

  Future<void> _setupEventStreaming() async {
    if (_vmService == null) return;

    // Cancel any previous subscription before re-subscribing
    await _eventStreamSubscription?.cancel();
    _eventStreamSubscription = null;
    await _loggingStreamSubscription?.cancel();
    _loggingStreamSubscription = null;
    await _stdoutStreamSubscription?.cancel();
    _stdoutStreamSubscription = null;

    try {
      await _vmService!.streamListen(EventStreams.kExtension);
      _eventStreamSubscription = _vmService!.onExtensionEvent.listen(
        (Event event) async {
          final timestamp = DateTime.now().toIso8601String();
          if (event.extensionKind == 'ext.flutterpilot.error') {
            final exception =
                event.extensionData?.data['exception']?.toString() ??
                'Unknown Exception';
            _eventBuffer.add({
              'type': 'error',
              'timestamp': timestamp,
              'data': event.extensionData?.data,
            });

            await _selfHealManager.handleCrash(
              exception: exception,
              callExtension: (ext) async {
                final res = await _callExtensionRaw(ext, {});
                return res.isError ? 'N/A' : res.data;
              },
            );
          } else if (event.extensionKind == 'ext.flutterpilot.action') {
            _eventBuffer.add({
              'type': 'action',
              'timestamp': timestamp,
              'data': event.extensionData?.data,
            });
          }
          if (_eventBuffer.length > 50) _eventBuffer.removeAt(0);
        },
        onError: (Object error) {
          _log.warning('Extension event stream error', error);
        },
        onDone: () {
          _log.info('Extension event stream closed');
          if (!_disposed) _scheduleReconnect();
        },
      );
    } catch (e) {
      _log.warning('Could not subscribe to extension stream', e);
    }

    // Subscribe to dart:developer log() events — these carry FlutterPilot
    // console output as well as any developer.log() calls in the app.
    try {
      await _vmService!.streamListen(EventStreams.kLogging);
      _loggingStreamSubscription = _vmService!.onLoggingEvent.listen(
        (Event event) {
          final record = event.logRecord;
          if (record == null) return;
          _appendDebugLog(
            message: record.message?.valueAsString ?? '',
            level: _levelToString(record.level ?? 0),
            logger: record.loggerName?.valueAsString ?? '',
            timestamp: DateTime.now().toIso8601String(),
          );
        },
        onError: (Object error) {
          _log.fine('Logging stream error: $error');
        },
      );
    } catch (e) {
      _log.fine('Could not subscribe to Logging stream (may not be available): $e');
    }

    // Subscribe to the Stdout stream which captures plain print() output.
    try {
      await _vmService!.streamListen(EventStreams.kStdout);
      _stdoutStreamSubscription = _vmService!.onStdoutEvent.listen(
        (Event event) {
          final bytes = event.bytes;
          if (bytes == null || bytes.isEmpty) return;
          // bytes is a base64-encoded string in the VM service protocol
          final raw = String.fromCharCodes(
            base64.decode(bytes),
          ).trim();
          if (raw.isEmpty) return;
          _appendDebugLog(
            message: raw,
            level: 'info',
            logger: 'stdout',
            timestamp: DateTime.now().toIso8601String(),
          );
        },
        onError: (Object error) {
          _log.fine('Stdout stream error: $error');
        },
      );
    } catch (e) {
      _log.fine('Could not subscribe to Stdout stream (may not be available): $e');
    }
  }

  void _appendDebugLog({
    required String message,
    required String level,
    required String logger,
    required String timestamp,
  }) {
    _debugLogBuffer.add({
      'timestamp': timestamp,
      'level': level,
      'logger': logger,
      'message': message,
    });
    if (_debugLogBuffer.length > _debugLogBufferMax) {
      _debugLogBuffer.removeAt(0);
    }
  }

  static String _levelToString(int level) {
    if (level >= 1000) return 'error';
    if (level >= 900) return 'warning';
    if (level >= 800) return 'info';
    return 'debug';
  }

  void _registerTools() {
    _registerAppTool(
      name: 'get_app_summary',
      description:
          'Get a 360-degree high-level status of the application. CALL THIS TOOL FIRST upon connecting to find your bearings, identify the current screen, and see if there are any pending errors.',
      extension: 'ext.flutterpilot.getSummary',
      nudge:
          'HINT: Now that you have the summary, use get_widget_tree to find interactable elements or capture_screenshot to see the UI.',
    );

    server.registerTool(
      'get_self_heal_status',
      description:
          'Check if the application is currently in an unstable/crash state. Use this to verify if your last fix worked or if a new crash was intercepted.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final status = _selfHealManager.isUnstable ? '🚨 UNSTABLE' : '✅ STABLE';
        return CallToolResult(
          content: [TextContent(text: 'Current App Status: $status')],
        );
      },
    );

    server.registerTool(
      'get_latest_crash_report',
      description:
          'Retrieve the most recent structured crash report. CALL THIS immediately if you receive a Self-Heal notification or if `get_self_heal_status` returns UNSTABLE.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = _selfHealManager.lastCrashReport;
        if (report == null) {
          return CallToolResult(
            content: [TextContent(text: 'No crash reports available.')],
          );
        }
        return CallToolResult(
          content: [TextContent(text: report.toMarkdown())],
        );
      },
    );

    _registerAppTool(
      name: 'get_errors',
      description:
          'Retrieve the most recent unhandled exceptions and stack traces. CALL THIS whenever you suspect a crash or logic failure.',
      extension: 'ext.flutterpilot.getErrors',
      formatResult: (json) {
        final errors = json['errors'] as List?;
        if (errors == null || errors.isEmpty) return 'No recent errors found.';
        return errors
            .map(
              (e) =>
                  '--- Error ---\n${e['exception']}\n${e['timestamp']}\n${e['stackTrace']}',
            )
            .join('\n\n');
      },
      nudge:
          'HINT: Analyze the stack trace to find the failing file, then use get_widget_tree to see the state of the UI at failure.',
    );

    _registerAppTool(
      name: 'get_riverpod_state',
      description:
          'Inspect the current values of all active Riverpod providers. CALL THIS to debug data flow, authentication status, or to verify if a state update occurred after an action.',
      extension: 'ext.flutterpilot.getRiverpodStates',
      formatResult: (json) {
        final states = json['states'] as Map?;
        if (states == null || states.isEmpty) {
          return 'No observed Riverpod providers. Ensure RiverpodPilotObserver is registered.';
        }
        return states.entries
            .map((e) => '${e.key}: ${e.value['value']} (${e.value['type']})')
            .join('\n');
      },
    );

    _registerAppTool(
      name: 'get_bloc_state',
      description:
          'Inspect the current states of all active Blocs and Cubits. CALL THIS to verify business logic transitions.',
      extension: 'ext.flutterpilot.getBlocStates',
      formatResult: (json) {
        final states = json['states'] as Map?;
        if (states == null || states.isEmpty) {
          return 'No observed Blocs. Ensure BlocPilotObserver is registered.';
        }
        return states.entries
            .map((e) => '${e.key}: ${e.value['state']} (${e.value['type']})')
            .join('\n');
      },
    );

    _registerAppTool(
      name: 'get_network_logs',
      description:
          'View the last 50 HTTP requests and responses. CALL THIS if an API call failed or to verify network payload accuracy.',
      extension: 'ext.flutterpilot.getNetworkLogs',
      formatResult: (json) {
        final logs = json['logs'] as List?;
        if (logs == null || logs.isEmpty) return 'No network traffic captured.';
        return logs
            .map(
              (l) =>
                  '[${l['timestamp']}] ${l['type'].toUpperCase()} ${l['method'] ?? ''} ${l['uri']} ${l['statusCode'] ?? ''}',
            )
            .join('\n');
      },
    );

    _registerAppTool(
      name: 'get_navigation_stack',
      description:
          'Show the current navigation history (stack). CALL THIS to understand where the user is in the application flow.',
      extension: 'ext.flutterpilot.getNavigationStack',
      formatResult: (json) =>
          'Navigation Stack: ${json['stack']?.join(' -> ') ?? 'Empty'}',
    );

    server.registerTool(
      'set_riverpod_state',
      description:
          'Inject a new state into a Riverpod provider. Use the provider name (type) from `get_riverpod_state`. The `value` should be a JSON-compatible string (e.g. "42", "true", "\\"hello\\"").',
      inputSchema: ToolInputSchema(
        properties: {
          'provider': JsonSchema.string(),
          'value': JsonSchema.string(),
        },
        required: ['provider', 'value'],
      ),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setState', {
        'type': 'riverpod',
        'name': p['provider'],
        'value': p['value'],
      }).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'set_bloc_state',
      description:
          'Force a new state into a Bloc or Cubit. Use the Bloc/Cubit class name from `get_bloc_state`. The `state` should be a JSON string (e.g. "42", "true").',
      inputSchema: ToolInputSchema(
        properties: {
          'cubit': JsonSchema.string(),
          'state': JsonSchema.string(),
        },
        required: ['cubit', 'state'],
      ),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setState', {
        'type': 'bloc',
        'name': p['cubit'],
        'value': p['state'],
      }).then((res) => res.toCallToolResult()),
    );

    _registerAppTool(
      name: 'get_widget_tree',
      description:
          'Retrieve the complete widget hierarchy with exact screen coordinates (x, y, width, height) and source code locations (file/line). CALL THIS to locate buttons to tap or to debug layout overflows.',
      extension: 'ext.flutterpilot.getWidgetTree',
      nudge:
          'HINT: You can now use tap_widget(key) or enter_text(key) using the keys found in this tree.',
    );

    _registerAppTool(
      name: 'get_hive_contents',
      description:
          'Dump the contents of all registered Hive boxes. CALL THIS to verify local persistent storage.',
      extension: 'ext.flutterpilot.getHiveContents',
    );

    _registerAppTool(
      name: 'list_drift_tables',
      description: 'List all tables in the SQLite (Drift) database.',
      extension: 'ext.flutterpilot.listDriftTables',
      properties: {'dbName': JsonSchema.string()},
    );

    _registerAppTool(
      name: 'list_custom_tools',
      description:
          'Discover additional app-specific tools registered by the developer.',
      extension: 'ext.flutterpilot.listCustomTools',
    );

    server.registerTool(
      'get_recent_events',
      description:
          'Retrieves the last 50 proactive events (errors, taps, state changes) from the stream. Use this to catch up on what happened while you were processing or if the user interacted with the app manually.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_eventBuffer.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No recent events.')],
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: _eventBuffer
                  .map(
                    (ev) => '[${ev['timestamp']}] ${ev['type']}: ${ev['data']}',
                  )
                  .join('\n'),
            ),
          ],
        );
      },
    );

    // -- get_debug_logs -------------------------------------------------------
    // Returns captured console output (print, debugPrint, developer.log).
    server.registerTool(
      'get_debug_logs',
      description:
          'Returns captured console output from the running app — including print(), debugPrint(), and dart:developer log() calls. '
          'This replaces the need to manually copy-paste from VS Code debug console. '
          'Use level filter ("debug", "info", "warning", "error") and limit to narrow results. '
          'Call this any time you need to see what the app is printing.',
      inputSchema: ToolInputSchema(
        properties: {
          'level': JsonSchema.string(),
          'limit': JsonSchema.integer(),
          'logger': JsonSchema.string(),
        },
      ),
      callback: (params, extra) async {
        final levelFilter = params['level'] as String?;
        final loggerFilter = params['logger'] as String?;
        final limit = (params['limit'] as int?) ?? 100;
        var entries = _debugLogBuffer.toList();
        if (levelFilter != null && levelFilter.isNotEmpty) {
          entries = entries
              .where((e) => e['level'] == levelFilter)
              .toList();
        }
        if (loggerFilter != null && loggerFilter.isNotEmpty) {
          entries = entries
              .where((e) => (e['logger'] as String).contains(loggerFilter))
              .toList();
        }
        if (entries.length > limit) {
          entries = entries.sublist(entries.length - limit);
        }
        if (entries.isEmpty) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'No console logs captured yet. '
                    'Ensure FlutterPilot.initialize() is called before runApp().',
              ),
            ],
          );
        }
        final lines = entries
            .map(
              (e) =>
                  '[${e['timestamp']}] [${e['level']}] ${e['logger'].toString().isNotEmpty ? '(${e['logger']}) ' : ''}${e['message']}',
            )
            .join('\n');
        return CallToolResult(
          content: [
            TextContent(
              text: '${entries.length} log entries '
                  '(buffer total: ${_debugLogBuffer.length}):\n$lines',
            ),
          ],
        );
      },
    );

    // -- clear_debug_logs -----------------------------------------------------
    server.registerTool(
      'clear_debug_logs',
      description:
          'Clears the captured console log buffer on the server side. '
          'Use this before a specific test scenario so you get a clean baseline.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final count = _debugLogBuffer.length;
        _debugLogBuffer.clear();
        return CallToolResult(
          content: [TextContent(text: 'Cleared $count log entries.')],
        );
      },
    );

    // -- set_log_filter -------------------------------------------------------
    // Delegates to the SDK extension to also clear the in-app buffer.
    server.registerTool(
      'set_log_filter',
      description:
          'Clears the in-app SDK debug log buffer. Call before a test run '
          'to get a clean log window. '
          'Tip: pair with get_debug_logs(level:"error") after the action.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final serverCleared = _debugLogBuffer.length;
        _debugLogBuffer.clear();
        final res = await _callExtensionRaw(
          'ext.flutterpilot.clearDebugLogs',
          {},
        );
        if (res.isError) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'Server buffer cleared ($serverCleared entries). '
                    'In-app buffer: ${res.errorMessage}',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: 'Log buffers cleared (server: $serverCleared entries, app: cleared).',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'query_drift',
      description:
          'Execute a raw SQL SELECT query on the local database. CALL THIS to verify complex data relationships or transaction history.',
      inputSchema: ToolInputSchema(
        properties: {'dbName': JsonSchema.string(), 'sql': JsonSchema.string()},
        required: ['dbName', 'sql'],
      ),
      callback: (params, extra) async {
        final sql = (params['sql'] as String).trim();
        final sqlUpper = sql.toUpperCase();
        final isReadOnly =
            sqlUpper.startsWith('SELECT') ||
            sqlUpper.startsWith('EXPLAIN') ||
            sqlUpper.startsWith('PRAGMA');
        if (!allowDestructive && !isReadOnly) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Security: Only SELECT/EXPLAIN/PRAGMA queries are allowed. Start server with --allow-destructive to enable write operations.',
              ),
            ],
            isError: true,
          );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.queryDrift',
          params,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Results:\n${res.data!['results']}\n\nHINT: If data is missing, check get_network_logs to see if the last sync failed.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'call_custom_tool',
      description:
          'Executes an app-specific tool defined by the developer. CALL THIS if you see a relevant tool listed in `list_custom_tools`.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(),
          'params': JsonSchema.object(),
        },
        required: ['name'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.callCustomTool',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'tap_at',
      description:
          'Simulates a physical tap at specific (x, y) coordinates. Prefer `tap_widget` if you have a Key.',
      inputSchema: ToolInputSchema(
        properties: {'x': JsonSchema.number(), 'y': JsonSchema.number()},
        required: ['x', 'y'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapAt', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Tap successful. HINT: Use get_navigation_stack or get_riverpod_state to see if the app responded.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'tap_widget',
      description:
          'Finds a widget by its Key and taps its center. HINT: Use `get_widget_tree` to find the Key first. After tapping, you should verify state changes.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string()},
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Widget tapped. HINT: The UI should have changed. Use capture_screenshot to verify.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'enter_text',
      description:
          'Types text into a TextField identified by a Key. Automatically handles controller updates and change notifications.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string(), 'text': JsonSchema.string()},
        required: ['key', 'text'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.enterText', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Text entered. HINT: You may need to tap a "Submit" or "Save" button now.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'scroll_into_view',
      description:
          'Ensures a widget is visible by scrolling its parent list. Use this before tapping a widget that might be off-screen.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string()},
        required: ['key'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.scrollIntoView',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'double_tap_widget',
      description:
          'Double-taps a widget by Key (two rapid taps). Use for zoom gestures, selection toggles, or any widget that responds to double-tap.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string()},
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.doubleTapWidget',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Double-tapped. Use capture_screenshot to verify.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'long_press_widget',
      description:
          'Long-presses a widget by Key. Use to trigger context menus, drag handles, or long-press actions. Optional durationMs (default 600).',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
          'durationMs': JsonSchema.integer(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final args = {
          'key': p['key'] as String,
          if (p['durationMs'] != null) 'durationMs': p['durationMs'].toString(),
        };
        final res = await _callExtensionRaw(
          'ext.flutterpilot.longPressWidget',
          args,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Long press complete. Use capture_screenshot to verify the context menu or action.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'swipe_widget',
      description:
          'Swipes on a widget in a direction (up/down/left/right). Use to scroll lists, dismiss cards, open drawers, or trigger swipe actions.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
          'direction': JsonSchema.string(
            enumValues: ['up', 'down', 'left', 'right'],
          ),
          'distance': JsonSchema.number(),
        },
        required: ['key', 'direction'],
      ),
      callback: (p, e) async {
        final args = {
          'key': p['key'] as String,
          'direction': p['direction'] as String,
          if (p['distance'] != null) 'distance': p['distance'].toString(),
        };
        final res = await _callExtensionRaw(
          'ext.flutterpilot.swipeWidget',
          args,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Swipe complete. Use capture_screenshot or get_widget_tree to verify.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'drag_widget',
      description:
          'Drags one widget onto another by Key. Use for drag-and-drop reordering, drag targets, or drop zones.',
      inputSchema: ToolInputSchema(
        properties: {
          'fromKey': JsonSchema.string(),
          'toKey': JsonSchema.string(),
        },
        required: ['fromKey', 'toKey'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.dragWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Drag complete. Use capture_screenshot to verify the new position.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'wait_for_widget',
      description:
          'Polls until a widget with the given Key appears in the tree, or times out. Use after navigation or async operations. Default timeout 5000ms.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
          'timeoutMs': JsonSchema.integer(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final args = {
          'key': p['key'] as String,
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForWidget',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'wait_for_route',
      description:
          'Polls until the current route matches the expected route, or times out. Use instead of sleep() after navigate_to. Default timeout 5000ms.',
      inputSchema: ToolInputSchema(
        properties: {
          'route': JsonSchema.string(),
          'timeoutMs': JsonSchema.integer(),
        },
        required: ['route'],
      ),
      callback: (p, e) async {
        final args = {
          'route': p['route'] as String,
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForRoute',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'wait_for_animation',
      description:
          'Waits until all animations and frame callbacks have settled. Call this before taking screenshots or making assertions after animated transitions.',
      inputSchema: ToolInputSchema(
        properties: {'timeoutMs': JsonSchema.integer()},
      ),
      callback: (p, e) async {
        final args = {
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForAnimation',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'assert_widget_visible',
      description:
          'Asserts that a widget with the given Key is present and has layout. Returns error if the assertion fails — treat this as a test failure.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string()},
        required: ['key'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.assertWidgetVisible',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'assert_text_visible',
      description:
          'Asserts that the given text is visible on screen. Set exact=true for exact match, false (default) for substring match.',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(),
          'exact': JsonSchema.boolean(),
        },
        required: ['text'],
      ),
      callback: (p, e) async {
        final args = {
          'text': p['text'] as String,
          if (p['exact'] != null) 'exact': p['exact'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.assertTextVisible',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'assert_widget_count',
      description:
          'Asserts the exact number of widgets of a given type (e.g. "ListTile", "ElevatedButton") on screen. Returns error if count does not match.',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(),
          'count': JsonSchema.integer(),
        },
        required: ['type', 'count'],
      ),
      callback: (p, e) async {
        final args = {
          'type': p['type'] as String,
          'count': p['count'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.assertWidgetCount',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'simulate_network',
      description:
          'Simulates a network condition for all Dio HTTP requests. Use to test offline states, loading skeletons, and slow-connection UX. Conditions: normal | slow_3g | fast_4g | offline.',
      inputSchema: ToolInputSchema(
        properties: {
          'condition': JsonSchema.string(
            enumValues: ['normal', 'slow_3g', 'fast_4g', 'offline'],
          ),
        },
        required: ['condition'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.simulateNetwork',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'mock_http_response',
      description:
          'Registers a URL pattern mock so that any Dio request whose URL contains '
          'urlPattern returns a synthetic response instead of hitting the network. '
          'Use to test error states, empty states, or edge-case API responses. '
          'Call clear_http_mocks to remove mocks when done.',
      inputSchema: ToolInputSchema(
        properties: {
          'urlPattern': JsonSchema.string(
            description: 'Substring of the URL to match (e.g. "/api/users")',
          ),
          'statusCode': JsonSchema.integer(description: 'HTTP status code (e.g. 200, 404, 500)'),
          'body': JsonSchema.string(
            description: 'Response body as a JSON string (e.g. \'{"error":"not found"}\')',
          ),
          'delayMs': JsonSchema.integer(
            description: 'Artificial delay in milliseconds before returning the mock (default 0)',
          ),
        },
        required: ['urlPattern', 'statusCode', 'body'],
      ),
      callback: (p, e) {
        final mapped = {
          'urlPattern': p['urlPattern']?.toString(),
          'statusCode': p['statusCode']?.toString(),
          'body': p['body']?.toString(),
          if (p['delayMs'] != null) 'delayMs': p['delayMs'].toString(),
        };
        return _callExtensionRaw('ext.flutterpilot.addHttpMock', mapped)
            .then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'clear_http_mocks',
      description:
          'Removes a specific URL pattern mock, or all mocks if urlPattern is omitted. '
          'Always call this after testing a mocked flow to restore real network behaviour.',
      inputSchema: ToolInputSchema(
        properties: {
          'urlPattern': JsonSchema.string(
            description:
                'Pattern to remove. Omit to clear ALL mocks.',
          ),
        },
      ),
      callback: (p, e) {
        final mapped = <String, String?>{
          if (p['urlPattern'] != null) 'urlPattern': p['urlPattern'].toString(),
        };
        return _callExtensionRaw('ext.flutterpilot.clearHttpMocks', mapped)
            .then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'wait_for_state',
      description:
          'Polls a Riverpod provider or Bloc/Cubit until its current value string contains '
          'expectedValue, or until timeoutMs elapses. Use after triggering async operations '
          'to assert that state has settled. Requires the matching plugin to be active '
          '(RiverpodPilotObserver or BlocPilotObserver).',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(enumValues: ['riverpod', 'bloc']),
          'name': JsonSchema.string(
            description:
                'State identifier. For Riverpod: the provider\'s runtimeType string '
                '(e.g. "StateProvider<int>"). For Bloc: the bloc\'s runtimeType string '
                '(e.g. "CounterCubit").',
          ),
          'expectedValue': JsonSchema.string(
            description: 'Substring expected in the state\'s toString() output',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Milliseconds to wait before timing out (default 5000)',
          ),
        },
        required: ['type', 'name', 'expectedValue'],
      ),
      callback: (p, e) {
        final mapped = {
          'type': p['type']?.toString(),
          'name': p['name']?.toString(),
          'expectedValue': p['expectedValue']?.toString(),
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw('ext.flutterpilot.waitForState', mapped)
            .then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'set_device_rotation',
      description:
          'Rotates the device to portrait or landscape orientation. Use to test responsive layouts, '
          'orientation-locked screens, and rotation animations.',
      inputSchema: ToolInputSchema(
        properties: {
          'orientation': JsonSchema.string(
            enumValues: ['portrait', 'landscape', 'all'],
          ),
        },
        required: ['orientation'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.setOrientation',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'save_screenshot_baseline',
      description:
          'Captures the current screen and stores it as a named baseline image for future '
          'visual regression comparisons. Call this once to establish a golden image, then '
          'use compare_screenshot after code changes.',
      inputSchema: ToolInputSchema(
        properties: {'name': JsonSchema.string()},
        required: ['name'],
      ),
      callback: (p, e) async {
        final name = p['name']?.toString();
        if (name == null || name.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'name is required')],
            isError: true,
          );
        }
        final res = await _callExtensionRaw('ext.flutterpilot.captureScreenshot', {});
        if (res.isError) return res.toCallToolResult();
        final base64Str = res.data?['data'] as String?;
        if (base64Str == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no data')],
            isError: true,
          );
        }
        _screenshotBaselines[name] = base64Decode(base64Str);
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Baseline "$name" saved (${_screenshotBaselines[name]!.length} bytes). '
                  'HINT: Run compare_screenshot after making visual changes.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'compare_screenshot',
      description:
          'Captures the current screen and compares it pixel-by-pixel with a previously saved '
          'baseline. Returns the percentage of changed pixels. Use for visual regression testing.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(description: 'Baseline name set by save_screenshot_baseline'),
          'threshold': JsonSchema.number(
            description: 'Allowed diff % before test fails (default 1.0 = 1%)',
          ),
        },
        required: ['name'],
      ),
      callback: (p, e) async {
        final name = p['name']?.toString();
        if (name == null || name.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'name is required')],
            isError: true,
          );
        }
        final baseline = _screenshotBaselines[name];
        if (baseline == null) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'No baseline named "$name". '
                    'Call save_screenshot_baseline first.',
              ),
            ],
            isError: true,
          );
        }
        final res = await _callExtensionRaw('ext.flutterpilot.captureScreenshot', {});
        if (res.isError) return res.toCallToolResult();
        final base64Str = res.data?['data'] as String?;
        if (base64Str == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no data')],
            isError: true,
          );
        }
        final currentBytes = base64Decode(base64Str);
        final threshold = (p['threshold'] as num?)?.toDouble() ?? 1.0;

        // Decode both PNGs and compare pixel-by-pixel.
        final baselineImg = img.decodePng(baseline);
        final currentImg = img.decodePng(currentBytes);

        if (baselineImg == null || currentImg == null) {
          return CallToolResult(
            content: [TextContent(text: 'Failed to decode PNG images for comparison')],
            isError: true,
          );
        }

        double diffPercent;
        if (baselineImg.width != currentImg.width ||
            baselineImg.height != currentImg.height) {
          diffPercent = 100.0;
        } else {
          int diffPixels = 0;
          final total = baselineImg.width * baselineImg.height;
          for (int y = 0; y < baselineImg.height; y++) {
            for (int x = 0; x < baselineImg.width; x++) {
              final bp = baselineImg.getPixel(x, y);
              final cp = currentImg.getPixel(x, y);
              if (bp.r != cp.r || bp.g != cp.g || bp.b != cp.b) {
                diffPixels++;
              }
            }
          }
          diffPercent = total > 0 ? (diffPixels / total) * 100.0 : 0.0;
        }

        final passed = diffPercent <= threshold;
        final diffStr = diffPercent.toStringAsFixed(2);
        return CallToolResult(
          content: [
            TextContent(
              text: passed
                  ? 'Visual regression PASSED ✅ — diff: $diffStr% (threshold: $threshold%)'
                  : 'Visual regression FAILED ❌ — diff: $diffStr% exceeds threshold $threshold%',
            ),
          ],
          isError: !passed,
        );
      },
    );

    server.registerTool(
      'navigate_to',
      description:
          'Programmatically pushes a named route. Useful for jumping directly to a feature screen for testing.',
      inputSchema: ToolInputSchema(
        properties: {'route': JsonSchema.string()},
        required: ['route'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.navigateTo',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'start_recording',
      description:
          'Starts recording manual interactions. User should perform the flow in the app while this is active.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.startRecording',
        {},
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'stop_and_generate_test',
      description:
          'Stops recording and returns a log of actions. Use your LLM capability to convert this log into a Flutter `testWidgets` block.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.stopRecording',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Recorded Actions (Convert to Test):\n${jsonEncode(res.data?['actions'])}\n\nHINT: Create a new file in the test/ directory and paste this as a testWidgets block.',
            ),
          ],
          isError: false,
        );
      },
    );

    server.registerTool(
      'capture_screenshot',
      description:
          'Capture a vision-ready image of the current screen. CALL THIS to analyze layout, colors, or visual glitches. HINT: Compare with `get_widget_tree` for coordinate-perfect reasoning.',
      inputSchema: ToolInputSchema(
        properties: {
          'format': JsonSchema.string(enumValues: ['png', 'webp']),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            ImageContent(data: res.data!['data'], mimeType: 'image/png'),
            TextContent(
              text:
                  'Screenshot captured. HINT: If you see an error overlay, call diagnose_last_error immediately.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'hot_reload',
      description:
          'Trigger a source code hot reload. CALL THIS after you have modified a .dart file to apply the fix to the running app.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'Not connected')],
            isError: true,
          );
        }
        final vm = await _vmService!.getVM();
        final mainIsolateId = vm.isolates?.first.id;
        if (mainIsolateId == null) {
          return CallToolResult(
            content: [TextContent(text: 'No main isolate found')],
            isError: true,
          );
        }
        try {
          await _vmService!.reloadSources(mainIsolateId);
          await _vmService!.callServiceExtension(
            'ext.flutter.reassemble',
            isolateId: mainIsolateId,
          );
          _selfHealManager.reset();
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Hot Reload successful! HINT: Now call get_self_heal_status to verify the fix.',
              ),
            ],
          );
        } catch (err) {
          return CallToolResult(
            content: [TextContent(text: 'Hot Reload failed: $err')],
            isError: true,
          );
        }
      },
    );

    server.registerTool(
      'hot_restart',
      description:
          'Trigger a full app hot restart. CALL THIS for structural code changes (main(), providers) or to reset app state.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'Not connected')],
            isError: true,
          );
        }
        final vm = await _vmService!.getVM();
        final mainIsolateId = vm.isolates?.first.id;
        if (mainIsolateId == null) {
          return CallToolResult(
            content: [TextContent(text: 'No main isolate found')],
            isError: true,
          );
        }
        try {
          await _vmService!.callServiceExtension(
            'ext.flutter.hotRestart',
            isolateId: mainIsolateId,
          );
          _selfHealManager.reset();
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Hot Restart triggered! HINT: App state is reset. Use get_app_summary to re-orient.',
              ),
            ],
          );
        } catch (err) {
          return CallToolResult(
            content: [TextContent(text: 'Hot Restart failed: $err')],
            isError: true,
          );
        }
      },
    );

    server.registerTool(
      'set_theme',
      description:
          'Toggle Light/Dark mode. Use this to verify design consistency across themes.',
      inputSchema: ToolInputSchema(
        properties: {
          'theme': JsonSchema.string(enumValues: ['light', 'dark']),
        },
        required: ['theme'],
      ),
      callback: (p, e) {
        final val = p['theme'] == 'dark'
            ? 'Brightness.dark'
            : 'Brightness.light';
        return _callExtensionRaw('ext.flutter.brightnessOverride', {
          'value': val,
        }).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'set_locale',
      description:
          'Switch app language (e.g., "en", "de_DE"). Use this to check for text overflows in different languages.',
      inputSchema: ToolInputSchema(
        properties: {'locale': JsonSchema.string()},
        required: ['locale'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.setLocale',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'get_perf_metrics',
      description:
          'Get current FPS and Heap Memory usage. CALL THIS to verify that code optimizations actually improved performance.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final fpsRes = await _callExtensionRaw(
          'ext.flutterpilot.getPerfMetrics',
          {},
        );
        String memory = 'N/A';
        if (_vmService != null) {
          final vm = await _vmService!.getVM();
          final usage = await _vmService!.getMemoryUsage(
            vm.isolates!.first.id!,
          );
          memory =
              '${((usage.heapUsage ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB';
        }
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'FPS: ${fpsRes.data?['fps'] ?? 'N/A'}\nHeap: $memory\n\nHINT: If FPS is below 60, use show_performance_overlay to find heavy build cycles.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'diagnose_last_error',
      description:
          '[DEPRECATED] Use `get_latest_crash_report` instead for better structured data.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = _selfHealManager.lastCrashReport;
        if (report == null) {
          return CallToolResult(
            content: [TextContent(text: 'No crash reports available.')],
          );
        }
        return CallToolResult(
          content: [TextContent(text: report.toMarkdown())],
        );
      },
    );

    // ── New interaction tools ────────────────────────────────────────────────

    server.registerTool(
      'press_back',
      description:
          'Simulates pressing the hardware/system back button. Pops the '
          'current route from the Navigator. Reports whether a route was '
          'actually popped (false if already at root).',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.pressBack', {});
        if (res.isError) return res.toCallToolResult();
        final popped = res.data?['popped'] as bool? ?? false;
        return CallToolResult(
          content: [
            TextContent(
              text: popped
                  ? 'Back pressed — route popped.'
                  : 'Back pressed — already at root (nothing to pop).',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'clear_text_field',
      description:
          'Clears the text of a TextField / TextFormField identified by its '
          'widget key. Equivalent to select-all then delete. '
          'Use enter_text to type new content afterwards.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.clearTextField',
          {'key': p['key'].toString()},
        );
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Text field cleared.')],
              );
      },
    );

    server.registerTool(
      'get_widget_properties',
      description:
          'Reads the semantic properties of a widget identified by its key. '
          'Returns: type, text (Text/TextField content), isEnabled '
          '(onPressed/onTap/onChanged non-null), isChecked (Checkbox/Switch), '
          'value/min/max (Slider), isFocused, and screen-space bounds. '
          'Use this instead of screenshots to verify widget state.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getWidgetProperties',
          {'key': p['key'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'assert_widget_enabled',
      description:
          'Asserts that the widget identified by key is ENABLED '
          '(has a non-null onPressed / onTap / onChanged callback). '
          'Returns error if the widget is disabled or not found.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.assertWidgetEnabled',
          {'key': p['key'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'assert_widget_disabled',
      description:
          'Asserts that the widget identified by key is DISABLED '
          '(onPressed / onTap / onChanged is null). '
          'Returns error if the widget is enabled or not found.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.assertWidgetDisabled',
          {'key': p['key'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'unfocus_all',
      description:
          'Removes focus from all widgets and dismisses the software keyboard. '
          'Call this after finishing text input to close the keyboard before '
          'taking screenshots or tapping other elements.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res =
            await _callExtensionRaw('ext.flutterpilot.unfocusAll', {});
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Keyboard dismissed.')],
              );
      },
    );

    server.registerTool(
      'focus_widget',
      description:
          'Taps the centre of the widget identified by key to request focus '
          '(opens the software keyboard for a TextField). '
          'Use unfocus_all to close the keyboard afterwards.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.focusWidget',
          {'key': p['key'].toString()},
        );
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Widget focused.')],
              );
      },
    );

    server.registerTool(
      'set_text_scale_factor',
      description:
          'Overrides the app-wide text scale factor for accessibility testing. '
          'Common values: 1.0 (default), 1.5 (large), 2.0 (extra-large), '
          '3.0 (maximum). Pass 0 to reset to system default. '
          'Requires the app to wrap MaterialApp with a MediaQuery that '
          'listens to FlutterPilot.textScaleNotifier.',
      inputSchema: ToolInputSchema(
        properties: {
          'scale': JsonSchema.number(),
        },
        required: ['scale'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.setTextScaleFactor',
          {'scale': p['scale'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'simulate_deep_link',
      description:
          'Simulates opening a deep link URL, triggering the same routing '
          'path as an OS-level deep link (e.g., "myapp://product/123" or '
          '"/product/123"). Use this to test deep link handlers, share links, '
          'and notification tap flows.',
      inputSchema: ToolInputSchema(
        properties: {
          'url': JsonSchema.string(),
        },
        required: ['url'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.simulateDeepLink',
          {'url': p['url'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'pump_frames',
      description:
          'Waits for a specified number of vsync animation frames to complete. '
          'Use this to let animations, timers, or async widget builds settle '
          'without needing a full wait_for_animation call. '
          'Max 120 frames.',
      inputSchema: ToolInputSchema(
        properties: {
          'count': JsonSchema.integer(),
        },
      ),
      callback: (p, e) async {
        final count = p['count'] ?? 1;
        final res = await _callExtensionRaw(
          'ext.flutterpilot.pumpFrames',
          {'count': count.toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'get_semantics_tree',
      description:
          'Returns the full accessibility semantics tree as seen by screen '
          'readers (VoiceOver/TalkBack). Each node has: id, label, value, '
          'hint, tooltip, role flags (isButton/isTextField/isSlider/isImage/'
          'isLink/isLiveRegion), isChecked, isEnabled, isFocused, and '
          'screen-space rect. Use this for accessibility audits.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getSemanticsTree',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: jsonEncode(res.data),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'set_slider_value',
      description:
          'Sets the value of a Slider widget identified by key. Computes '
          'the correct tap position for the target value based on the '
          'slider\'s min/max range and dispatches a pointer event. '
          'The value is clamped to [min, max].',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
          'value': JsonSchema.number(),
        },
        required: ['key', 'value'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.setSliderValue',
          {
            'key': p['key'].toString(),
            'value': p['value'].toString(),
          },
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'toggle_checkbox',
      description:
          'Taps the centre of the first Checkbox, Switch, or Radio widget '
          'found under the given key to toggle its state. '
          'Use get_widget_properties to read the resulting isChecked value.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.toggleCheckbox',
          {'key': p['key'].toString()},
        );
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Toggled.')],
              );
      },
    );

    // ── Server-only file/project tools ───────────────────────────────────────

    server.registerTool(
      'read_dart_file',
      description:
          'Reads a Dart source file from the connected Flutter project. '
          'The path is relative to the project root (where pubspec.yaml is). '
          'Use this to give the AI agent codebase context: read widgets, '
          'models, routes, or test files before making changes.',
      inputSchema: ToolInputSchema(
        properties: {
          'path': JsonSchema.string(),
        },
        required: ['path'],
      ),
      callback: (p, e) async {
        final relativePath = p['path'].toString();
        if (relativePath.contains('..')) {
          return CallToolResult(
            content: [
              TextContent(text: 'Error: path traversal not allowed.'),
            ],
            isError: true,
          );
        }
        final file = File(
          '${_projectRoot.path}${Platform.pathSeparator}$relativePath',
        );
        if (!await file.exists()) {
          return CallToolResult(
            content: [TextContent(text: 'File not found: $relativePath')],
            isError: true,
          );
        }
        final content = await file.readAsString();
        return CallToolResult(
          content: [TextContent(text: content)],
        );
      },
    );

    server.registerTool(
      'list_dart_files',
      description:
          'Lists all .dart files in the Flutter project under the given '
          'directory (defaults to "lib"). Returns relative paths from the '
          'project root. Use to explore project structure before reading files.',
      inputSchema: ToolInputSchema(
        properties: {
          'directory': JsonSchema.string(),
        },
      ),
      callback: (p, e) async {
        final dir =
            p['directory']?.toString().replaceAll('..', '') ?? 'lib';
        final searchDir = Directory(
          '${_projectRoot.path}${Platform.pathSeparator}$dir',
        );
        if (!await searchDir.exists()) {
          return CallToolResult(
            content: [TextContent(text: 'Directory not found: $dir')],
            isError: true,
          );
        }
        final files = <String>[];
        await for (final entity in searchDir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final relative = entity.path
                .replaceFirst(_projectRoot.path, '')
                .replaceFirst(RegExp(r'^[/\\]'), '');
            files.add(relative);
          }
        }
        files.sort();
        return CallToolResult(
          content: [TextContent(text: files.join('\n'))],
        );
      },
    );

    server.registerTool(
      'get_build_config',
      description:
          'Reads the project\'s pubspec.yaml and returns the app name, '
          'version, Flutter/Dart SDK constraints, and dependency list. '
          'Use this to understand what packages are available before '
          'suggesting code that requires them.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final pubspec =
            File('${_projectRoot.path}${Platform.pathSeparator}pubspec.yaml');
        if (!await pubspec.exists()) {
          return CallToolResult(
            content: [TextContent(text: 'pubspec.yaml not found.')],
            isError: true,
          );
        }
        // Return raw pubspec.yaml — YAML parsing would add a dependency.
        // The AI agent can parse it directly from the raw text.
        final content = await pubspec.readAsString();
        return CallToolResult(
          content: [TextContent(text: content)],
        );
      },
    );

    // ── SharedPreferences tools ──────────────────────────────────────────────

    _registerAppTool(
      name: 'get_shared_preferences',
      description:
          'Returns all SharedPreferences keys and their typed values '
          '(String, int, double, bool, List<String>). '
          'Requires the flutterpilot_shared_preferences plugin.',
      extension: 'ext.flutterpilot.getSharedPreferences',
    );

    server.registerTool(
      'set_shared_preference',
      description:
          'Writes a key-value pair to SharedPreferences. '
          'Specify type as: string (default), int, double, bool, or '
          'stringList (JSON array, e.g. \'["a","b"]\').',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(),
          'value': JsonSchema.string(),
          'type': JsonSchema.string(),
        },
        required: ['key', 'value'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.setSharedPreference',
          {
            'key': p['key'].toString(),
            'value': p['value'].toString(),
            if (p['type'] != null) 'type': p['type'].toString(),
          },
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'clear_shared_preferences',
      description:
          'Clears SharedPreferences. If key is specified, only that key is '
          'removed. If omitted, ALL preferences are cleared. '
          'Use with caution — clear all is irreversible.',
      inputSchema: ToolInputSchema(
        properties: {'key': JsonSchema.string()},
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.clearSharedPreferences',
          {if (p['key'] != null) 'key': p['key'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    // =========================================================================
    // DevTools-equivalent deep inspection tools
    // These use the same VM Service Protocol that Flutter DevTools uses.
    // =========================================================================

    // -- get_memory_details ---------------------------------------------------
    server.registerTool(
      'get_memory_details',
      description:
          'Returns a detailed memory breakdown of the running app: heap used, '
          'heap capacity, external (native) memory, and RSS for every Dart isolate. '
          'Use this to detect memory leaks or unexpected growth. '
          'Heap > 200 MB or external > 50 MB usually warrants investigation.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await _vmService!.getVM();
          final buf = StringBuffer('Memory details:\n');
          int totalHeapUsed = 0;
          int totalHeapCapacity = 0;
          int totalExternal = 0;
          for (final iso in vm.isolates ?? []) {
            if (iso.id == null) continue;
            try {
              final m = await _vmService!.getMemoryUsage(iso.id!);
              final heapUsedMb =
                  ((m.heapUsage ?? 0) / (1024 * 1024)).toStringAsFixed(2);
              final heapCapMb =
                  ((m.heapCapacity ?? 0) / (1024 * 1024)).toStringAsFixed(2);
              final extMb =
                  ((m.externalUsage ?? 0) / (1024 * 1024)).toStringAsFixed(2);
              buf.writeln(
                '  ${iso.name ?? iso.id}: heap=$heapUsedMb/$heapCapMb MB  external=$extMb MB',
              );
              totalHeapUsed += m.heapUsage ?? 0;
              totalHeapCapacity += m.heapCapacity ?? 0;
              totalExternal += m.externalUsage ?? 0;
            } catch (_) {}
          }
          buf.writeln(
            '\nTotals: heap=${((totalHeapUsed) / (1024 * 1024)).toStringAsFixed(2)}/'
            '${((totalHeapCapacity) / (1024 * 1024)).toStringAsFixed(2)} MB  '
            'external=${((totalExternal) / (1024 * 1024)).toStringAsFixed(2)} MB',
          );
          return CallToolResult(
            content: [TextContent(text: buf.toString())],
          );
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'Memory query failed: $e')],
            isError: true,
          );
        }
      },
    );

    // -- get_allocation_profile -----------------------------------------------
    server.registerTool(
      'get_allocation_profile',
      description:
          'Returns the top Dart classes by current heap allocation (like the '
          'DevTools Memory tab class list). Use this to find memory leaks — '
          'look for classes with unexpectedly high instance counts or byte sizes. '
          'Accepts optional limit (default 30) for number of classes to show.',
      inputSchema: ToolInputSchema(
        properties: {'limit': JsonSchema.integer()},
      ),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        final limit = (params['limit'] as int?) ?? 30;
        try {
          final vm = await _vmService!.getVM();
          final isolateId = vm.isolates?.firstOrNull?.id;
          if (isolateId == null) {
            return CallToolResult(
              content: [TextContent(text: 'No isolate available.')],
            );
          }
          final profile = await _vmService!.getAllocationProfile(isolateId);
          final members = profile.members ?? [];
          members.sort(
            (a, b) => (b.bytesCurrent ?? 0).compareTo(a.bytesCurrent ?? 0),
          );
          final top = members.take(limit);
          final buf = StringBuffer(
            'Top $limit classes by heap usage (from ${members.length} total):\n'
            '${'Class'.padRight(40)} ${'Bytes'.padLeft(12)} ${'Instances'.padLeft(12)}\n'
            '${'-' * 66}\n',
          );
          for (final c in top) {
            if ((c.bytesCurrent ?? 0) == 0) continue;
            final name = (c.classRef?.name ?? '?').padRight(40);
            final bytes =
                ((c.bytesCurrent ?? 0) / 1024).toStringAsFixed(1).padLeft(11);
            final instances =
                '${c.instancesCurrent ?? 0}'.padLeft(12);
            buf.writeln('$name ${bytes}KB $instances');
          }
          return CallToolResult(
            content: [TextContent(text: buf.toString())],
          );
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'Allocation profile failed: $e')],
            isError: true,
          );
        }
      },
    );

    // -- get_http_profile -----------------------------------------------------
    server.registerTool(
      'get_http_profile',
      description:
          'Returns all HTTP requests made by the app — URL, method, status code, '
          'duration, and request/response size. This is the DevTools Network tab '
          'in your AI agent. Use this to debug API calls, check for slow requests '
          '(>2s), or confirm the app actually sent a request. '
          'Optional limit (default 50) caps the number of requests shown.',
      inputSchema: ToolInputSchema(
        properties: {
          'limit': JsonSchema.integer(),
          'status_filter': JsonSchema.integer(),
        },
      ),
      callback: (params, extra) async {
        final limit = (params['limit'] as int?) ?? 50;
        final statusFilter = params['status_filter'] as int?;
        final res = await _callExtensionRaw('ext.dart.io.getHttpProfile', {});
        if (res.isError) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'HTTP profile unavailable: ${res.errorMessage}\n'
                    'Note: dart:io HTTP profiling is only available in debug builds.',
              ),
            ],
          );
        }
        final requests =
            (res.data?['requests'] as List<dynamic>?) ?? [];
        var filtered = requests.cast<Map<String, dynamic>>();
        if (statusFilter != null) {
          filtered = filtered
              .where(
                (r) => (r['response'] as Map?)?['statusCode'] == statusFilter,
              )
              .toList();
        }
        if (filtered.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No HTTP requests recorded yet.')],
          );
        }
        final shown = filtered.reversed.take(limit);
        final buf = StringBuffer(
          '${filtered.length} HTTP requests (showing last $limit):\n',
        );
        for (final req in shown) {
          final method = req['method'] ?? '?';
          final uri = req['uri'] ?? '?';
          final status =
              (req['response'] as Map?)?['statusCode']?.toString() ?? '...';
          final start = req['startTime'] as int? ?? 0;
          final end = req['endTime'] as int? ?? 0;
          final durationMs = end > 0 ? '${((end - start) / 1000).round()}ms' : 'pending';
          final reqSize =
              ((req['request'] as Map?)?['contentLength'] ?? 0).toString();
          final respSize =
              ((req['response'] as Map?)?['contentLength'] ?? 0).toString();
          buf.writeln(
            '[$status] $method $uri  ⏱$durationMs  ↑${reqSize}B ↓${respSize}B',
          );
        }
        return CallToolResult(
          content: [TextContent(text: buf.toString())],
        );
      },
    );

    // -- clear_http_profile ---------------------------------------------------
    server.registerTool(
      'clear_http_profile',
      description:
          'Clears the HTTP request history so you get a clean baseline '
          'before triggering a specific API call. Pair with get_http_profile.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final res = await _callExtensionRaw(
          'ext.dart.io.clearHttpProfile',
          {},
        );
        if (res.isError) {
          return CallToolResult(
            content: [TextContent(text: 'Clear failed: ${res.errorMessage}')],
          );
        }
        return CallToolResult(
          content: [TextContent(text: 'HTTP profile cleared.')],
        );
      },
    );

    // -- get_render_tree ------------------------------------------------------
    server.registerTool(
      'get_render_tree',
      description:
          'Dumps the render object tree — the layout/paint layer beneath the '
          'widget tree. Use this to debug layout issues, overflow errors, or '
          'understand exactly how Flutter is sizing and positioning widgets. '
          'This is the DevTools Layout Explorer equivalent for AI agents.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final res = await _callExtensionRaw(
          'ext.flutter.debugDumpRenderTree',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final tree =
            res.data?['data']?.toString() ??
            res.data?['result']?.toString() ??
            jsonEncode(res.data);
        // Truncate if very large
        const maxLen = 8000;
        final out = tree.length > maxLen
            ? '${tree.substring(0, maxLen)}\n... (truncated, ${tree.length - maxLen} chars omitted)'
            : tree;
        return CallToolResult(content: [TextContent(text: out)]);
      },
    );

    // -- get_layer_tree -------------------------------------------------------
    server.registerTool(
      'get_layer_tree',
      description:
          'Dumps the compositing layer tree — the GPU-level representation of '
          'the scene. Use this to debug performance issues caused by unnecessary '
          'repaint layers, or to understand why widgets are not composited efficiently.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final res = await _callExtensionRaw(
          'ext.flutter.debugDumpLayerTree',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final tree =
            res.data?['data']?.toString() ??
            res.data?['result']?.toString() ??
            jsonEncode(res.data);
        const maxLen = 8000;
        final out = tree.length > maxLen
            ? '${tree.substring(0, maxLen)}\n... (truncated)'
            : tree;
        return CallToolResult(content: [TextContent(text: out)]);
      },
    );

    // -- get_vm_info ----------------------------------------------------------
    server.registerTool(
      'get_vm_info',
      description:
          'Returns Dart VM version, process ID, all running isolates and their '
          'pause/run state. Use this to confirm which Dart version the app is '
          'running on, or to check isolate health.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await _vmService!.getVM();
          final buf = StringBuffer();
          buf.writeln('VM version: ${vm.version ?? 'unknown'}');
          buf.writeln('PID: ${vm.pid ?? 'unknown'}');
          buf.writeln('Isolates (${vm.isolates?.length ?? 0}):');
          for (final iso in vm.isolates ?? []) {
            buf.writeln('  ${iso.name ?? iso.id} (id=${iso.id})');
          }
          return CallToolResult(content: [TextContent(text: buf.toString())]);
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'VM info failed: $e')],
            isError: true,
          );
        }
      },
    );

    // -- toggle_repaint_rainbow -----------------------------------------------
    server.registerTool(
      'toggle_repaint_rainbow',
      description:
          'Enables or disables the repaint rainbow overlay (each layer '
          'that repaints cycles through colors). Use this to visually identify '
          'which parts of the UI are repainting more than expected — '
          'a classic Flutter performance debugging technique.',
      inputSchema: ToolInputSchema(
        properties: {'enabled': JsonSchema.boolean()},
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final res = await _callExtensionRaw('ext.flutter.repaintRainbow', {
          'enabled': enabled.toString(),
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Repaint rainbow ${enabled ? 'enabled' : 'disabled'}. '
                  '${enabled ? 'Look for rapidly cycling colors on screen — those widgets repaint every frame.' : ''}',
            ),
          ],
        );
      },
    );

    // -- toggle_debug_paint ---------------------------------------------------
    server.registerTool(
      'toggle_debug_paint',
      description:
          'Enables or disables debug paint — shows layout padding (blue), '
          'widget boundaries (orange), baselines (green), and pointer hit areas. '
          'Use this to debug layout issues like unexpected padding or misaligned widgets.',
      inputSchema: ToolInputSchema(
        properties: {'enabled': JsonSchema.boolean()},
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final res = await _callExtensionRaw(
          'ext.flutter.debugPaint',
          {'enabled': enabled.toString()},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Debug paint ${enabled ? 'enabled' : 'disabled'}.',
            ),
          ],
        );
      },
    );

    // -- toggle_slow_animations -----------------------------------------------
    server.registerTool(
      'toggle_slow_animations',
      description:
          'Slows all animations to 1/5 speed (timeDilation=5) or restores '
          'normal speed (timeDilation=1). Use this to visually inspect animation '
          'curves, catch jank frames, or verify transition correctness. '
          'Set enabled=false to restore normal speed.',
      inputSchema: ToolInputSchema(
        properties: {'enabled': JsonSchema.boolean()},
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final dilation = enabled ? '5.0' : '1.0';
        final res = await _callExtensionRaw(
          'ext.flutter.timeDilation',
          {'timeDilation': dilation},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: enabled
                  ? 'Animations slowed to 1/5 speed. Call again with enabled=false to restore.'
                  : 'Animations restored to normal speed.',
            ),
          ],
        );
      },
    );

    // -- enable_widget_rebuild_tracking ---------------------------------------
    server.registerTool(
      'enable_widget_rebuild_tracking',
      description:
          'Enables or disables per-widget rebuild counting '
          '(equivalent to DevTools "Track Widget Builds"). '
          'After enabling, interact with the app, then call get_debug_logs '
          'to see rebuild events, or check the performance overlay via '
          'get_perf_metrics. Set enabled=false to stop tracking.',
      inputSchema: ToolInputSchema(
        properties: {'enabled': JsonSchema.boolean()},
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final res = await _callExtensionRaw(
          'ext.flutter.profileWidgetBuilds',
          {'enabled': enabled.toString()},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Widget rebuild tracking ${enabled ? 'enabled' : 'disabled'}. '
                  '${enabled ? 'Interact with the app, then use get_debug_logs or capture_screenshot to observe rebuild activity.' : ''}',
            ),
          ],
        );
      },
    );

    // -- get_gc_stats ---------------------------------------------------------
    server.registerTool(
      'get_gc_stats',
      description:
          'Returns garbage collection statistics for all Dart isolates: '
          'number of GC rounds, total bytes collected, and current heap pressure. '
          'High GC frequency (>5/sec) can cause jank.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await _vmService!.getVM();
          final buf = StringBuffer('GC statistics:\n');
          for (final iso in vm.isolates ?? []) {
            if (iso.id == null) continue;
            try {
              final profile = await _vmService!.getAllocationProfile(
                iso.id!,
                gc: false,
              );
              final newSpace = profile.memoryUsage;
              if (newSpace != null) {
                final used = ((newSpace.heapUsage ?? 0) / (1024 * 1024))
                    .toStringAsFixed(2);
                final cap = ((newSpace.heapCapacity ?? 0) / (1024 * 1024))
                    .toStringAsFixed(2);
                buf.writeln(
                  '  ${iso.name ?? iso.id}: heap=$used/$cap MB',
                );
              }
            } catch (_) {}
          }
          buf.writeln(
            '\nTip: use get_allocation_profile to see which classes are '
            'consuming heap, or get_memory_details for a live snapshot.',
          );
          return CallToolResult(
            content: [TextContent(text: buf.toString())],
          );
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'GC stats failed: $e')],
            isError: true,
          );
        }
      },
    );
  }

  void _registerAppTool({
    required String name,
    required String description,
    required String extension,
    Map<String, JsonSchema>? properties,
    String Function(Map<String, dynamic> json)? formatResult,
    String? nudge,
  }) {
    server.registerTool(
      name,
      description: description,
      inputSchema: ToolInputSchema(properties: properties ?? {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(extension, p);
        if (res.isError) return res.toCallToolResult();
        final text = formatResult != null
            ? formatResult(res.data!)
            : res.data.toString();
        return CallToolResult(
          content: [
            TextContent(text: nudge != null ? '$text\n\n$nudge' : text),
          ],
        );
      },
    );
  }

  Future<_ExtensionResult> _callExtensionRaw(
    String extension,
    Map<String, dynamic> parameters,
  ) async {
    if (_vmService == null) {
      if (_isReconnecting) {
        return _ExtensionResult.error(
          'VM Service is reconnecting. Please retry shortly.',
        );
      }
      return _ExtensionResult.error('No VM Service connection.');
    }
    try {
      final vm = await _vmService!.getVM().timeout(const Duration(seconds: 10));
      for (final isolateRef in vm.isolates ?? []) {
        if (isolateRef.id == null) continue;
        try {
          final response = await _vmService!
              .callServiceExtension(
                extension,
                isolateId: isolateRef.id!,
                args: Map<String, String>.from(parameters),
              )
              .timeout(const Duration(seconds: 15));
          if (response.json != null) {
            if (response.json!['error'] != null) {
              return _ExtensionResult.error(
                'Error: ${response.json!['error']}',
              );
            }
            return _ExtensionResult.success(response.json!);
          }
        } on RPCError catch (e) {
          // -32601 = method not found: extension not registered in this isolate.
          // Any other code is a real error from the extension — surface it.
          if (e.code == -32601) {
            continue;
          }
          return _ExtensionResult.error(
            e.data?['details'] as String? ?? 'Extension error: ${e.message}',
          );
        } on TimeoutException {
          return _ExtensionResult.error(
            'Extension call timed out. The app may be unresponsive.',
          );
        }
      }
    } on TimeoutException {
      return _ExtensionResult.error(
        'VM Service timed out. The app may be unresponsive.',
      );
    } on StateError catch (e) {
      _log.warning('VM Service connection error during call', e);
      _scheduleReconnect();
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
      );
    } on WebSocketException catch (e) {
      _log.warning('WebSocket error during VM Service call', e);
      _scheduleReconnect();
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
      );
    } on IOException catch (e) {
      _log.warning('IO error during VM Service call', e);
      _scheduleReconnect();
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
      );
    }
    return _ExtensionResult.error(
      'Tool not found in any isolate. Ensure you registered the plugin.',
    );
  }

  Future<void> stop() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _eventStreamSubscription?.cancel();
    _eventStreamSubscription = null;
    await _loggingStreamSubscription?.cancel();
    _loggingStreamSubscription = null;
    await _stdoutStreamSubscription?.cancel();
    _stdoutStreamSubscription = null;
    await _vmService?.dispose();
  }
}

class _ExtensionResult {
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final bool isError;
  _ExtensionResult.success(this.data) : errorMessage = null, isError = false;
  _ExtensionResult.error(this.errorMessage) : data = null, isError = true;
  CallToolResult toCallToolResult() => CallToolResult(
    content: [
      TextContent(
        text: isError
            ? (errorMessage ?? 'Unknown error')
            : jsonEncode(data ?? {}),
      ),
    ],
    isError: isError,
  );
}
