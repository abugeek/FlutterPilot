## Unreleased

- `get_app_summary` says when the app is not running the code on disk:
  "• Code: 2 Dart files (lib/a.dart, lib/b.dart) edited since the app loaded
  its code… hot_reload loads it", or that `pubspec.lock`, `pubspec.yaml` or
  a native project file changed since the build and `launch_app(relaunch:
  true)` is needed. Edited files are compared with the source the VM has
  loaded, so a reload from the terminal or an earlier session counts.
  `launch_app` with an app running gives the relaunch reason too.
- A call the app does not answer says why (`WHY: …` after the timeout): the
  UI isolate busy in Dart code, with the stack where it was interrupted
  (`Home.recomputeTotals (package:app/main.dart:15)`); paused in the
  debugger and where; blocked outside Dart; or idle, with the call itself
  waiting. The isolate is resumed afterwards.
- `hot_reload` first checks that the app answers (5 s) instead of letting
  flutter_tools wait two minutes on a hung app and then blame a compile
  error.
- The server and the app's SDK carry a protocol number. When they differ,
  `get_app_summary` starts with "• Versions: the app's flutterpilot_sdk is
  older than this server…, so it lacks: …" (or newer: rebuild the server),
  and `get_app_summary(setup: true)` has both numbers.
- `navigate_to(waitFor: "Orders")` waits for a key or text on the new page
  (an error if it has not appeared in 5 s): one call for navigate, then
  wait.
- The third single step in a row (`tap_widget`, `enter_text`, `press_key`,
  `wait_for`, `assert_widget`, ...) ends with a one-line tip to send known
  steps in one `execute_action_chain`; said again every 12 steps, never
  after a failed step.
- A `hot_reload` that fails because the code does not compile returns the
  compiler's errors (`lib/a.dart:44:23: Error: …`) instead of an empty
  message: from `flutter run`'s output when `launch_app` started the app,
  else from `dart analyze` on the Dart files edited since the last good
  reload.
- An app whose `main()` has not reached `runApp` says so: `get_app_summary`
  starts with "Starting: main() has not called runApp yet…" instead of only
  "Route: Unknown" and no elements, and `capture_screenshot` waits up to 3 s
  for the first frame, then gives that reason instead of "No RenderView".
- Each tool call is noted in the project's
  `.dart_tool/flutterpilot_calls.jsonl` for `flutterpilot stats`: tool,
  time, response size and the kind of failure (quoted text and numbers
  masked). No arguments or results. `--no-call-log` or
  `FLUTTERPILOT_NO_CALL_LOG` turns it off; the file is cut at 2 MB.
- `launch_app` builds and starts the app (`flutter run`, or the command in
  the app's `flutterpilot/launch.json`), waits for its first frame and
  connects. The app keeps running after the MCP session ends, and the next
  one finds it. With an app already running it refuses unless
  `relaunch: true` and points at `hot_reload`; a failed build returns the
  end of the build output. 67 tools.
- `wait_for` and `navigate_to` end with the screen as it is now (route,
  tappable elements, new errors, still loading), as the action tools do; in
  field sessions a quarter of `wait_for` calls were followed by
  `get_app_summary`. `wait_for` answers in a sentence instead of JSON
  (`On route "/x".`, `Pumped 30 frames.`). Needs the SDK from this version
  (`ext.flutterpilot.screenNow`); an older one answers as before, without
  the screen.
- `exec_sql_query` failing on "no such column" lists the columns of the
  tables the query reads, and on "no such table" the database's tables,
  names like the missing one first. In field sessions 11 of 92 queries
  failed, nearly all on a guessed column.
- The tool list is 66 tools and about 9% smaller on the wire (a test holds
  it to a size budget). Breaking:
  - `get_capabilities` is `get_app_summary(setup: true)`.
  - `execute_action_chain` takes `steps` — tool calls, as in
    `run_on_devices`: `[{"tool": "tap_widget", "arguments": {"key": ...}}]` —
    and runs keys, scrolls, navigation and `wait_for` / `assert_widget`
    checks too, not only taps and text. Steps in the former
    `{"action", "target"}` shape are still read.
- Every tool has MCP annotations (read-only, destructive, idempotent), so
  clients can run reads without asking and ask before the tools that need
  `--allow-destructive`.
- The server sends `instructions` on connect: where to start and what not to
  repeat, for clients that load tool schemas on demand.
- Parameters have one name each, in camelCase: `clearFirst`, `sinceSeconds`,
  `statusFilter` (the former names still work), and schemas list `key` only
  (`target` still works). `get_shared_preferences(showSensitive)` is a
  boolean, `query_supabase_table(limit)` an integer; `table` and
  `query_firestore`'s `path` are required.

- `get_state(history: true)`: the last 50 Riverpod/Bloc changes, oldest
  first with times — old → new value, created, disposed — and the route
  changes between them; `clear: true` empties it.
- Tapping a disabled control names the form fields on screen that do not
  validate. `get_widget_properties` has `fieldError` / `invalid` for a form
  field; `get_interactive_elements` and `get_app_summary` mark fields that
  show an error.

- `inspect_widget(style: true)`: what a widget is drawn with — text size,
  weight, color, font and line height, paddings, fills, borders, corner
  radii, elevation — and the padding and fill around it.
- `set_app_settings(keyboardInset: 340)` lays the app out as with an open
  on-screen keyboard that tall (0 removes it), so a form that overflows above
  the keyboard is caught on desktop and web.
- `set_app_settings(windowSize:)` works on Windows: the app's viewport gets
  the size asked for. A window that stops at its minimum or the screen is
  reported as partly applied, not as done.
- `mock_http_response(error: "timeout" | "connection")` fails one URL with no
  response.

- `scenario` saves and loads local data too: the rows of the Drift and
  sqflite databases the app registered (one row per line in the file; each
  database replaced in one transaction) and Hive boxes of plain values.
  Tables over 1000 rows, tables with a credential-named column and virtual
  tables are left out and named. Loading them needs `--allow-destructive`.
- New `mock_platform_channel`: answers a plugin's method calls with a value
  or a PlatformException, delivers EventChannel events, and lists the calls
  the app made (and whether a plugin answered). A scenario carries the mocks
  across its hot restart.
- `scenario`, `generate_test` and `verify_feature` work on Windows: the
  app's folder was taken as `/D:/app`, which is not a path there.

- `get_app_summary` no longer prints a jank warning in a debug build, where
  most frames are over budget by nature and the line read as a defect on every
  call. It still does in a profile build, and `profile_frame_budget` answers
  in both.
- `set_app_settings(windowSize: "390x844")` resizes a macOS desktop app's
  window (its standard window, not a dialog in front) and reports the
  viewport the app then has; other platforms are refused with the reason.
- `navigate_to` waits (up to 1.5 s) for the page transition, so the next call
  sees the new page and not the one underneath.
- `hot_reload` on a sandboxed macOS app explains the permission the Flutter
  tool is missing instead of a bare failure.

## 0.1.0

- Initial release
- Core SDK with 20+ service extensions for AI-native Flutter introspection
- Widget tree capture with layout positions and source locations
- Screenshot capture as PNG
- Error interception and buffering
- Navigation stack tracking
- UI automation: tap, scroll, text entry
- Locale and theme override at runtime
- Performance metrics (FPS)
- Test recording and generation
- State inspection and injection via plugin system
