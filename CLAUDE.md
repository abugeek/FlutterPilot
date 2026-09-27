# FlutterPilot AI Assistant Guidelines

FlutterPilot is an AI-native runtime introspection, active control, and autonomous testing toolkit for Flutter applications, exposing 110+ MCP tools over the Model Context Protocol.

## 🚀 CLI & Zero-Code Mode

- **1-Command Setup**: Run `flutterpilot init` in any Flutter project root to auto-detect Riverpod/Bloc/Dio/Drift and configure packages.
- **Dev Runner**: `flutterpilot dev` wraps `flutter run` and prints the VM service URI; it does not start the MCP server.
- **End-to-end check**: `dart run tool/e2e_test.dart [-d device]` (in `packages/flutterpilot_server`) creates a fresh app, runs `init --local`, launches it, and drives it through the MCP server. Run it after changing the server, SDK, or CLI.
- **Zero-Code Mode**: Works out of the box even without `flutterpilot_sdk` by gracefully falling back to native Flutter VM inspector, debug paint, animation controls, GC profiler, and hot reload.

## Core Principles & Recommended Workflows

When interacting with a Flutter app using FlutterPilot:

### 1. Orientation & Diagnostics
- **First Step**: Call `get_app_summary` — route, the tappable elements on screen (labels + keys), errors, logs, and whether the app window is visible. `get_interactive_elements` gives the full tappable list.
- **Visual Inspection**: Use `capture_screenshot` to view the screen layout with coordinates.
- **Hierarchy Inspection**: Use `get_widget_tree` for a DevTools-style summary tree of the app's own widgets. PII and passwords are automatically redacted.
- **On-screen only**: finders, assertions and trees ignore routes covered by another page and hidden tabs, so `assert_text_visible` never passes on something the user can't see.
- **Background window is fine**: when the OS reports the app hidden (window covered/minimized), FlutterPilot keeps it rendering while you drive it; the summary says so, and frame timings from that period are not profiled.

### 2. UI Interaction & Virtual Semantic Keys
- **No Manual Keys Needed**: You can interact with widgets using:
  - **Explicit Keys**: `tap_widget(key: "login_button")`
  - **Semantic Selectors**: `tap_widget(key: "ElevatedButton['Log In']")` or `enter_text(key: "TextField['Email']", text: "user@test.com")`
  - **Visible Text**: `tap_widget(key: "Log In")` — exact text wins; if several different widgets merely *contain* the text, the call is refused with the candidates instead of guessing
  - **Tooltips**: `tap_widget(key: "Tooltip['Settings']")`
- **AI Visual Overlay**: When AI interacts, a visual ripple and `🤖 AI Tap` badge pulse on screen for live human observation.
- **Keyboard**: `enter_text` focuses the field, so `press_key(key: "enter")` right after submits it. Use `press_key` for Enter/Tab/Escape/arrows/shortcuts; change text with `enter_text`/`clear_text_field`.
- **Scroll Before Tapping**: Use `scroll_into_view(key: "...")` if a widget is below the fold.
- **Trust the response — don't reflexively re-verify**: `tap_widget`, `enter_text`, `press_key`, `secondary_tap`, `toggle_checkbox`, `swipe_widget`, `drag_widget`, `fill_form`, and `execute_action_chain` all report their own postcondition in the same response: whether the route changed, a capped widget-tree diff of what appeared/disappeared, the elements tappable now, and any new errors. Read that response before reaching for `get_widget_tree` or `capture_screenshot` — most of the time it already answers "did this work." Only fall back to a screenshot when the response says nothing changed but you expected a purely visual effect (color, animation frame) with no structural diff.
- **Prefer one batched call over a tap→check→tap loop**: when the sequence of steps is already known, use `execute_action_chain`, `fill_form_batch`, `tap_and_wait`, or `enter_text_and_submit` instead of separate `tap_widget`/`enter_text` calls. Each one executes natively inside the Flutter engine and returns a single combined result — this is the single biggest latency lever available: it turns N agent turns into 1.

### 3. Fast Verification — assert_* over flutter test
- For "did my change actually work" checks, use the in-process assertion tools against the *already-running* app: `assert_widget_visible(key)`, `assert_text_visible(text)`, `assert_widget_count(type, count)`, `assert_widget_enabled(key)` / `assert_widget_disabled(key)`. These run in milliseconds — no new process, no cold VM boot.
- For async results, use `wait_for_condition(selector: "...")` or `tap_and_wait(target, expect)` instead of sleeping.
- `audit_screen_health` is for layout/accessibility sweeps (combine with `set_text_scale_factor` to catch overflows), not for confirming a single interaction.

### 4. Visual Regression Diff Engine
- Establish golden baselines with `save_screenshot_baseline(name: "...")`.
- After code modifications or UI updates, run `compare_screenshot(name: "...")` to get the diff percentage and a highlighted diff image on regression.
- Prefer this (or the inline widget-tree diff from §2) over a bare `capture_screenshot` when you specifically need to know *what* changed, not just *that* something looks different.

### 5. Network Mocking & Conditioning (Dio plugin)
- **Mock Responses**: `mock_http_response(urlPattern: "...", statusCode: 500, body: '{"error":"server_down"}')` to test failure handling without a backend; `clear_http_mocks` afterwards.
- **Network Conditioning**: `simulate_network(condition: "slow_3g"|"fast_4g"|"offline"|"normal")`.
- **Verify**: `get_network_logs` (Dio) or `get_http_profile` (any dart:io client: status, timing, sizes).

### 6. Performance (DevTools equivalents)
- `profile_frame_budget` — p50/p90/p99 frame times, build vs raster split, jank count.
- `get_http_profile` — the DevTools Network tab.
- `get_memory_details` / `get_allocation_profile` — heap usage and top classes.

### 7. Multi-Device Fleet Testing
- Use `list_connected_devices` to see all running Flutter instances across iOS, Android, and Web.
- Use `switch_device(id: "...")` to toggle target device on the fly.

### 8. Crash Fix Loop
1. When a crash occurs, call `get_errors` or `get_latest_crash_report` — they include the exception, your source frame (file:line) and, for layout errors, the culprit widget's location.
2. Use `get_flight_log` for the event timeline leading up to it.
3. Fix the Dart source, then `hot_reload` (or `hot_restart` for main()/static initializer/provider-definition changes).
4. Reproduce the triggering steps and verify with `get_self_heal_status` and the assert_* tools (§3).
