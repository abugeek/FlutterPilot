# FlutterPilot — AI Agent Guide

You are connected to a live Flutter app via FlutterPilot. Every tool
targets the active device (see list_connected_devices / switch_device);
run_on_devices runs the same steps on every registered device and compares.

## First steps
1. `get_app_summary` — route, tappable elements (labels + keys), errors, logs, window visibility (`setup: true`: connection and plugins, when a tool is missing)
2. `capture_screenshot` — what the user sees
3. `get_widget_tree` — keys and structure (diff:true: only what changed)
4. `inspect_widget(key | x,y)` — the file:line in the app's code that draws a widget, and the app widgets above it

## Acting
- <!-- include: finding-widgets -->
- <!-- include: batching -->
- `tap_widget(key | x,y)` — gesture: double / long / secondary; waitFor: a widget to wait for after the tap
- `enter_text(key, text)` — type into a field ("" clears it); `press_key("enter")` submits
- `press_key(key)` — enter/tab/escape/arrows/shortcuts; "back" = system back (never quits from the root)
- `fill_form(fields, submitWith)` — several fields (+ checkboxes) in one call
- `execute_action_chain(steps)` — a known sequence in one call: taps, text, keys, scrolls, with `wait_for` / `assert_widget` between them (`[{tool, arguments}]`, as in `run_on_devices`)
- `scroll_into_view`, `swipe_widget`, `drag_widget`, `pinch_zoom`, `set_slider_value`, `toggle_checkbox` (also a checkbox inside a tappable row), `focus_widget`
- `navigate_to(route)` — jump to a route (action push/replace with go_router; deepLink:true)
Every action reports whether the route changed, a widget-tree diff and what is tappable now: read it before re-checking.

## Waiting and checking
- `wait_for(key | route | animations | state+expectedValue | frames)` — poll, never sleep
- `assert_widget(text | key [+enabled] | type+count)` — milliseconds, against the running app
- `compare_screenshot(name, save:true)` then `compare_screenshot(name)` — visual regression
- `audit_screen_health` — overflows and small tap targets (with `set_app_settings(textScale: 2)`)

## Reading state
- `get_errors` (report:true: full crash report), `get_debug_logs` (clear:true)
- `get_navigation_stack` — routes (go_router: params, routes:true, history:true)
- `get_state` / `set_state` — Riverpod and Bloc (plugins); `get_state(history: true)`: the recent changes in order (old → new, created, disposed, route changes) when a value is not what you expect
- `get_network_logs`, `mock_http_response`, `simulate_network` — Dio plugin
- `mock_platform_channel` — answer a plugin's native calls (location, permission, camera) or deliver its events (a scanned barcode); no argument lists the calls the app made
- `get_http_profile` — any dart:io client (clear:true for a baseline)
- storage: `exec_sql_query`, `get_shared_preferences`, `get_hive_contents`, `get_secure_storage`

## Changing how the app renders
- `set_app_settings` — theme, locale, textScale, keyboardInset (lay out as with an open keyboard), orientation, windowSize, debugPaint, repaintRainbow, slowAnimations
- `inspect_widget(key, style: true)` — text size/weight/color, paddings, fills, borders, radii: check a design spec in numbers, not from a screenshot

## Performance
- `profile_frame_budget` — p50/p90/p99 build/raster, jank
- `profile_action(tool, arguments)` — CPU profile of one action: the app functions it ran (self/total ms, file:line), and for janky frames build/layout/paint/raster and the app widgets that rebuilt
- `get_memory_details` (classes:true: top classes by heap) — compare before/after a screen for leaks

## Fixing
1. `get_errors` → your source frame (file:line)
2. edit the Dart source → `hot_reload` (restart:true for main()/static initializers/provider definitions)
3. repeat the steps; `assert_widget` / `get_errors` to confirm

## Keep the app running
- Building the app again takes minutes; `hot_reload` under a second.
- `hot_reload(restart: true)` recompiles every changed Dart file and runs main() again: use it after a git checkout/merge too, and to get out of a stuck screen or a bad app state.
- Run the app again only for pubspec.yaml (dependencies, assets), native code, --dart-define values, another device or build mode, or a dead process. Don't kill it when a task is done.
