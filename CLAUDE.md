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
- **Trust the response — don't reflexively re-verify**: `tap_widget`, `enter_text`, `toggle_checkbox`, `swipe_widget`, `drag_widget`, `fill_form`, and `execute_action_chain` all report their own postcondition in the same response: whether the route changed, plus a capped widget-tree diff (counts + a few sample nodes) of what actually changed on screen. Read that response before reaching for `get_widget_tree` or `capture_screenshot` — most of the time it already answers "did this work." Only fall back to a screenshot when the response says nothing changed but you expected a purely visual effect (color, animation frame) with no structural diff.
- **Prefer one batched call over a tap→check→tap loop**: when the sequence of steps is already known, use `execute_action_chain`, `fill_form_batch`, `tap_and_wait`, or `enter_text_and_submit` instead of separate `tap_widget`/`enter_text` calls. Each one executes natively inside the Flutter engine and returns a single combined result — this is the single biggest latency lever available: it turns N agent turns into 1.

### 3. Fast Verification — assert_* over flutter test
- For "did my change actually work" checks, use the in-process assertion tools against the *already-running* app: `assert_widget_visible(key)`, `assert_text_visible(text)`, `assert_widget_count(type, count)`, `assert_widget_enabled(key)` / `assert_widget_disabled(key)`. These run in milliseconds — no new process, no cold VM boot.
- Do **not** reach for `generate_repro_test` + `flutter test` for routine verification. That path exists specifically for crash-repro workflows (see §8) and spins up a whole separate `flutter test` process, which will always be far slower than an assert_* call or the delta already returned by the action you just took (§2).
- `audit_screen_health` and `run_chaos_fuzzing` are for layout/accessibility and stability sweeps, not for confirming a single interaction.

### 4. Time-Travel State Snapshots (<100ms Rewind)
- Save checkpoint state: `save_state_snapshot(name: "checkout_filled")`.
- Rewind anytime without restart: `restore_state_snapshot(name: "checkout_filled")`.
- List saved snapshots: `list_state_snapshots`.

### 5. Visual Regression Diff Engine
- Establish golden baselines with `save_screenshot_baseline(name: "...")`.
- After code modifications or UI updates, run `compare_screenshot(name: "...")` to get automated diff percentages and pixel-by-pixel highlighted diff images on regression.
- Prefer this (or the inline widget-tree diff from §2) over a bare `capture_screenshot` when you specifically need to know *what* changed, not just *that* something looks different.

### 6. Network Chaos & Mocking
- **Mock Responses**: Use `mock_http_response(urlPattern: "...", statusCode: 500, body: '{"error":"server_down"}')` to test failure handling without a backend.
- **Network Conditioning**: Call `simulate_network_condition(condition: "slow_3g"|"offline"|"normal")` or `simulate_offline(enabled: true)`.
- **Verify Logs**: Call `get_network_logs` to inspect HTTP request/response payloads.

### 7. Multi-Device Fleet Testing
- Use `list_connected_devices` to see all running Flutter instances across iOS, Android, and Web.
- Use `switch_device(id: "...")` to toggle target device on the fly.

### 8. Crash Flight Recorder & Self-Healing Loop
1. When a crash occurs, call `get_flight_log` to inspect the 30-60s event timeline leading up to failure.
2. Call `generate_repro_test(writeToDisk: true)` to automatically synthesize an executable `test/repro_test.dart` test reproducing the bug.
3. Review the failing test & error details, then apply the code fix in the Dart source files.
4. Call `hot_reload` to push the fix to the running application.
5. Re-run `flutter test test/repro_test.dart` to verify that the bug is definitively fixed.
6. This flow is for **crash reproduction specifically** — not a general substitute for §3's assert_* tools when there's no crash to reproduce.
