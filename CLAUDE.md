# FlutterPilot AI Assistant Guidelines

FlutterPilot is an AI-native runtime introspection, active control, and autonomous testing toolkit for Flutter applications, exposing 62 MCP tools (see TOOLS.generated.md; an app is shown only the ones that work for it) over the Model Context Protocol.

**Next work:** see `ROADMAP.md` (priorities, field-test method, known gotchas). Drive tools from a shell with `packages/flutterpilot_server/tool/fp_bridge.dart`.

## 🚀 CLI & Zero-Code Mode

- **1-Command Setup**: Run `flutterpilot init` in any Flutter project root to auto-detect Riverpod/Bloc/Dio/Drift and configure packages.
- **Connect an agent**: `flutterpilot mcp install` writes the MCP config (Claude Code `.mcp.json`, Cursor, VS Code) with a compiled server.
- **Dev Runner**: `flutterpilot dev` wraps `flutter run` and prints the VM service URI; it does not start the MCP server.
- **End-to-end check**: `dart run tool/e2e_test.dart [-d device]` (in `packages/flutterpilot_server`) creates a fresh app, runs `init --local`, launches it, and drives it through the MCP server. Run it after changing the server, SDK, or CLI.
- **Zero-Code Mode**: Without `flutterpilot_sdk` the app can be inspected but not driven: only the tools that work are listed (summary, widget tree, screenshots, errors, logs, hot reload/restart, theme and debug-paint toggles, memory/HTTP profiles). `get_app_summary` says so; `flutterpilot init` adds taps, text entry, navigation and assertions.

## Core Principles & Recommended Workflows

When interacting with a Flutter app using FlutterPilot:

### 1. Orientation & Diagnostics
- **First Step**: Call `get_app_summary` — route, the tappable elements on screen (labels + keys), errors, logs, and whether the app window is visible. `get_interactive_elements` gives the full tappable list.
- **Visual Inspection**: Use `capture_screenshot` to view the screen layout with coordinates.
- **Hierarchy Inspection**: Use `get_widget_tree` for a DevTools-style summary tree of the app's own widgets. PII and passwords are automatically redacted.
- **On-screen only**: finders, assertions and trees ignore routes covered by another page and hidden tabs, so `assert_widget(text: ...)` never passes on something the user can't see.
- **System alerts and backgrounding (iOS simulator, needs idb)**: permission alerts are not in the Flutter tree — `native_describe_screen` lists them with tap points and `native_tap` taps them (points). iOS suspends a backgrounded app; tools then say so at once, and `native_open_app` brings it back with its state.
- **Background window is fine**: when the OS reports the app hidden (window covered/minimized), FlutterPilot keeps it rendering while you drive it; the summary says so, and frame timings from that period are not profiled.

### 2. UI Interaction & Virtual Semantic Keys
- **No Manual Keys Needed**: You can interact with widgets using:
  - **Explicit Keys**: `tap_widget(key: "login_button")`
  - **Semantic Selectors**: `tap_widget(key: "ElevatedButton['Log In']")` or `enter_text(key: "TextField['Email']", text: "user@test.com")`
  - **Visible Text**: `tap_widget(key: "Log In")` — exact text wins; if several different widgets merely *contain* the text, the call is refused with the candidates instead of guessing
  - **Tooltips**: `tap_widget(key: "Tooltip['Settings']")`
- **AI Visual Overlay**: When AI interacts, a visual ripple and `🤖 AI Tap` badge pulse on screen for live human observation.
- **Keyboard**: `enter_text` focuses the field, so `press_key(key: "enter")` right after submits it. Use `press_key` for Enter/Tab/Escape/arrows/shortcuts; in a focused field, characters, Backspace/Delete, arrows and select-all edit it like typing, and the response shows the field's text and cursor. Set whole values with `enter_text` (`text: ""` clears). `press_key(key: "back")` is the system back button.
- **Scroll Before Tapping**: Use `scroll_into_view(key: "...")` if a widget is below the fold.
- **Trust the response — don't reflexively re-verify**: `tap_widget` (all gestures), `enter_text`, `press_key`, `toggle_checkbox`, `swipe_widget`, `drag_widget`, `fill_form`, and `execute_action_chain` all report their own postcondition in the same response: whether the route changed, a capped widget-tree diff of what appeared/disappeared, the elements tappable now, and any new errors — read once the screen has settled (transitions, drawers, tabs; a navigation that lands a moment later), and it says when a progress indicator shows that results are still loading. Read that response before reaching for `get_widget_tree` or `capture_screenshot` — most of the time it already answers "did this work." Only fall back to a screenshot when the response says nothing changed but you expected a purely visual effect (color, animation frame) with no structural diff.
- **Prefer one batched call over a tap→check→tap loop**: when the sequence of steps is already known, use `execute_action_chain`, `fill_form` (with `submitWith`), or `tap_widget(waitFor: ...)` instead of separate `tap_widget`/`enter_text`/`wait_for` calls. Each one executes natively inside the Flutter engine and returns a single combined result — this is the single biggest latency lever available: it turns N agent turns into 1.

### 3. Fast Verification — assert_* over flutter test
- For "did my change actually work" checks, use `assert_widget` against the *already-running* app: `assert_widget(text: ...)`, `assert_widget(key: ...)`, `assert_widget(key: ..., enabled: true|false)`, `assert_widget(type: ..., count: N)`. These run in milliseconds — no new process, no cold VM boot.
- For async results, use `wait_for(key | route | animations | state | frames)` or `tap_widget(key, waitFor: ...)` instead of sleeping.
- `audit_screen_health` is for layout/accessibility sweeps (combine with `set_app_settings(textScale: 2)` to catch overflows), not for confirming a single interaction.

### 4. Visual Regression Diff Engine
- Establish golden baselines with `compare_screenshot(name: "...", save: true)`.
- After code modifications or UI updates, run `compare_screenshot(name: "...")` to get the diff percentage and a highlighted diff image on regression.
- Prefer this (or the inline widget-tree diff from §2) over a bare `capture_screenshot` when you specifically need to know *what* changed, not just *that* something looks different.

### 5. Network Mocking & Conditioning (Dio plugin)
- **Mock Responses**: `mock_http_response(urlPattern: "...", statusCode: 500, body: '{"error":"server_down"}')` to test failure handling without a backend; `mock_http_response(clear: true)` afterwards.
- **Network Conditioning**: `simulate_network(condition: "slow_3g"|"fast_4g"|"offline"|"normal")`.
- **Verify**: `get_network_logs` (Dio) or `get_http_profile` (any dart:io client: status, timing, sizes).

### 6. Performance (DevTools equivalents)
- `profile_frame_budget` — p50/p90/p99 frame times, build vs raster split, jank count.
- `get_http_profile` — the DevTools Network tab.
- `get_memory_details` — heap usage; `classes: true` for the top classes.

### 7. Multi-Device Fleet Testing
- FlutterPilot connects to one app by itself (listed as `default`). Add the others with `register_device(id: "iphone", uri: "http://127.0.0.1:PORT/TOKEN=/")` — the URI `flutter run` prints; registering the already-connected app's URI just renames it.
- `list_connected_devices` shows each device's platform, app, SDK/zero-code, and which ones are no longer running.
- `switch_device(id: "...")` — every tool then targets that device (tools have no per-call device parameter). If the app restarted on a new port, `register_device` the same id with the new URI.

### 8. Crash Fix Loop
1. When a crash occurs, call `get_errors` (`report: true` for the full crash report) — it includes the exception, your source frame (file:line) and, for layout errors, the culprit widget's location.
2. Use `get_flight_log` for the event timeline leading up to it.
3. Fix the Dart source, then `hot_reload` (`restart: true` for main()/static initializer/provider-definition changes).
4. Reproduce the triggering steps and verify with `get_errors` and `assert_widget` (§3).
