# FlutterPilot AI Assistant Guidelines

FlutterPilot is an AI-native runtime introspection, active control, and autonomous testing toolkit for Flutter applications, exposing 110+ MCP tools over the Model Context Protocol.

## 🚀 CLI & Zero-Code Mode

- **1-Command Setup**: Run `flutterpilot init` in any Flutter project root to auto-detect Riverpod/Bloc/Dio/Drift and configure packages.
- **Unified Dev Runner**: Run `flutterpilot dev` to launch the Flutter app and automatically hook the FlutterPilot MCP Server.
- **Zero-Code Mode**: Works out of the box even without `flutterpilot_sdk` by gracefully falling back to native Flutter VM inspector, debug paint, animation controls, GC profiler, and hot reload.

## Core Principles & Recommended Workflows

When interacting with a Flutter app using FlutterPilot:

### 1. Orientation & Diagnostics
- **First Step**: Call `get_app_summary` to discover the current route, widget count, active plugins, and runtime errors.
- **Visual Inspection**: Use `capture_screenshot` to view the screen layout with coordinates.
- **Hierarchy Inspection**: Use `get_widget_tree` to map out semantic widget selectors and hierarchy. PII and passwords are automatically redacted.

### 2. UI Interaction & Virtual Semantic Keys
- **No Manual Keys Needed**: You can interact with widgets using:
  - **Explicit Keys**: `tap_widget(key: "login_button")`
  - **Semantic Selectors**: `tap_widget(key: "ElevatedButton['Log In']")` or `enter_text(key: "TextField['Email']", text: "user@test.com")`
  - **Visible Text**: `tap_widget(key: "Log In")`
  - **Tooltips**: `tap_widget(key: "Tooltip['Settings']")`
- **AI Visual Overlay**: When AI interacts, a visual ripple and `🤖 AI Tap` badge pulse on screen for live human observation.
- **Scroll Before Tapping**: Use `scroll_into_view(key: "...")` if a widget is below the fold.
- **Wait for Settle**: Call `pump_frames(count: 10)` or `wait_for_route(route: "...")` after navigation.

### 3. Visual Regression Diff Engine
- Establish golden baselines with `save_screenshot_baseline(name: "...")`.
- After code modifications or UI updates, run `compare_screenshot(name: "...")` to get automated diff percentages and pixel-by-pixel highlighted diff images on regression.

### 4. Network Chaos & Mocking
- **Mock Responses**: Use `mock_http_response(urlPattern: "...", statusCode: 500, body: '{"error":"server_down"}')` to test failure handling without a backend.
- **Network Conditioning**: Call `simulate_network_condition(condition: "slow_3g"|"offline"|"normal")` or `simulate_offline(enabled: true)`.
- **Verify Logs**: Call `get_network_logs` to inspect HTTP request/response payloads.

### 5. Multi-Device Fleet Testing
- Use `list_connected_devices` to see all running Flutter instances across iOS, Android, and Web.
- Use `switch_device(id: "...")` to toggle target device on the fly.

### 6. Self-Healing & Error Recovery Loop
1. When an unhandled crash occurs, read `get_errors` or `diagnose_last_error`.
2. Review the stack trace and failing widget tree.
3. Apply the code fix in the Dart source files.
4. Call `hot_reload` to push the fix immediately to the running app.
5. Re-verify the flow to confirm recovery.
