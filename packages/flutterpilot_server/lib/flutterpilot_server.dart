import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'src/fleet_manager.dart';
import 'src/self_heal_manager.dart';
import 'src/vm_discovery.dart';

part 'src/constants.dart';
part 'src/tools/app_inspection_tools.dart';
part 'src/tools/devtools_tools.dart';
part 'src/tools/navigation_tools.dart';
part 'src/tools/screenshot_tools.dart';
part 'src/tools/self_heal_tools.dart';
part 'src/tools/state_management_tools.dart';
part 'src/tools/testing_tools.dart';
part 'src/tools/plugin_integration_tools.dart';
part 'src/tools/ui_automation_tools.dart';

final _log = logging.Logger('FlutterPilotServer');

/// Base class exposing the members that tool mixins need.
abstract class _FlutterPilotServerBase {
  McpServer get server;
  String get vmServiceUri;
  bool get allowDestructive;
  Directory get _projectRoot;
  VmService? get _vmService;
  bool get _isReconnecting;
  Queue<Map<String, dynamic>> get _eventBuffer;
  Queue<Map<String, dynamic>> get _debugLogBuffer;
  Map<String, Uint8List> get _screenshotBaselines;
  SelfHealManager get _selfHealManager;
  FleetManager get _fleetManager;

  Future<bool> _connectWithUri([String? targetUri]);

  Future<_ExtensionResult> _callExtensionRaw(
    String extension,
    Map<String, dynamic> parameters,
  );

  void _registerAppTool({
    required String name,
    required String description,
    required String extension,
    Map<String, JsonSchema>? properties,
    String Function(Map<String, dynamic> json)? formatResult,
    String? nudge,
  });
}

/// FlutterPilot MCP Server — bridges AI agents to a running Flutter app.
class FlutterPilotServer extends _FlutterPilotServerBase
    with
        _AppInspectionToolsMixin,
        _UiAutomationToolsMixin,
        _NavigationToolsMixin,
        _ScreenshotToolsMixin,
        _SelfHealToolsMixin,
        _StateManagementToolsMixin,
        _TestingToolsMixin,
        _DevtoolsToolsMixin,
        _PluginIntegrationToolsMixin {
  @override
  final McpServer server;
  String? _vmServiceUri;
  @override
  String get vmServiceUri => _vmServiceUri ?? '';
  @override
  final bool allowDestructive;
  @override
  final Directory _projectRoot;
  @override
  VmService? _vmService;
  @override
  final Queue<Map<String, dynamic>> _eventBuffer = Queue();
  @override
  final Queue<Map<String, dynamic>> _debugLogBuffer = Queue();
  @override
  late final SelfHealManager _selfHealManager;
  @override
  late final FleetManager _fleetManager = FleetManager();
  @override
  final Map<String, Uint8List> _screenshotBaselines = {};

  // Reconnection state
  @override
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
    String? vmServiceUri,
    this.allowDestructive = false,
    Directory? projectRoot,
  }) : _vmServiceUri = vmServiceUri,
       _projectRoot = projectRoot ?? Directory.current,
       server = McpServer(
         Implementation(name: 'FlutterPilot', version: '0.1.0'),
         options: McpServerOptions(
           capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
         ),
       ) {
    _selfHealManager = SelfHealManager(server: server);
    _registerTools();
    _registerPrompts();
  }

  Future<void> start() async {
    try {
      await _connectToVmService();
    } catch (e) {
      _log.warning('Initial VM Service connection skipped: $e');
    }

    // Start MCP server over stdio
    final stdioTransport = StdioServerTransport();
    await server.connect(stdioTransport);
    _log.info('FlutterPilot MCP Server started 🚀');
  }

  // ---------------------------------------------------------------------------
  // VM Service connection & reconnection
  // ---------------------------------------------------------------------------

  @override
  Future<bool> _connectWithUri([String? targetUri]) async {
    if (targetUri != null && targetUri.isNotEmpty) {
      _vmServiceUri = targetUri;
    }
    if (_vmServiceUri == null || _vmServiceUri!.isEmpty) {
      _log.info('Auto-discovering running Flutter app...');
      final discovered = await VmDiscoveryService.discover(
        projectRoot: _projectRoot,
      );
      if (discovered != null) {
        _vmServiceUri = discovered;
        _log.info('Discovered VM Service: $_vmServiceUri');
      } else {
        return false;
      }
    }
    try {
      await _connectToVmService();
      return _vmService != null;
    } catch (e) {
      _log.warning('Failed to connect to VM Service: $e');
      return false;
    }
  }

  Future<void> _connectToVmService() async {
    if (_disposed) return;
    if (_vmServiceUri == null || _vmServiceUri!.isEmpty) {
      final discovered = await VmDiscoveryService.discover(
        projectRoot: _projectRoot,
      );
      if (discovered != null) {
        _vmServiceUri = discovered;
      } else {
        _log.info(
          'Standby mode: Waiting for Flutter app to launch (call connect_app or flutter run).',
        );
        return;
      }
    }
    _log.info('Connecting to VM Service: $_vmServiceUri');
    _vmService = await vmServiceConnectUri(_vmServiceUri!);
    _log.info('Connected to VM Service at $_vmServiceUri');

    _currentBackoff = _minBackoff;

    // ignore: unawaited_futures
    _vmService!.onDone
        .then((_) {
          if (!_disposed) {
            _log.warning('VM Service connection lost');
            _scheduleReconnect();
          }
        })
        .catchError((Object e) {
          if (!_disposed) {
            _log.warning('Error in VM Service done handler: $e');
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

  // ---------------------------------------------------------------------------
  // Event streaming
  // ---------------------------------------------------------------------------

  Future<void> _setupEventStreaming() async {
    if (_vmService == null) return;

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
          try {
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
            if (_eventBuffer.length > _Constants.eventBufferMax) {
              _eventBuffer.removeFirst();
            }
          } catch (e) {
            _log.warning('Error processing extension event: $e');
          }
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
      _log.fine(
        'Could not subscribe to Logging stream (may not be available): $e',
      );
    }

    try {
      await _vmService!.streamListen(EventStreams.kStdout);
      _stdoutStreamSubscription = _vmService!.onStdoutEvent.listen(
        (Event event) {
          final bytes = event.bytes;
          if (bytes == null || bytes.isEmpty) return;
          final raw = String.fromCharCodes(base64.decode(bytes)).trim();
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
      _log.fine(
        'Could not subscribe to Stdout stream (may not be available): $e',
      );
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
    if (_debugLogBuffer.length > _Constants.debugLogBufferMax) {
      _debugLogBuffer.removeFirst();
    }
  }

  static String _levelToString(int level) {
    if (level >= 1000) return 'error';
    if (level >= 900) return 'warning';
    if (level >= 800) return 'info';
    return 'debug';
  }

  // ---------------------------------------------------------------------------
  // Tool registration — delegates to category mixins
  // ---------------------------------------------------------------------------

  void _registerTools() {
    _registerAppInspectionTools();
    _registerUiAutomationTools();
    _registerNavigationTools();
    _registerScreenshotTools();
    _registerSelfHealTools();
    _registerStateManagementTools();
    _registerTestingTools();
    _registerDevtoolsTools();
    _registerPluginIntegrationTools();
  }

  // ---------------------------------------------------------------------------
  // Prompts
  // ---------------------------------------------------------------------------

  void _registerPrompts() {
    server.registerPrompt(
      'flutterpilot_guide',
      title: 'FlutterPilot Usage Guide',
      description:
          'Complete guide on how to use FlutterPilot tools effectively. '
          'Call this prompt at the start of a session to understand all 83 tools, '
          'when to use each one, and recommended workflows.',
      callback: (args, extra) async {
        return GetPromptResult(
          description: 'FlutterPilot complete usage guide',
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(
                text: '''# FlutterPilot — AI Agent Guide

You are connected to a live Flutter app via FlutterPilot (83 MCP tools).
Use this guide to understand what tools to call, when, and in what order.

## First Steps (always start here)
1. `get_app_summary` — Understand current state: route, errors, widget count
2. `capture_screenshot` — See what the user sees right now
3. `get_widget_tree` — Discover widget keys and structure for interactions

## Interaction Tools
- `tap_widget(key)` — Tap by ValueKey string (find keys via get_widget_tree)
- `tap_at(x, y)` — Tap at pixel coordinates (use screenshot to determine coords)
- `enter_text(key, text)` — Type into a text field
- `swipe_widget(key, direction, durationMs)` — Swipe gesture
- `long_press_widget(key)` — Long press
- `double_tap_widget(key)` — Double tap
- `set_slider_value(key, value)` — Move a slider
- `toggle_checkbox(key)` — Toggle checkbox/switch/radio
- `press_back` — Hardware back button

## Navigation
- `navigate_to(route)` — Go to a named route (e.g. "/home")
- `get_navigation_stack` — See current route stack
- `wait_for_route(route, timeoutMs)` — Wait for navigation to complete

## Waiting & Synchronization
- `wait_for_widget(key, timeoutMs)` — Wait for a widget to appear
- `wait_for_animation(timeoutMs)` — Wait for all animations to settle
- `wait_for_state(condition, timeoutMs)` — Wait for custom condition
- `pump_frames(count)` — Advance N animation frames manually

## Reading App State
- `get_errors` — Runtime errors caught by the app
- `get_riverpod_state(provider)` — Read a Riverpod provider value
- `get_bloc_state(cubit)` — Read a Bloc/Cubit state
- `get_shared_preferences` — Read all SharedPreferences
- `get_hive_contents` — Read Hive box data
- `get_network_logs` — Dio HTTP request/response history (requires Dio plugin)
- `get_semantics_tree` — Accessibility tree (for a11y testing)

## Debug Console (replaces manual VS Code copy-paste)
- `get_debug_logs(level, logger, limit)` — See print()/debugPrint()/developer.log() output
- `clear_debug_logs` — Clear buffer before a test
- `set_log_filter` — Clear both server + in-app log buffers

## DevTools-Level Deep Inspection
- `get_memory_details` — Heap used/capacity/external per isolate
- `get_allocation_profile(limit)` — Top Dart classes by heap bytes (find leaks)
- `get_gc_stats` — GC heap pressure
- `get_http_profile(limit, status_filter)` — ALL HTTP requests (not just Dio)
- `clear_http_profile` — Reset before testing a specific API call
- `get_render_tree` — Render object layout tree
- `get_layer_tree` — GPU compositing layers
- `get_vm_info` — Dart VM version, all isolates
- `toggle_repaint_rainbow(enabled)` — Highlight layers that repaint (perf debugging)
- `toggle_debug_paint(enabled)` — Show layout bounds and padding
- `toggle_slow_animations(enabled)` — 5x slow motion for animation inspection
- `enable_widget_rebuild_tracking(enabled)` — Count per-widget rebuilds

## Visual Testing
- `capture_screenshot` — Get current screen as image
- `save_screenshot_baseline(filename)` — Save reference image
- `compare_screenshot(filename)` — Pixel-diff against reference
- `get_widget_properties(key)` — Read widget text, enabled state, bounds

## Assertions
- `assert_widget_visible(key)` — Assert widget is on screen
- `assert_widget_enabled(key)` — Assert widget is tappable
- `assert_widget_disabled(key)` — Assert widget is disabled
- `assert_text_visible(text, exact)` — Assert text appears on screen
- `assert_widget_count(type, count)` — Assert N widgets of given type

## Performance & Overlays
- `get_perf_metrics` — FPS + heap summary
- `hot_reload` — Apply code changes without restarting
- `hot_restart` — Full app restart

## State Management Tools
- `set_riverpod_state(provider, value)` — Inject Riverpod state
- `set_bloc_state(cubit, state)` — Inject Bloc state
- `set_locale(locale)` — Switch language (e.g. "ar", "fr", "en")
- `set_theme(theme)` — Switch light/dark mode
- `set_text_scale_factor(scale)` — Test accessibility (try 2.0)

## Custom / App-Specific Tools
- `list_custom_tools` — Discover tools the developer registered
- `call_custom_tool(name, ...params)` — Execute an app-specific tool

## Recommended Workflows

### Debugging an issue
1. get_app_summary → get_errors → get_debug_logs(level:"error")
2. capture_screenshot → get_widget_tree
3. Reproduce the issue → get_debug_logs → get_http_profile

### Testing a user flow
1. clear_debug_logs → clear_http_profile (clean baseline)
2. Perform interactions with tap_widget / enter_text
3. wait_for_animation or wait_for_widget after each step
4. assert_widget_visible / assert_text_visible to verify outcome
5. capture_screenshot for visual record

### Memory leak investigation
1. get_memory_details (record baseline)
2. Navigate through the suspected screen
3. press_back to return
4. get_memory_details (compare — heap should not grow)
5. get_allocation_profile (find which class is accumulating)

### Performance debugging
1. enable_widget_rebuild_tracking(true)
2. toggle_repaint_rainbow(true)
3. Interact with the app
4. get_perf_metrics → look for FPS drops
5. toggle_slow_animations(true) to inspect animations visually

## Key Rules
- Always call get_widget_tree BEFORE tap_widget to discover correct keys
- Widget keys are ValueKey strings — they look like "loginButton", "emailField"
- After any navigation, call wait_for_animation before the next interaction
- Use get_debug_logs after any complex operation to see what the app printed
- Use get_http_profile to verify API calls actually happened
''',
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Core helpers
  // ---------------------------------------------------------------------------

  @override
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

  @override
  Future<_ExtensionResult> _callExtensionRaw(
    String extension,
    Map<String, dynamic> parameters,
  ) async {
    if (_vmService == null) {
      // Attempt quick auto-connect if disconnected
      await _connectWithUri();
      if (_vmService == null) {
        if (_isReconnecting) {
          return _ExtensionResult.error(
            'VM Service is reconnecting. Please retry shortly.',
            ErrorCategory.reconnecting,
          );
        }
        return _ExtensionResult.error(
          'No active Flutter app connection. Start your app with "flutter run" or call connect_app(uri: "...") to connect.',
          ErrorCategory.connectionLost,
        );
      }
    }
    try {
      final vm = await _vmService!.getVM().timeout(_Constants.vmServiceTimeout);
      for (final isolateRef in vm.isolates ?? []) {
        if (isolateRef.id == null) continue;
        try {
          final response = await _vmService!
              .callServiceExtension(
                extension,
                isolateId: isolateRef.id!,
                args: Map<String, String>.from(parameters),
              )
              .timeout(_Constants.extensionCallTimeout);
          if (response.json != null) {
            if (response.json!['error'] != null) {
              return _ExtensionResult.error(
                'Error: ${response.json!['error']}',
                ErrorCategory.extensionError,
              );
            }
            return _ExtensionResult.success(response.json!);
          }
        } on RPCError catch (e) {
          if (e.code == -32601) {
            final fallback = await _handleZeroCodeFallback(
              extension,
              parameters,
              isolateRef.id!,
            );
            if (fallback != null) return fallback;
            continue;
          }
          return _ExtensionResult.error(
            e.data?['details'] as String? ?? 'Extension error: ${e.message}',
            ErrorCategory.extensionError,
          );
        } on TimeoutException {
          return _ExtensionResult.error(
            'Extension call timed out. The app may be unresponsive.',
            ErrorCategory.timeout,
          );
        }
      }
      return _ExtensionResult.error(
        'Extension "$extension" is not registered in the running Flutter app. If this is a plugin or deep state tool, run "flutterpilot init" to install matching packages.',
        ErrorCategory.extensionError,
      );
    } on TimeoutException {
      return _ExtensionResult.error(
        'VM Service timed out. The app may be unresponsive.',
        ErrorCategory.timeout,
      );
    } on StateError catch (e) {
      _log.warning('VM Service connection error during call', e);
      _scheduleReconnect();
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
        ErrorCategory.connectionLost,
      );
    } on WebSocketException catch (e) {
      _log.warning('WebSocket error during VM Service call', e);
      _scheduleReconnect();
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
        ErrorCategory.connectionLost,
      );
    } on IOException catch (e) {
      _log.warning('IO error during VM Service call', e);
      _scheduleReconnect();
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
        ErrorCategory.connectionLost,
      );
    }
  }

  Future<_ExtensionResult?> _handleZeroCodeFallback(
    String extension,
    Map<String, dynamic> parameters,
    String isolateId,
  ) async {
    if (_vmService == null) return null;
    try {
      if (extension == 'ext.flutterpilot.getSummary') {
        final vm = await _vmService!.getVM();
        final memory = await _vmService!.getMemoryUsage(isolateId);
        return _ExtensionResult.success({
          'sdkMode': 'zero-code (core Flutter VM)',
          'status': 'connected',
          'flutterVersion': vm.version ?? 'Unknown',
          'isolateCount': vm.isolates?.length ?? 1,
          'memory': {
            'heapUsageMb':
                ((memory.heapUsage ?? 0) / (1024 * 1024)).toStringAsFixed(1),
            'heapCapacityMb':
                ((memory.heapCapacity ?? 0) / (1024 * 1024)).toStringAsFixed(1),
          },
          'hint':
              'Running in Zero-Code mode. Install flutterpilot_sdk to unlock deep state inspection (Riverpod, Bloc, Drift, Dio) and deterministic key tapping.',
        });
      } else if (extension == 'ext.flutterpilot.hotReload') {
        await _vmService!.callServiceExtension(
          'ext.flutter.reassemble',
          isolateId: isolateId,
        );
        return _ExtensionResult.success({'status': 'hot_reload_applied'});
      } else if (extension == 'ext.flutterpilot.getWidgetTree') {
        final res = await _vmService!.callServiceExtension(
          'ext.flutter.inspector.getRootWidgetTree',
          isolateId: isolateId,
          args: {'isSummaryTree': 'true'},
        );
        if (res.json != null) {
          return _ExtensionResult.success(res.json!);
        }
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Internal DTO for VM extension call results
// ---------------------------------------------------------------------------

/// Category of error returned by a tool call, enabling AI agents to decide
/// whether to retry, call a different tool, or report the failure.
enum ErrorCategory {
  /// The VM Service connection is not available.
  connectionLost,

  /// The VM Service is currently reconnecting — retry shortly.
  reconnecting,

  /// The extension call timed out (app may be unresponsive).
  timeout,

  /// The requested extension was not found in any isolate.
  toolNotFound,

  /// The extension returned an application-level error.
  extensionError,

  /// Input validation failed (missing/invalid parameters).
  validation,
}

class _ExtensionResult {
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final bool isError;
  final ErrorCategory? errorCategory;
  _ExtensionResult.success(this.data)
    : errorMessage = null,
      isError = false,
      errorCategory = null;
  _ExtensionResult.error(this.errorMessage, [this.errorCategory])
    : data = null,
      isError = true;
  CallToolResult toCallToolResult() => CallToolResult(
    content: [
      TextContent(
        text: isError
            ? (errorCategory != null
                  ? '[${errorCategory!.name}] ${errorMessage ?? 'Unknown error'}'
                  : (errorMessage ?? 'Unknown error'))
            : jsonEncode(data ?? {}),
      ),
    ],
    isError: isError,
  );
}
