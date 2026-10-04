# FlutterPilot AI Assistant Guidelines

FlutterPilot is an AI-native runtime introspection, active control, and autonomous testing toolkit for Flutter applications, exposing 67 MCP tools (see TOOLS.generated.md; an app is shown only the ones that work for it) over the Model Context Protocol.

**Next work:** see `ROADMAP.md` (priorities, field-test method, known gotchas). Drive tools from a shell with `packages/flutterpilot_server/tool/fp_bridge.dart`.

## 🚀 CLI & Zero-Code Mode

- **1-Command Setup**: Run `flutterpilot init` in any Flutter project root to auto-detect Riverpod/Bloc/Dio/Drift and configure packages.
- **Check setup**: `flutterpilot doctor` checks SDK/plugin wiring, macOS entitlements, MCP config and (if running) what the app registered, with exact fixes.
- **Connect an agent**: `flutterpilot mcp install` writes the MCP config (Claude Code `.mcp.json`, Cursor, VS Code, Codex, Gemini CLI, Antigravity, Zed, opencode, Junie, Kiro, Roo Code; README "MCP Setup") with a compiled server, plus the official Dart MCP server (`dart mcp-server --disable flutter,dart_tooling_daemon`: its analyzer, `lsp` and pub; its hot reload/errors/inspector/driver duplicate ours).
- **Finding the app**: a plain `flutter run`, an IDE launch or the Dart MCP server's `launch_app` is found through the Dart Tooling Daemon; `flutterpilot dev` also writes `.dart_tool/flutterpilot_vm_uri`.
- **Dev Runner**: `flutterpilot dev` wraps `flutter run` and prints the VM service URI; it does not start the MCP server.
- **End-to-end check**: `dart run tool/e2e_test.dart [-d device]` (in `packages/flutterpilot_server`) creates a fresh app, runs `init --local`, launches it, and drives it through the MCP server. Run it after changing the server, SDK, or CLI.
- **Zero-Code Mode**: Without `flutterpilot_sdk` the app can be inspected but not driven: only the tools that work are listed (summary, widget tree, screenshots, errors, logs, hot reload/restart, theme and debug-paint toggles, memory/HTTP profiles). `get_app_summary` says so; `flutterpilot init` adds taps, text entry, navigation and assertions.

## Core Principles & Recommended Workflows

When interacting with a Flutter app using FlutterPilot:

### 1. Orientation & Diagnostics
- **First Step**: Call `get_app_summary` — route, the tappable elements on screen (labels + keys), errors, logs, and whether the app window is visible. `get_interactive_elements` gives the full tappable list.
- **Visual Inspection**: Use `capture_screenshot` to view the screen layout with coordinates.
- **Hierarchy Inspection**: Use `get_widget_tree` for a DevTools-style summary tree of the app's own widgets. Password fields show as `•`; credentials in logs, URLs, network bodies, errors and credential-named state (`password=…`, `?api_key=…`, Bearer tokens, JWTs) are masked in every tool (docs/security-review.md).
- **Where is this in the code?**: `inspect_widget(key: ...)` or `inspect_widget(x:, y:)` (a point from a screenshot) returns the file:line in the app's code that creates the widget — for a framework widget, the app widget that builds it — plus the app widgets above it. Use it before editing UI code (debug builds). `layout: true` adds each box's constraints and size up the ancestors and explains overflows (by how much, which children fill the Row) and 0-sized widgets (which ancestor gives max 0).
- **What is it drawn with?**: `inspect_widget(key: ..., style: true)` returns the numbers a screenshot can't: each text's size, weight, color (`#RRGGBB`), font, line height and letter spacing; paddings as `ltrb` (a Container's border is taken out and listed as `plusBorder`); fills, gradients, borders, corner radii, elevation and opacity; and the padding and fill around the widget. Use it to check a change against a design spec (16 or 12 of padding, weight 600 or 700) instead of judging a screenshot. What an app's own `CustomPainter` draws is not listed (the response says how many are inside), nor are a TextField's underline/outline.
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
- `audit_screen_health` is for layout/accessibility sweeps (combine with `set_app_settings(textScale: 2)` to catch overflows, `theme: "dark"` for contrast, `keyboardInset: 340` to lay the page out as with an open on-screen keyboard — a form that overflows or hides its submit button above the keyboard shows up on desktop and web too; `0` removes it — or `windowSize: "390x844"` to test a macOS or Windows desktop app at a phone width), not for confirming a single interaction. It reports overflows, small tap targets, controls a screen reader can't name (with the widget and file:line that adds the tap), text below WCAG contrast (measured from the rendered pixels), and the screen reader order with any jumps back up the screen. Disabled controls are exempt from contrast, and moving up into the next column of a multi-column layout is not a jump.

- **Regression test from a flow**: `generate_test(start: true)` restarts the app and records; do the flow with tap_widget/enter_text/press_key/assert_widget/wait_for/mock_http_response as usual; `generate_test(name: "checkout")` writes `integration_test/checkout_test.dart` (the app's `main()`, `find.byKey`/`find.text`/`find.byTooltip` finders, mocks as `DioPilotInterceptor.mock`, obscured text via `--dart-define`), runs it on the same device and reports pass, or the step it failed at. Minutes, not milliseconds: use it to keep a flow working, not to check one change.

- **Start from a known state**: `scenario(save: "empty_cart", description: ...)` writes `flutterpilot/scenarios/empty_cart.json` in the app (route, SharedPreferences minus sensitive keys, the rows of the registered Drift/sqflite databases — one row per line — and plain Hive boxes, active HTTP and platform-channel mocks, bool/number/String Riverpod/Bloc values); `scenario(load: "empty_cart")` replaces the preferences and those rows (each database in one transaction; tables not in the file keep theirs), hot-restarts with the mocks answering from the first call, goes to the route and sets the state. `scenario()` lists them. Files are meant to be checked in and edited. Loading stored data needs `--allow-destructive`; state is set behind the widgets (a TextField keeps its own text). Not saved, and said so: tables over 1000 rows, tables with a credential-named column, virtual tables, Hive boxes holding adapter objects, secure storage, files.

- **Verify a feature against acceptance criteria**: `verify_feature(feature: "Login", criteria: ["A wrong password shows an error", ...], scenario: "logged_out")` (scenario optional), then for each `verify_feature(criterion: N)`, drive the app and check the outcome with `assert_widget`/`wait_for`/`compare_screenshot`; `verify_feature(finish: true)` returns the verdicts and writes `flutterpilot/reports/<feature>-<time>/report.md` (steps, HTTP requests, errors, a screenshot per criterion). A criterion passes only if a check passed, none failed and the app threw no error (layout overflows are listed as warnings); driven but unchecked is NOT VERIFIED. Picking a criterion again starts its evidence over.

### 4. Visual Regression Diff Engine
- Establish golden baselines with `compare_screenshot(name: "...", save: true)`.
- After code modifications or UI updates, run `compare_screenshot(name: "...")` to get the diff percentage and a highlighted diff image on regression.
- Prefer this (or the inline widget-tree diff from §2) over a bare `capture_screenshot` when you specifically need to know *what* changed, not just *that* something looks different.

### 5. Network Mocking & Conditioning (Dio plugin)
- **Mock Responses**: `mock_http_response(urlPattern: "...", statusCode: 500, body: '{"error":"server_down"}')` to test failure handling without a backend; `mock_http_response(clear: true)` afterwards. `error: "timeout"` or `error: "connection"` (instead of `statusCode`) fails that URL with no response, after `delayMs`, while the rest of the app stays online. Responses out of order (the stale-search race): give two patterns different `delayMs` — the URL *contains* the pattern, so make them distinct (`q=ap&` and `q=apple&`).
- **Network Conditioning**: `simulate_network(condition: "slow_3g"|"fast_4g"|"offline"|"normal")`.
- **Plugins without the hardware** (no plugin needed): `mock_platform_channel()` lists the calls the app made on platform channels (channel, method, arguments, and whether a plugin answered or the platform has none) — that is where the names come from. `mock_platform_channel(channel: "flutter.baseflow.com/geolocator", method: "checkPermission", result: 0)` answers the call in the native side's place; `error: "CODE"` throws a PlatformException; `channel + event: "4006381333931"` delivers an event to the app's EventChannel listeners (a scanned barcode, a location update); `clear: true` removes mocks. Pigeon APIs: the whole channel name, no method. Answering calls needs `FlutterPilot.initialize()` as the first line of `main()`, before `WidgetsFlutterBinding.ensureInitialized()` (the tool says so otherwise; events work either way). Mocks are lost on hot restart unless a scenario carries them.
- **Verify**: `get_network_logs` (Dio) or `get_http_profile` (any dart:io client: status, timing, sizes; `url` filters; `id: N` for one request's headers, bodies and connection timeline, credentials masked).

### 6. Performance (DevTools equivalents)
- `profile_frame_budget` — p50/p90/p99 frame times, build vs raster split, jank count.
- `profile_action(tool: "tap_widget", arguments: {...})` — CPU profile of one action: the app's functions by self/total time with file:line, and the hottest framework functions with the app code that called them. For frames over budget it adds build/layout/paint/raster times and which app widgets rebuilt (self time per widget type). FlutterPilot's own work is left out. Add `durationMs` to keep sampling after the action for results that load later.
- `get_http_profile` — the DevTools Network tab.
- **Trust profile builds for timings**: debug frames run several times slower (on hn_reader a feed switch took 219 ms of Dart and showed 2 janky frames in debug, 87 ms and none in profile). Launch with `flutter run --profile` (not the iOS simulator) to confirm jank; FlutterPilot connects the same way, the summary says "Build: profile", and the performance tools say which build their numbers come from. Profile builds have no hot reload (`hot_reload`, `generate_test`, `scenario` are not listed) and no file:line in `inspect_widget`; everything else works.
- `get_memory_details` — heap usage; `classes: true` for the top classes. Leak check: `cycle: [{tool: "tap_widget", arguments: {key: "Open"}}, {tool: "press_key", arguments: {key: "back"}}], times: 5` returns the classes that keep instances from every round, where they're defined, and what keeps one alive (retaining path), and says when it's framework bookkeeping or FlutterPilot itself rather than the app.

### 7. Multi-Device Fleet Testing
- FlutterPilot connects to one app by itself (listed as `default`). Add the others with `register_device(id: "iphone", uri: "http://127.0.0.1:PORT/TOKEN=/")` — the URI `flutter run` prints; registering the already-connected app's URI just renames it.
- `list_connected_devices` shows each device's platform, app, SDK/zero-code, and which ones are no longer running.
- `switch_device(id: "...")` — every tool then targets that device (tools have no per-call device parameter). If the app restarted on a new port, `register_device` the same id with the new URI.
- **Same flow on every device**: `run_on_devices(steps: [{tool: "tap_widget", arguments: {key: "Log in"}}, {tool: "assert_widget", arguments: {text: "Welcome"}}])` runs the steps on all registered devices at once (each on its own connection; `devices: [...]` picks some) and reports which steps passed where and how the final screens differ: route, tappable elements, new errors with the last one's message. Listed once two devices are registered.

### 8. Crash Fix Loop
1. When a crash occurs, call `get_errors` (`report: true` for the full crash report) — it includes the exception, your source frame (file:line) and, for layout errors, the culprit widget's location.
   If the app died in native code (an Objective-C/Swift/Kotlin exception or a signal; macOS, iOS simulator, Android), any tool's "not running" error says so, with the exception message, then (the OS writes the report ~20 s later) the frames where it was thrown and the report path.
2. Fix the Dart source, then `hot_reload` (`restart: true` for main()/static initializer/provider-definition changes).
3. Reproduce the triggering steps and verify with `get_errors` and `assert_widget` (§3).
