# FlutterPilot Server

The MCP (Model Context Protocol) bridge between AI agents and your running Flutter app. Exposes 82 tools via the VM service.

> **What is MCP?** The Model Context Protocol is an open standard for connecting AI models (Claude, Gemini, etc.) to external tools. FlutterPilot Server implements MCP to let AI agents see and control your Flutter app in real-time.

## Prerequisites

- **Dart SDK** >= 3.11.0
- **A running Flutter app** with `flutterpilot_sdk` initialized
- **VM Service URI** from `flutter run` output (e.g., `http://127.0.0.1:12345/abcdefg=/`)

## Quick Start

### 1. Run Your Flutter App
```bash
flutter run
```

From the output, copy the **Observatory debugger** URI:
```
An Observatory debugger and profiler on ... is available at: http://127.0.0.1:54321/abc123=/
```

### 2. Start the MCP Server
```bash
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri http://127.0.0.1:54321/abc123=/
```

**That's it!** The server is now listening on **stdin/stdout** for MCP commands.

### 3. Connect Your AI Agent (Optional)

For **Claude Desktop**:
```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": [
        "run",
        "/path/to/FlutterPilot/packages/flutterpilot_server/bin/flutterpilot_server.dart",
        "--uri",
        "http://127.0.0.1:54321/abc123=/"
      ]
    }
  }
}
```

For **Cursor IDE**:
Add to `.cursor/settings.json`:
```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": ["run", "packages/flutterpilot_server/bin/flutterpilot_server.dart", "--uri", "<vm-uri>"]
    }
  }
}
```

---

## Command-Line Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--uri <uri>` | ✅ Yes | — | VM Service URI of your running app |
| `--project-root <path>` | ❌ No | `cwd` | Project root for file reading tools (`read_dart_file`, `list_dart_files`) |
| `--allow-destructive` | ❌ No | false | Allow non-SELECT SQL queries via `query_drift_db` (use with caution!) |
| `--timeout <ms>` | ❌ No | 10000 | Tool call timeout in milliseconds |

### Examples

```bash
# Basic — read-only mode
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri http://127.0.0.1:12345/xyz=/

# With project root for file reading
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri http://127.0.0.1:12345/xyz=/ \
  --project-root /path/to/my-flutter-project

# With destructive SQL enabled (for write operations)
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri http://127.0.0.1:12345/xyz=/ \
  --allow-destructive

# Via Melos (from monorepo root)
melos run server:run -- --uri http://127.0.0.1:12345/xyz=/
```

---

## 82 MCP Tools Reference

> **Tip for AI Agents:** Call the `flutterpilot_guide` MCP prompt at the start of your session to get a structured cheat sheet covering all tools, recommended workflows, and key rules.

### 🎬 Screenshots & Layout (5 tools)

#### `capture_screenshot`
Capture the current screen as a PNG.
```json
{
  "type": "resource",
  "resource": {
    "uri": "data:image/png;base64,...",
    "mimeType": "image/png"
  }
}
```

#### `get_widget_tree`
Return the full widget hierarchy as a nested JSON structure, including layout properties.
```json
{
  "tree": {
    "type": "MaterialApp",
    "props": { "title": "My App" },
    "children": [...]
  }
}
```

#### `get_widget_properties` `key: string`
Read text, enabled state, value, and bounds from any widget by key.
```json
{
  "text": "Submit",
  "isEnabled": true,
  "isChecked": null,
  "value": null,
  "isFocused": false,
  "bounds": { "x": 100, "y": 200, "width": 150, "height": 50 }
}
```

#### `save_screenshot_baseline` `filename: string`
Save screenshot as baseline for visual regression testing.
```json
{ "saved": true, "path": "/path/to/baseline.png" }
```

#### `compare_screenshot` `filename: string`
Compare current screenshot against saved baseline.
```json
{
  "match": true,
  "diff": null,
  "percentage": 100.0
}
```

---

### 🖱️ UI Automation (15 tools)

#### `tap_at` `x: number, y: number`
Tap at specific screen coordinates.
```json
{ "success": true }
```

#### `tap_widget` `key: string`
Tap a widget at its center by key.
```json
{ "success": true, "widgetFound": true }
```

#### `double_tap_widget` `key: string`
Double-tap a widget.

#### `long_press_widget` `key: string`
Long-press a widget.

#### `enter_text` `key: string, text: string`
Fill a text field by key with the given text.
```json
{ "success": true }
```

#### `clear_text_field` `key: string`
Clear a text field by key.

#### `scroll_into_view` `key: string, duration?: number`
Scroll until a widget is visible. Optional duration in milliseconds.
```json
{ "scrolled": true }
```

#### `scroll_by` `dx: number, dy: number, duration?: number`
Scroll by pixel amount (dx = horizontal, dy = vertical).

#### `press_back`
Pop the current route (simulate hardware back button).
```json
{ "popped": true }
```

#### `set_slider_value` `key: string, value: number`
Set a slider to a numeric value (will compute tap position).
```json
{ "success": true }
```

#### `toggle_checkbox` `key: string`
Toggle a Checkbox, Switch, or Radio widget by key.

#### `focus_widget` `key: string`
Request focus on a widget (opens keyboard if TextField).

#### `unfocus_all`
Dismiss the keyboard by unfocusing all widgets.

#### `set_text_scale_factor` `scale: number`
Set accessibility text scale (1.0 = normal, 2.0 = 2× larger).
```json
{ "success": true }
```
*Note: Requires app to listen to `FlutterPilot.textScaleNotifier`*

#### `pump_frames` `count: number`
Wait for N vsync frames (useful for animations).
```json
{ "framesWaited": 60 }
```

---

### 🧭 Navigation & Routing (8 tools)

#### `navigate_to` `route: string`
Push a named route.
```json
{ "success": true }
```

#### `get_navigation_stack`
Return the route stack (bottom to top).
```json
{
  "stack": ["/", "/auth/login", "/home/dashboard"],
  "currentRoute": "/home/dashboard"
}
```

#### `simulate_deep_link` `url: string`
Trigger deep link routing (e.g., `myapp://product/123`).
```json
{ "success": true }
```

#### `set_locale` `locale: string`
Switch app language at runtime (e.g., `'en'`, `'es'`, `'pt_BR'`).
```json
{ "success": true }
```
*Note: Requires app to listen to `FlutterPilot.localeNotifier`*

#### `set_theme` `theme: 'light' | 'dark'`
Switch light/dark theme.

#### `set_device_rotation` `rotation: 'portrait' | 'landscape'`
Change device orientation.

#### `wait_for_state` `condition: string, timeout?: number`
Wait until a condition is true (e.g., `"route.contains('success')"`, `"!hasErrors"`).
```json
{ "success": true, "conditionMet": true }
```

#### `hot_reload`
Trigger hot reload on the app.
```json
{ "success": true }
```

---

### 🔍 State & Inspection (19 tools)

#### `get_app_summary`
Snapshot of app state: current route, error count, widget count, recording state.
```json
{
  "currentRoute": "/home",
  "errorCount": 0,
  "widgetCount": 152,
  "recordingActive": false,
  "fpsEstimate": 60.0
}
```

#### `get_errors`
Return all buffered Flutter errors.
```json
{
  "errors": [
    {
      "message": "NoSuchMethodError: ...",
      "stackTrace": "...",
      "timestamp": "2024-04-08T20:00:00Z"
    }
  ]
}
```

#### `diagnose_last_error`
Full diagnostic report: error, stack trace, screenshot, widget tree, state, at time of error.
```json
{
  "error": {...},
  "stack": "...",
  "screenshot": "base64-png",
  "widgetTree": {...},
  "appState": {...},
  "timestamp": "2024-04-08T20:00:00Z"
}
```

#### `get_perf_metrics`
Real-time performance metrics.
```json
{
  "fpsEstimate": 59.8,
  "frameTimes": [16.2, 16.1, 16.0],
  "memory": { "heapUsage": 45000000, "externalMemory": 12000000 },
  "refreshRate": 60.0
}
```

#### `get_semantics_tree`
Full accessibility tree (VoiceOver/TalkBack compatible).
```json
{
  "root": {
    "label": "Home Screen",
    "role": "button",
    "bounds": {...},
    "children": [...]
  }
}
```

#### `assert_widget_enabled` `key: string`
Assert that a widget is interactive (enabled, tappable, etc.).
```json
{ "enabled": true }
```

#### `assert_widget_disabled` `key: string`
Assert that a widget is disabled.
```json
{ "disabled": true }
```

#### `get_riverpod_states` *(requires flutterpilot_riverpod)*
Current state of all active Riverpod providers.
```json
{
  "providers": {
    "userProvider": { "id": 1, "name": "Alice" },
    "counterProvider": 42
  }
}
```

#### `get_bloc_states` *(requires flutterpilot_bloc)*
Current state of all active Bloc/Cubit instances.
```json
{
  "blocs": {
    "counterCubit": 42,
    "authBloc": "authenticated"
  }
}
```

#### `get_network_logs` *(requires flutterpilot_dio)*
All HTTP requests/responses captured by Dio.
```json
{
  "requests": [
    {
      "method": "GET",
      "url": "https://api.example.com/users",
      "statusCode": 200,
      "responseTime": 125,
      "response": {...}
    }
  ]
}
```

#### `query_drift_db` `sql: string` *(requires flutterpilot_drift)*
Execute a SQL query on your Drift database.
```json
{
  "rows": [
    { "id": 1, "name": "Alice", "email": "alice@example.com" }
  ]
}
```
*Supports SELECT, INSERT, UPDATE, DELETE (if `--allow-destructive`)*

#### `get_hive_contents` *(requires flutterpilot_hive)*
All key-value pairs from all registered Hive boxes.
```json
{
  "boxes": {
    "userBox": { "userKey": "Alice", "ageKey": 30 },
    "settingsBox": { "theme": "dark", "lang": "en" }
  }
}
```

#### `get_shared_preferences` *(requires flutterpilot_shared_preferences)*
Current SharedPreferences key-value map.
```json
{
  "prefs": {
    "username": "alice",
    "theme": "dark",
    "notification_count": 5
  }
}
```

#### `set_shared_preference` `key: string, value: any, type?: string` *(requires flutterpilot_shared_preferences)*
Write a value to SharedPreferences.
```json
{ "success": true, "key": "username", "value": "bob" }
```

#### `clear_shared_preferences` *(requires flutterpilot_shared_preferences)*
Clear all SharedPreferences data.
```json
{ "success": true, "cleared": true }
```

#### `get_build_config`
Return pubspec.yaml and build metadata.
```json
{
  "pubspec": {
    "name": "my_app",
    "version": "1.0.0",
    "dependencies": {...}
  },
  "buildInfo": {...}
}
```

#### `read_dart_file` `path: string` *(requires `--project-root`)*
Read a Dart source file from your project.
```json
{
  "path": "lib/main.dart",
  "content": "import 'package:flutter/material.dart';\n..."
}
```

#### `list_dart_files` `pattern?: string` *(requires `--project-root`)*
List Dart files in your project (optional glob pattern).
```json
{
  "files": [
    "lib/main.dart",
    "lib/screens/home.dart",
    "lib/widgets/button.dart"
  ]
}
```

---

### 🎬 Recording & Testing (6 tools)

#### `start_recording`
Begin recording user interactions.
```json
{ "recording": true }
```

#### `stop_and_generate_test`
Stop recording and generate a testWidgets block.
```json
{
  "testCode": "testWidgets('user flow', (tester) async {\n  await tester.pumpWidget(MyApp());\n  expect(find.text('Home'), findsOneWidget);\n  await tester.tap(find.byKey(Key('loginBtn')));\n  ...\n});",
  "actionsRecorded": 15
}
```

#### `get_latest_crash_report`
Get the most recent crash diagnostic (if auto-captured by server).
```json
{
  "crash": {
    "timestamp": "2024-04-08T20:00:00Z",
    "error": "NoSuchMethodError: ...",
    "stack": "...",
    "screenshot": "base64-png"
  }
}
```

#### `show_performance_overlay` `show: boolean`
Toggle the Flutter performance overlay on-screen.
```json
{ "success": true }
```

#### `list_custom_tools`
List all app-registered custom tools.
```json
{
  "tools": [
    { "name": "clearCache", "description": "Clear app cache" },
    { "name": "resetDatabase", "description": "Reset local DB" }
  ]
}
```

#### `call_custom_tool` `name: string, ...args`
Invoke an app-registered custom tool.
```json
{ "cleared": true }
```

---

### 🖥️ Debug Console (3 tools)

#### `get_debug_logs` `level?: string, logger?: string, limit?: number`
Retrieve captured `print()` / `debugPrint()` / `developer.log()` output from the app. Replaces manual copy-paste from VS Code Debug Console.
- `level`: filter by severity — `"verbose"`, `"info"`, `"warning"`, `"error"`, `"severe"`
- `logger`: filter by logger name (from `dart:developer log(name:...)`)
- `limit`: max entries to return (default 100)
```json
{
  "count": 5,
  "logs": [
    { "level": "info", "message": "User tapped login", "logger": "AuthBloc", "timestamp": "14:32:01.123" },
    { "level": "error", "message": "Network request failed: 401", "logger": "DioInterceptor", "timestamp": "14:32:02.456" }
  ]
}
```

#### `clear_debug_logs`
Clear the debug log buffer on both the server and the app.
```json
{ "cleared": true }
```

#### `set_log_filter`
Clear both the server and app debug log buffers (same as clear_debug_logs).
```json
{ "cleared": true }
```

---

### 🔬 DevTools Deep Inspection (12 tools)

#### `get_memory_details`
Get heap memory usage per isolate (like Flutter DevTools Memory tab).
```json
{
  "isolates": [
    {
      "id": "isolates/1",
      "name": "main",
      "heapUsage": 14680064,
      "heapCapacity": 33554432,
      "externalUsage": 2097152,
      "heapUsageMB": "14.00 MB",
      "heapCapacityMB": "32.00 MB"
    }
  ]
}
```

#### `get_allocation_profile` `limit?: number`
Show top Dart classes by current heap allocation (find memory leaks).
- `limit`: number of top classes to return (default 20)
```json
{
  "topClasses": [
    { "name": "_Uint8List", "instances": 1234, "bytes": 5242880 },
    { "name": "Image", "instances": 42, "bytes": 2097152 }
  ]
}
```

#### `get_gc_stats`
Get garbage collection pressure and heap stats.
```json
{
  "isolateId": "isolates/1",
  "heapUsage": 14680064,
  "heapCapacity": 33554432,
  "gcOldSpaceUsed": 8388608,
  "gcOldSpaceCapacity": 16777216
}
```

#### `get_http_profile` `limit?: number, status_filter?: string`
Get all HTTP requests from the Dart runtime (not just Dio — includes all `dart:io` HttpClient calls).
- `limit`: max requests to return (default 50)
- `status_filter`: filter by status — `"complete"`, `"pending"`, `"error"`
```json
{
  "count": 3,
  "requests": [
    {
      "method": "POST",
      "uri": "https://api.example.com/login",
      "statusCode": 200,
      "startTime": "14:32:01.000",
      "duration": "145ms"
    }
  ]
}
```

#### `clear_http_profile`
Reset the HTTP request profile. Call before testing a specific API flow.
```json
{ "cleared": true }
```

#### `get_render_tree`
Get the Flutter render object tree (layout constraints, sizes, positions). Equivalent to DevTools Render Tree tab.
```json
{ "renderTree": "RenderView\n  RenderPositionedBox\n    RenderPadding..." }
```

#### `get_layer_tree`
Get the Flutter compositing layer tree (GPU layer structure). Useful for finding unnecessary compositing.
```json
{ "layerTree": "TransformLayer\n  PictureLayer\n  TextLayer..." }
```

#### `get_vm_info`
Get Dart VM version, architecture, and list of all isolates.
```json
{
  "version": "3.4.0",
  "pid": 12345,
  "isolates": ["main", "worker1"]
}
```

#### `toggle_repaint_rainbow` `enabled: boolean`
Highlight layers that repaint with cycling rainbow colors (DevTools Repaint Rainbow).
```json
{ "enabled": true }
```

#### `toggle_debug_paint` `enabled: boolean`
Show layout bounds, padding, and alignment guides (DevTools Debug Paint).
```json
{ "enabled": true }
```

#### `toggle_slow_animations` `enabled: boolean`
Slow animations to 5× speed for inspection.
```json
{ "enabled": true }
```

#### `enable_widget_rebuild_tracking` `enabled: boolean`
Count how many times each widget rebuilds (find excessive rebuild issues).
```json
{ "enabled": true }
```

---



```
┌──────────────────────────────────────────────────────────────┐
│                    AI Agent (Claude, etc.)                   │
└────────────────────────┬─────────────────────────────────────┘
                         │ MCP Protocol (JSON-RPC over stdio)
                         │ Sends: {"jsonrpc": "2.0", "method": "tools/call", "params": {...}}
                         │ Receives: {"result": {...}}
┌────────────────────────▼─────────────────────────────────────┐
│                  FlutterPilot Server                          │
│  • Parses MCP request                                         │
│  • Validates params (type, range, format)                     │
│  • Calls matching tool handler                                │
│  • Gathers response (parallel Future.wait if needed)          │
│  • Formats as MCP response JSON                               │
└────────────────────────┬─────────────────────────────────────┘
                         │ VM Service Extension Calls
                         │ Calls: ext.flutterpilot.getWidgetTree
                         │ Returns: Raw Dart value (map, list, etc.)
┌────────────────────────▼─────────────────────────────────────┐
│                  Running Flutter App                          │
│  • flutterpilot_sdk registers extensions                      │
│  • Extensions return JSON-serializable values                 │
│  • Optional plugins (Riverpod, Bloc, etc.)                    │
└──────────────────────────────────────────────────────────────┘
```

---

## Configuration for MCP Clients

### Claude Desktop

Edit `~/.claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": [
        "run",
        "/absolute/path/to/FlutterPilot/packages/flutterpilot_server/bin/flutterpilot_server.dart",
        "--uri",
        "http://127.0.0.1:54321/abc123=/"
      ]
    }
  }
}
```

### VS Code with Cursor Extension

1. Install **FlutterPilot VS Code** extension (from Marketplace)
2. Run your app: `flutter run`
3. Click **"Connect FlutterPilot"** in VS Code sidebar
4. Extension auto-starts server, connects AI chat

### Programmatic (Custom MCP Client)

Use the `mcp-py` or `mcp-js` SDK:

```python
import mcp
client = mcp.StdioMcpClient("dart", [
    "run",
    "flutterpilot_server.dart",
    "--uri", "http://127.0.0.1:54321/abc=/"
])

# Call tool
result = client.call_tool("capture_screenshot", {})
print(result)  # {'resource': {'uri': 'data:image/png;base64,...', ...}}
```

---

## Important Notes

### MCP Protocol & Logging

**CRITICAL:** The server uses **stdin/stdout** for MCP JSON-RPC protocol. All logging MUST go to **stderr**, never `print()` or stdout.

The SDK initializes:
```
FlutterPilot initialized 🚀
```

All tool outputs are JSON. All logging goes to stderr.

### Tool Timeouts

- Default timeout: **10 seconds** per tool call
- Screenshots may take up to 500ms
- Database queries timeout after 10s
- Hanging VM service calls are interrupted

### Crash Detection (Self-Heal)

The server listens to the VM service. If your app crashes:
1. Server auto-captures full diagnostic (screenshot, error, state)
2. Server sends `CRITICAL APP CRASH: SELF-HEAL REQUEST` to stderr
3. Connected AI agent sees notification
4. AI can analyze and apply fixes via hot reload

---

## Troubleshooting

### "VM Service URI not found"
- Ensure app was started with `flutter run` (not `--release`)
- Copy full VM Service URI from flutter run output
- Format: `http://127.0.0.1:PORT/TOKEN=/`

### "Tool timeout exceeded"
- App may be unresponsive or blocked
- Screenshots timeout after 500ms
- Increase timeout: `--timeout 15000` (15 seconds)

### "query_drift_db: SQL injection detected"
- `--allow-destructive` requires explicit flag for writes
- SELECT queries are always allowed
- Avoid raw SQL; use Drift's query builder when possible

### "File not found: read_dart_file"
- Ensure `--project-root` is set to your Flutter project directory
- Paths are relative to project root, not absolute
- Example: `--project-root ~/my-flutter-app`

---

## Performance Tips

1. **Parallel queries** — Server batches requests (e.g., `Future.wait` for multiple tools)
2. **Screenshot caching** — Don't call `capture_screenshot` more than once per second
3. **Selective tree walks** — Use `get_widget_properties` for single widgets, not full `get_widget_tree`
4. **Avoid hot reload in loops** — Each reload takes ~2 seconds

---

## License

MIT — see [LICENSE](../../LICENSE)
