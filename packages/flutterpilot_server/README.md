# FlutterPilot Server

The MCP (Model Context Protocol) server for FlutterPilot — the bridge between AI agents and your running Flutter app.

## Prerequisites

- Dart SDK >= 3.11.0
- A running Flutter app with `flutterpilot_sdk` initialized
- The VM Service URI from `flutter run` output

## Quick Start

```bash
# From the monorepo root
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri <vm-service-uri>

# Or via Melos
melos run server:run -- --uri <vm-service-uri>
```

The VM Service URI is printed when you run `flutter run`:
```
An Observatory debugger and profiler on ... is available at: http://127.0.0.1:XXXXX/YYYY=/
```

## Options

| Flag | Description |
|------|-------------|
| `--uri <uri>` | **Required.** The VM Service URI of your running Flutter app |
| `--allow-destructive` | Enable write SQL queries via the Drift plugin (default: read-only) |

## How It Works

The server connects to your Flutter app's VM Service and exposes 30+ MCP tools:

```
AI Agent ←→ MCP Protocol (JSON-RPC over stdio) ←→ FlutterPilot Server ←→ VM Service ←→ Your App
```

## Tools Included

### Inspection
- `get_app_summary` — Overall status: current route, error count, widget count
- `diagnose_last_error` — 360° error report with state and stack trace
- `get_widget_tree` — Full widget hierarchy with layout positions
- `get_navigation_stack` — Current route stack
- `get_perf_metrics` — Real-time FPS

### State Management
- `get_riverpod_states` / `get_bloc_states` — Current provider/bloc state
- `set_state` — Inject state into riverpod/bloc at runtime
- `get_network_logs` — Dio HTTP traffic log
- `query_drift_db` — SQL queries against Drift databases
- `get_hive_contents` — Dump Hive box contents

### Visual & UI Automation
- `capture_screenshot` — PNG screenshot as MCP Image response
- `tap_at(x,y)` / `tap_widget(key)` — Simulate taps
- `enter_text(key, text)` — Fill text fields
- `scroll_into_view(key)` — Scroll to a widget
- `navigate_to(route)` — Push a named route

### Testing & Recording
- `start_recording` / `stop_and_generate_test` — Record taps → generate test code

### Development
- `hot_reload` — Apply code changes to running app
- `set_theme` — Switch between light/dark mode
- `set_locale` — Change app locale at runtime
- `show_performance_overlay` — Toggle performance overlay

### Self-Heal
- `get_latest_crash_report` — Full diagnostic report after a crash
- Automatic crash detection sends `CRITICAL APP CRASH` notifications to the AI agent

## MCP Configuration

To use with an MCP-compatible AI tool (Claude, Cursor, etc.), add to your MCP config:

```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": ["run", "path/to/flutterpilot_server/bin/flutterpilot_server.dart", "--uri", "<vm-service-uri>"]
    }
  }
}
```

## Important Notes

- The server uses **stdin/stdout** for MCP protocol communication — all logging goes to stderr
- Tool calls timeout after 10-15 seconds if the app is unresponsive
- Self-heal crash detection is automatic and sends MCP logging notifications
