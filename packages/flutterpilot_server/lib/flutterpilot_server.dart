import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'src/self_heal_manager.dart';

class FlutterPilotServer {
  final McpServer server;
  final String vmServiceUri;
  final bool allowDestructive;
  VmService? _vmService;
  final List<Map<String, dynamic>> _eventBuffer = [];
  late final SelfHealManager _selfHealManager;

  FlutterPilotServer({required this.vmServiceUri, this.allowDestructive = false})
      : server = McpServer(
          Implementation(name: 'FlutterPilot', version: '0.0.1'),
          options: McpServerOptions(
            capabilities: ServerCapabilities(
              tools: ServerCapabilitiesTools(),
            ),
          ),
        ) {
    _selfHealManager = SelfHealManager(server: server);
    _registerTools();
  }

  Future<void> start() async {
    stderr.writeln('Connecting to VM Service: $vmServiceUri');
    _vmService = await vmServiceConnectUri(vmServiceUri);
    stderr.writeln('Connected to VM Service!');

    await _setupEventStreaming();

    // Start MCP server over stdio
    final stdioTransport = StdioServerTransport();
    await server.connect(stdioTransport);
    stderr.writeln('FlutterPilot MCP Server started 🚀');
  }

  Future<void> _setupEventStreaming() async {
    if (_vmService == null) return;
    try {
      await _vmService!.streamListen(EventStreams.kExtension);
      _vmService!.onExtensionEvent.listen(
        (Event event) async {
        final timestamp = DateTime.now().toIso8601String();
        if (event.extensionKind == 'ext.flutterpilot.error') {
          final exception = event.extensionData?.data['exception']?.toString() ?? 'Unknown Exception';
          _eventBuffer.add({'type': 'error', 'timestamp': timestamp, 'data': event.extensionData?.data});
          
          await _selfHealManager.handleCrash(
            exception: exception,
            callExtension: (ext) async {
              final res = await _callExtensionRaw(ext, {});
              return res.isError ? 'N/A' : res.data;
            },
          );

        } else if (event.extensionKind == 'ext.flutterpilot.action') {
          _eventBuffer.add({'type': 'action', 'timestamp': timestamp, 'data': event.extensionData?.data});
        }
        if (_eventBuffer.length > 50) _eventBuffer.removeAt(0);
      },
      onError: (Object error) {
        stderr.writeln('Extension event stream error: $error');
      },
      );
    } catch (e) {
      stderr.writeln('Warning: Could not subscribe to extension stream: $e');
    }
  }

  void _registerTools() {
    _registerAppTool(
      name: 'get_app_summary', 
      description: 'Get a 360-degree high-level status of the application. CALL THIS TOOL FIRST upon connecting to find your bearings, identify the current screen, and see if there are any pending errors.', 
      extension: 'ext.flutterpilot.getSummary',
      nudge: 'HINT: Now that you have the summary, use get_widget_tree to find interactable elements or capture_screenshot to see the UI.'
    );

    server.registerTool('get_self_heal_status', 
      description: 'Check if the application is currently in an unstable/crash state. Use this to verify if your last fix worked or if a new crash was intercepted.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final status = _selfHealManager.isUnstable ? '🚨 UNSTABLE' : '✅ STABLE';
        return CallToolResult(content: [TextContent(text: 'Current App Status: $status')]);
      }
    );

    server.registerTool('get_latest_crash_report', 
      description: 'Retrieve the most recent structured crash report. CALL THIS immediately if you receive a Self-Heal notification or if `get_self_heal_status` returns UNSTABLE.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = _selfHealManager.lastCrashReport;
        if (report == null) return CallToolResult(content: [TextContent(text: 'No crash reports available.')]);
        return CallToolResult(content: [TextContent(text: report.toMarkdown())]);
      }
    );

    _registerAppTool(
      name: 'get_errors', 
      description: 'Retrieve the most recent unhandled exceptions and stack traces. CALL THIS whenever you suspect a crash or logic failure.', 
      extension: 'ext.flutterpilot.getErrors',
      formatResult: (json) {
        final errors = json['errors'] as List?;
        if (errors == null || errors.isEmpty) return 'No recent errors found.';
        return errors.map((e) => '--- Error ---\n${e['exception']}\n${e['timestamp']}\n${e['stackTrace']}').join('\n\n');
      },
      nudge: 'HINT: Analyze the stack trace to find the failing file, then use get_widget_tree to see the state of the UI at failure.'
    );

    _registerAppTool(
      name: 'get_riverpod_state', 
      description: 'Inspect the current values of all active Riverpod providers. CALL THIS to debug data flow, authentication status, or to verify if a state update occurred after an action.', 
      extension: 'ext.flutterpilot.getRiverpodStates',
      formatResult: (json) {
        final states = json['states'] as Map?;
        if (states == null || states.isEmpty) return 'No observed Riverpod providers. Ensure RiverpodPilotObserver is registered.';
        return states.entries.map((e) => '${e.key}: ${e.value['value']} (${e.value['type']})').join('\n');
      }
    );

    _registerAppTool(
      name: 'get_bloc_state', 
      description: 'Inspect the current states of all active Blocs and Cubits. CALL THIS to verify business logic transitions.', 
      extension: 'ext.flutterpilot.getBlocStates',
      formatResult: (json) {
        final states = json['states'] as Map?;
        if (states == null || states.isEmpty) return 'No observed Blocs. Ensure BlocPilotObserver is registered.';
        return states.entries.map((e) => '${e.key}: ${e.value['state']} (${e.value['type']})').join('\n');
      }
    );

    _registerAppTool(
      name: 'get_network_logs', 
      description: 'View the last 50 HTTP requests and responses. CALL THIS if an API call failed or to verify network payload accuracy.', 
      extension: 'ext.flutterpilot.getNetworkLogs',
      formatResult: (json) {
        final logs = json['logs'] as List?;
        if (logs == null || logs.isEmpty) return 'No network traffic captured.';
        return logs.map((l) => '[${l['timestamp']}] ${l['type'].toUpperCase()} ${l['method'] ?? ''} ${l['uri']} ${l['statusCode'] ?? ''}').join('\n');
      }
    );

    _registerAppTool(
      name: 'get_navigation_stack', 
      description: 'Show the current navigation history (stack). CALL THIS to understand where the user is in the application flow.', 
      extension: 'ext.flutterpilot.getNavigationStack',
      formatResult: (json) => 'Navigation Stack: ${json['stack']?.join(' -> ') ?? 'Empty'}',
    );

    server.registerTool('set_riverpod_state', 
      description: 'Inject a new state into a Riverpod provider. Use the provider name (type) from `get_riverpod_state`. The `value` should be a JSON-compatible representation of the new state.', 
      inputSchema: ToolInputSchema(properties: {
        'name': JsonSchema.string(), 
        'value': JsonSchema.object()
      }, required: ['name', 'value']),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setState', {
        'type': 'riverpod',
        'name': p['name'],
        'value': json.encode(p['value'])
      }).then((res) => res.toCallToolResult())
    );

    server.registerTool('set_bloc_state', 
      description: 'Force a new state into a Bloc or Cubit. Use the Bloc name from `get_bloc_state`. The `state` should be a JSON representation of the new state.', 
      inputSchema: ToolInputSchema(properties: {
        'name': JsonSchema.string(), 
        'state': JsonSchema.object()
      }, required: ['name', 'state']),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setState', {
        'type': 'bloc',
        'name': p['name'],
        'value': json.encode(p['state'])
      }).then((res) => res.toCallToolResult())
    );

    _registerAppTool(
      name: 'get_widget_tree', 
      description: 'Retrieve the complete widget hierarchy with exact screen coordinates (x, y, width, height) and source code locations (file/line). CALL THIS to locate buttons to tap or to debug layout overflows.', 
      extension: 'ext.flutterpilot.getWidgetTree',
      nudge: 'HINT: You can now use tap_widget(key) or enter_text(key) using the keys found in this tree.'
    );

    _registerAppTool(
      name: 'get_hive_contents', 
      description: 'Dump the contents of all registered Hive boxes. CALL THIS to verify local persistent storage.', 
      extension: 'ext.flutterpilot.getHiveContents'
    );

    _registerAppTool(
      name: 'list_drift_tables', 
      description: 'List all tables in the SQLite (Drift) database.', 
      extension: 'ext.flutterpilot.listDriftTables', 
      properties: {'dbName': JsonSchema.string()}
    );

    _registerAppTool(
      name: 'list_custom_tools', 
      description: 'Discover additional app-specific tools registered by the developer.', 
      extension: 'ext.flutterpilot.listCustomTools'
    );

    server.registerTool('get_recent_events', 
      description: 'Retrieves the last 50 proactive events (errors, taps, state changes) from the stream. Use this to catch up on what happened while you were processing or if the user interacted with the app manually.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_eventBuffer.isEmpty) return CallToolResult(content: [TextContent(text: 'No recent events.')]);
        return CallToolResult(content: [TextContent(text: _eventBuffer.map((ev) => '[${ev['timestamp']}] ${ev['type']}: ${ev['data']}').join('\n'))]);
      }
    );

    server.registerTool('query_drift', 
      description: 'Execute a raw SQL SELECT query on the local database. CALL THIS to verify complex data relationships or transaction history.', 
      inputSchema: ToolInputSchema(properties: {'dbName': JsonSchema.string(), 'sql': JsonSchema.string()}, required: ['dbName', 'sql']),
      callback: (params, extra) async {
        final sql = (params['sql'] as String).trim();
        final sqlUpper = sql.toUpperCase();
        final isReadOnly = sqlUpper.startsWith('SELECT') || sqlUpper.startsWith('EXPLAIN') || sqlUpper.startsWith('PRAGMA');
        if (!allowDestructive && !isReadOnly) {
          return CallToolResult(content: [TextContent(text: 'Security: Only SELECT/EXPLAIN/PRAGMA queries are allowed. Start server with --allow-destructive to enable write operations.')], isError: true);
        }
        final res = await _callExtensionRaw('ext.flutterpilot.queryDrift', params);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(content: [
          TextContent(text: 'Results:\n${res.data!['results']}\n\nHINT: If data is missing, check get_network_logs to see if the last sync failed.')
        ]);
      }
    );

    server.registerTool('call_custom_tool', 
      description: 'Executes an app-specific tool defined by the developer. CALL THIS if you see a relevant tool listed in `list_custom_tools`.', 
      inputSchema: ToolInputSchema(properties: {'name': JsonSchema.string(), 'params': JsonSchema.object()}, required: ['name']),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.callCustomTool', p).then((res) => res.toCallToolResult())
    );

    server.registerTool('tap_at', 
      description: 'Simulates a physical tap at specific (x, y) coordinates. Prefer `tap_widget` if you have a Key.', 
      inputSchema: ToolInputSchema(properties: {'x': JsonSchema.number(), 'y': JsonSchema.number()}, required: ['x', 'y']),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapAt', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(content: [TextContent(text: 'Tap successful. HINT: Use get_navigation_stack or get_riverpod_state to see if the app responded.')]);
      }
    );

    server.registerTool('tap_widget', 
      description: 'Finds a widget by its Key and taps its center. HINT: Use `get_widget_tree` to find the Key first. After tapping, you should verify state changes.', 
      inputSchema: ToolInputSchema(properties: {'key': JsonSchema.string()}, required: ['key']),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(content: [TextContent(text: 'Widget tapped. HINT: The UI should have changed. Use capture_screenshot to verify.')]);
      }
    );

    server.registerTool('enter_text', 
      description: 'Types text into a TextField identified by a Key. Automatically handles controller updates and change notifications.', 
      inputSchema: ToolInputSchema(properties: {'key': JsonSchema.string(), 'text': JsonSchema.string()}, required: ['key', 'text']),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.enterText', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(content: [TextContent(text: 'Text entered. HINT: You may need to tap a "Submit" or "Save" button now.')]);
      }
    );

    server.registerTool('scroll_into_view', 
      description: 'Ensures a widget is visible by scrolling its parent list. Use this before tapping a widget that might be off-screen.', 
      inputSchema: ToolInputSchema(properties: {'key': JsonSchema.string()}, required: ['key']),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.scrollIntoView', p).then((res) => res.toCallToolResult())
    );

    server.registerTool('navigate_to', 
      description: 'Programmatically pushes a named route. Useful for jumping directly to a feature screen for testing.', 
      inputSchema: ToolInputSchema(properties: {'route': JsonSchema.string()}, required: ['route']),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.navigateTo', p).then((res) => res.toCallToolResult())
    );

    server.registerTool('start_recording', 
      description: 'Starts recording manual interactions. User should perform the flow in the app while this is active.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.startRecording', {}).then((res) => res.toCallToolResult())
    );

    server.registerTool('stop_and_generate_test', 
      description: 'Stops recording and returns a log of actions. Use your LLM capability to convert this log into a Flutter `testWidgets` block.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.stopRecording', {});
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(content: [TextContent(text: 'Recorded Actions (Convert to Test):\n${jsonEncode(res.data?['actions'])}\n\nHINT: Create a new file in the test/ directory and paste this as a testWidgets block.')], isError: false);
      }
    );

    server.registerTool('capture_screenshot', 
      description: 'Capture a vision-ready image of the current screen. CALL THIS to analyze layout, colors, or visual glitches. HINT: Compare with `get_widget_tree` for coordinate-perfect reasoning.', 
      inputSchema: ToolInputSchema(properties: {'format': JsonSchema.string(enumValues: ['png', 'webp'])}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.captureScreenshot', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(content: [
          ImageContent(data: res.data!['data'], mimeType: 'image/png'),
          TextContent(text: 'Screenshot captured. HINT: If you see an error overlay, call diagnose_last_error immediately.')
        ]);
      }
    );

    server.registerTool('hot_reload', 
      description: 'Trigger a source code hot reload. CALL THIS after you have modified a .dart file to apply the fix to the running app.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_vmService == null) return CallToolResult(content: [TextContent(text: 'Not connected')], isError: true);
        final vm = await _vmService!.getVM();
        final mainIsolateId = vm.isolates?.first.id;
        if (mainIsolateId == null) return CallToolResult(content: [TextContent(text: 'No main isolate found')], isError: true);
        try {
          await _vmService!.reloadSources(mainIsolateId);
          await _vmService!.callServiceExtension('ext.flutter.reassemble', isolateId: mainIsolateId);
          _selfHealManager.reset();
          return CallToolResult(content: [TextContent(text: 'Hot Reload successful! HINT: Now call get_self_heal_status to verify the fix.')]);
        } catch (err) {
          return CallToolResult(content: [TextContent(text: 'Hot Reload failed: $err')], isError: true);
        }
      }
    );

    server.registerTool('hot_restart', 
      description: 'Trigger a full app hot restart. CALL THIS for structural code changes (main(), providers) or to reset app state.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_vmService == null) return CallToolResult(content: [TextContent(text: 'Not connected')], isError: true);
        final vm = await _vmService!.getVM();
        final mainIsolateId = vm.isolates?.first.id;
        if (mainIsolateId == null) return CallToolResult(content: [TextContent(text: 'No main isolate found')], isError: true);
        try {
          await _vmService!.callServiceExtension('ext.flutter.hotRestart', isolateId: mainIsolateId);
          _selfHealManager.reset();
          return CallToolResult(content: [TextContent(text: 'Hot Restart triggered! HINT: App state is reset. Use get_app_summary to re-orient.')]);
        } catch (err) {
          return CallToolResult(content: [TextContent(text: 'Hot Restart failed: $err')], isError: true);
        }
      }
    );

    server.registerTool('set_theme', 
      description: 'Toggle Light/Dark mode. Use this to verify design consistency across themes.', 
      inputSchema: ToolInputSchema(properties: {'theme': JsonSchema.string(enumValues: ['light', 'dark'])}, required: ['theme']),
      callback: (p, e) {
        final val = p['theme'] == 'dark' ? 'Brightness.dark' : 'Brightness.light';
        return _callExtensionRaw('ext.flutter.brightnessOverride', {'value': val}).then((res) => res.toCallToolResult());
      }
    );

    server.registerTool('set_locale', 
      description: 'Switch app language (e.g., "en", "de_DE"). Use this to check for text overflows in different languages.', 
      inputSchema: ToolInputSchema(properties: {'locale': JsonSchema.string()}, required: ['locale']),
      callback: (p, e) => _callExtensionRaw('ext.flutterpilot.setLocale', p).then((res) => res.toCallToolResult())
    );

    server.registerTool('get_perf_metrics', 
      description: 'Get current FPS and Heap Memory usage. CALL THIS to verify that code optimizations actually improved performance.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final fpsRes = await _callExtensionRaw('ext.flutterpilot.getPerfMetrics', {});
        String memory = 'N/A';
        if (_vmService != null) {
          final vm = await _vmService!.getVM();
          final usage = await _vmService!.getMemoryUsage(vm.isolates!.first.id!);
          memory = '${((usage.heapUsage ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB';
        }
        return CallToolResult(content: [TextContent(text: 'FPS: ${fpsRes.data?['fps'] ?? 'N/A'}\nHeap: $memory\n\nHINT: If FPS is below 60, use show_performance_overlay to find heavy build cycles.')]);
      }
    );

    server.registerTool('diagnose_last_error', 
      description: '[DEPRECATED] Use `get_latest_crash_report` instead for better structured data.', 
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = _selfHealManager.lastCrashReport;
        if (report == null) return CallToolResult(content: [TextContent(text: 'No crash reports available.')]);
        return CallToolResult(content: [TextContent(text: report.toMarkdown())]);
      }
    );
  }

  void _registerAppTool({required String name, required String description, required String extension, Map<String, JsonSchema>? properties, String Function(Map<String, dynamic> json)? formatResult, String? nudge}) {
    server.registerTool(name, description: description, inputSchema: ToolInputSchema(properties: properties ?? {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(extension, p);
        if (res.isError) return res.toCallToolResult();
        final text = formatResult != null ? formatResult(res.data!) : res.data.toString();
        return CallToolResult(content: [TextContent(text: nudge != null ? '$text\n\n$nudge' : text)]);
      }
    );
  }

  Future<_ExtensionResult> _callExtensionRaw(String extension, Map<String, dynamic> parameters) async {
    if (_vmService == null) return _ExtensionResult.error('No VM Service connection.');
    try {
      final vm = await _vmService!.getVM().timeout(const Duration(seconds: 10));
      for (final isolateRef in vm.isolates ?? []) {
        if (isolateRef.id == null) continue;
        try {
          final response = await _vmService!
              .callServiceExtension(extension, isolateId: isolateRef.id!, args: Map<String, String>.from(parameters))
              .timeout(const Duration(seconds: 15));
          if (response.json != null) {
            if (response.json!['error'] != null) return _ExtensionResult.error('Error: ${response.json!['error']}');
            return _ExtensionResult.success(response.json!);
          }
        } on RPCError {
          // Extension not registered in this isolate — try the next one.
          continue;
        } on TimeoutException {
          return _ExtensionResult.error('Extension call timed out. The app may be unresponsive.');
        }
      }
    } on TimeoutException {
      return _ExtensionResult.error('VM Service timed out. The app may be unresponsive.');
    }
    return _ExtensionResult.error('Tool not found in any isolate. Ensure you registered the plugin.');
  }

  Future<void> stop() async => await _vmService?.dispose();
}

class _ExtensionResult {
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final bool isError;
  _ExtensionResult.success(this.data) : errorMessage = null, isError = false;
  _ExtensionResult.error(this.errorMessage) : data = null, isError = true;
  CallToolResult toCallToolResult() => CallToolResult(content: [TextContent(text: errorMessage ?? 'Unknown')], isError: isError);
}
