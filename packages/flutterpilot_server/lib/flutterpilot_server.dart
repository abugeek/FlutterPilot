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
  VmService? _vmService;
  final List<Map<String, dynamic>> _eventBuffer = [];
  late final SelfHealManager _selfHealManager;
  final Map<String, Uint8List> _screenshotBaselines = {};

  // Reconnection state
  bool _isReconnecting = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  StreamSubscription<Event>? _eventStreamSubscription;
  Duration _currentBackoff = const Duration(seconds: 1);
  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);
  static final Random _random = Random();

  FlutterPilotServer({
    required this.vmServiceUri,
    this.allowDestructive = false,
  }) : server = McpServer(
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
