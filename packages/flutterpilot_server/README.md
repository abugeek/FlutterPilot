# FlutterPilot Server

The MCP (Model Context Protocol) bridge between AI agents and your running Flutter app. Exposes a versioned tool set via the VM service; use `get_capabilities` to discover the exact tools available at runtime.

Remote VM-service connections are blocked by default. Use `--allow-remote` only on a trusted network; optionally add `--remote-token` to require an additional token matching the VM-service URI path.

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
| `--project-root <path>` | ❌ No | `cwd` | The Flutter app's folder, to find the app `flutter run` started there |
| `--allow-destructive` | ❌ No | false | Allow tools that change app data or call real services (secure storage writes, Supabase sign-out, Firebase events). SQL stays read-only. |
| `--timeout <ms>` | ❌ No | 10000 | Tool call timeout in milliseconds |

### Examples

```bash
# Basic — read-only mode
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri http://127.0.0.1:12345/xyz=/

# With the app folder given explicitly
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

## MCP Tools Reference

64 tools; every parameter is in [TOOLS.generated.md](../../TOOLS.generated.md)
(generated from the running server). An app is shown only the tools that can
work for it: plugin tools once the app registers that plugin, `native_*` on
iOS simulators with idb, 16 tools for apps without `flutterpilot_sdk`.
Families of similar tools are one tool with a parameter (e.g. `tap_widget`
`gesture: "double"`, `wait_for` `route: ...`, `hot_reload` `restart: true`).

| Area | Tools |
|---|---|
| Connection & fleet | `connect_app`, `register_device`, `switch_device`, `list_connected_devices`, `get_capabilities`, `get_operation` |
| Seeing the app | `get_app_summary`, `get_widget_tree` (`diff`), `get_interactive_elements`, `get_widget_properties`, `inspect_widget` (source file:line, `layout`), `get_semantics_tree`, `capture_screenshot`, `get_navigation_stack` |
| Acting | `tap_widget` (`gesture`, `waitFor`), `enter_text`, `press_key` (`"back"`), `fill_form`, `execute_action_chain`, `scroll_into_view`, `swipe_widget`, `drag_widget`, `pinch_zoom`, `set_slider_value`, `toggle_checkbox`, `focus_widget`, `navigate_to` |
| Checking | `assert_widget`, `wait_for`, `compare_screenshot` (`save`), `audit_screen_health` (layout + accessibility: labels, contrast, reading order) |
| Rendering | `set_app_settings` (theme, locale, textScale, orientation, debug overlays) |
| Errors & logs | `get_errors` (`report`), `get_flight_log`, `get_debug_logs` |
| Code changes | `hot_reload` (`restart`) |
| Performance | `profile_frame_budget`, `profile_action` (CPU and janky frames per action), `get_memory_details` (`classes`, leak check with `cycle`), `get_http_profile` (`id`: headers, bodies) |
| State (Riverpod/Bloc) | `get_state`, `set_state` |
| Network (Dio) | `get_network_logs`, `mock_http_response`, `simulate_network` |
| Storage | `exec_sql_query` (Drift/sqflite), `get_hive_contents`, `get_shared_preferences`, `set_shared_preference`, `get_secure_storage`, `set_secure_storage_key` |
| Backends | `get_supabase_auth`, `query_supabase_table`, `supabase_session`, `get_firebase_auth`, `query_firestore`, `get_connectivity` |
| App-specific | `call_custom_tool` |
| iOS simulator | `native_describe_screen`, `native_tap`, `native_text`, `native_button`, `native_screenshot`, `native_open_app` |

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

If the app dies in native code (an Objective-C, Swift or Kotlin exception,
or a signal), the next tool's error says so, with the exception message.
About 20 s later, once the OS has written the crash report, it adds the
frames where the exception was thrown and the report's path. This works for
macOS, the iOS simulator and Android (`adb`); a physical iPhone keeps its
crash reports.

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

### "exec_sql_query is read-only"
- Only SELECT, WITH, PRAGMA and EXPLAIN run; change data through the app's UI

---

## Performance Tips

1. **Parallel queries** — Server batches requests (e.g., `Future.wait` for multiple tools)
2. **Screenshot caching** — Don't call `capture_screenshot` more than once per second
3. **Selective tree walks** — Use `get_widget_properties` for single widgets, not full `get_widget_tree`
4. **Avoid hot reload in loops** — Each reload takes ~2 seconds

---

## License

MIT — see [LICENSE](../../LICENSE)
