## Unreleased

- **Breaking:** `swipe_widget`, `drag_widget`, `pinch_zoom`, `focus_widget` and
  `set_slider_value` are now one `gesture_widget(key, gesture: swipe | drag |
  pinch | focus | slide)`. The old names still work as steps inside
  `execute_action_chain`, `run_on_devices`, `profile_action` and a leak
  `cycle`; called directly they are unknown tools.
- `--tools core|all` on the server: `core` lists a short set (29 names) for a
  client that counts tools across every server it runs; `all` is the default
  and lists every tool that works for the app. `flutterpilot doctor` says
  which profile a config uses.
- `assert_widget`, `wait_for`, `verify_feature(finish: true)` and
  `run_on_devices` answer with `structuredContent` beside their text — a
  machine-readable verdict (`passed`, `met`/`timedOut`, per-criterion
  verdicts, per-device step counts) so a client need not parse prose.
- The arguments of a step another tool runs (`steps[]`, a `cycle`,
  `profile_action`, `run_on_devices`) are brought to the schema's types before
  the step runs (`"5"` becomes 5, a JSON-string array becomes the array); a
  value that cannot be read is refused with an example instead of a cast error
  that reads as "the app is busy, retry".
- Every capped list says how much was cut and how to see the rest — "Showing
  100 of 342 matching log entries (newest kept). Narrow with level, query,
  sinceSeconds or logger, or raise limit (max 500)." — from one helper
  (`src/truncation.dart`); a list that was not cut gets no line.
- `get_debug_logs` includes what the app printed before FlutterPilot connected
  (the SDK buffered it from app start), merged with the server's own capture
  and deduplicated, so it no longer disagrees with `get_app_summary`.
- `get_app_summary`'s "Uncaught Errors" and `get_errors` mark entries from
  before the last hot reload or restart ("N uncaught exceptions from before
  the last reload (the reload may have fixed them)") instead of presenting
  them as current.
- Windows: `launch_app` starts `flutter` (`flutter.bat`) through `cmd.exe`, or
  a `.bat`/`.cmd` launch command, and a relaunch stops the whole process tree
  (`taskkill /T`) so no build or app is left behind; file paths the server
  prints use `/`.
- `launch_app(relaunch: true)` with no `device` keeps the device the running
  app is on (`windows`, `macos`, `linux` name their own device) and says so in
  the response, instead of stopping the app and then failing with "More than
  one device connected" (field test #346). When the device cannot be told — a
  fresh launch with several devices, or a browser or phone id the platform
  does not give — the call refuses *before* stopping anything and names the
  devices to pass.
- The call log writes a `listed` line when the set of listed tools changes, so
  `flutterpilot stats` can tell a tool that was offered from one that was not.
- Faster, measured on the example app against the field-session numbers in
  `flutterpilot stats`:
  - `navigate_to` skips its second wait for the animation (the app settles
    before it answers; only go_router push/replace still need it: it cost up
    to 1.5 s on a screen with a spinner) and reads the stack and the screen
    together: 105-190 ms -> 55-80 ms.
  - `get_app_summary` and every call that mentions the phone no longer wait
    for adb/devicectl: the phone's state is served from the last read (5 s on
    Android, 20 s on an iPhone, up to 5 min stale while a new read runs
    behind it; `devicectl` took 1-3 s a call), and the adb device is found
    once per connection instead of with two adb calls each time.
  - The "edited but not reloaded" check remembers each file's verdict until it
    changes or the app reloads: it asked the VM for every script of the app
    and each edited file's text on every summary.
  - `hot_reload` reads what it needs before the reload (folder, SDK, ping) in
    parallel.
- `capture_screenshot`, `compare_screenshot` and `audit_screen_health` are
  refused with the reason (`Not done: the screen is off (asleep)` / `the
  device is locked`) on a phone that is off or locked. Found on a real
  Android phone: drawing the screen there crashes the engine's raster thread
  (SIGSEGV, "call to OpenGL ES API with no current context") and the app is
  lost; the smoke run did this to the example app. Android is read afresh
  before each such call (0.2 s).
- Android: reading the phone's state (awake, locked, battery, who has the
  focus) is one adb call that filters on the phone and reads the slow
  settings once a minute: 190 ms instead of 550 ms (measured on a phone). A
  tap that changed nothing now says in that time whether the app or a system
  dialog is in front (`In front is com.google.android.permissioncontroller`)
  instead of leaving a 2.5 s `native_describe_screen` to find out, which also
  names the package in front and uses `uiautomator dump --compressed` (half
  the output). The dump itself stays about 2.5 s: the phone's uiautomator
  waits for the screen to be idle.
- The `adb forward` the server makes to reach an app by itself (after
  `flutter run` died) is removed when it makes a new one and when the server
  stops; `flutterpilot doctor` lists stale forwards left by killed
  `flutter run`s on a plugged-in phone, with the `adb forward --remove`
  commands. Parsing is unit-tested; the phone was unplugged when I came to
  run it live.
- On an app running on a real iPhone, `native_tap`, `native_text`,
  `native_button`, `native_describe_screen` and `native_screenshot` are no
  longer listed: idb and simctl drove whichever simulator happened to be
  booted (found on the iPhone: the dialog described and the coordinates were
  the simulator's). `native_open_app` stays. The permission hint and the
  "App inactive" line (an open permission dialog does make a real iPhone's
  app inactive) then apply; checked on an iPhone 15 Pro Max with geolocator:
  the hint names `geolocator_apple / requestPermission`, and mocking that
  call gets the app past the dialog.
- On a device where nothing here can tap a system dialog (a real iPhone:
  idb drives simulators only), a tap that changed nothing now names the
  permission calls the app made (`flutter.baseflow.com/permissions/methods /
  requestPermissions`) and says to dismiss the dialog by hand or answer that
  call with `mock_platform_channel` so it never opens; without
  `FlutterPilot.initialize()` first in `main()` it says that is needed. The
  app summary's "App inactive" line says the same instead of pointing at a
  `native_describe_screen` that is not listed there.
- `launch_app(waitSeconds: 60)` returns after that long if the build is still
  going, naming the stage (`compiling the iOS app`, `installing on the
  device`, `waiting for the device`…), so a 5-minute iPhone build is not one
  blind call; the build goes on and the next call keeps waiting.
- `launch_app` on a real iPhone signs with your team by itself when the
  project names none and the Mac has exactly one valid Apple Development
  certificate (passed as `FLUTTER_XCODE_DEVELOPMENT_TEAM`; the project is not
  touched, and the result says which team). Before: "No profiles for …" until
  the project was opened in Xcode.
- A physical iPhone: `native_open_app` brings the app back to the foreground
  (`devicectl device process launch`; the bundle id comes from matching the
  VM's process to the installed app), and when the app dies in native code
  its crash report is fetched from the phone (`devicectl … systemCrashLogs`)
  and shown like a simulator's. Tested on an iPhone 15 Pro Max (SIGABRT).
  The other `native_*` tools need idb, which drives simulators only.
- A failed iOS build with `No Accounts` says Xcode has no Apple ID signed in.
- A failed `launch_app` on a phone says why when it can: iOS signing (with
  the `FLUTTER_XCODE_DEVELOPMENT_TEAM` fix for `flutterpilot/launch.json`),
  a locked iPhone, Developer Mode off, an unauthorized or restricted Android
  phone, no storage; and adds the phone's state (`DEVICE: the iPhone is
  locked`). Before: "No Xcode build settings have been found".
- A phone whose cable or adb server dropped no longer needs a manual
  reconnect: the `adb forward` to the app is made again, and when
  `flutter run` itself is gone (its service proxy dies with it) the server
  reads the app's VM service address from logcat, forwards it and connects
  directly. The summary says so once (`• Connection: …`); hot reload and
  `launch_app` still need `flutter run`.
- A physical phone that is asleep, locked or (iPhone) not connected is said
  so: `• Device: …` in `get_app_summary` (and the phone's state in
  `setup: true`), and a `DEVICE: …` line on a call that got no answer or lost
  the connection, which looked like a hung app. Android is read over adb
  (`dumpsys`), an iPhone over `xcrun devicectl`. Not checked for simulators.
- The `native_*` tools work on Android (emulator or phone) through `adb`:
  `native_describe_screen` lists system dialogs and notifications with tap
  points (uiautomator), `native_tap`, `native_text`, `native_button` (HOME,
  BACK, POWER, WAKEUP), `native_screenshot` and `native_open_app`. `adb` is
  found on PATH, in `ANDROID_HOME`/`ANDROID_SDK_ROOT` or the SDK's default
  folder (it was only looked up on PATH, so crash lookup silently failed);
  the device is the one `flutter run` forwarded the VM service from, else the
  only one attached, else `serial`.
- `exec_sql_query` without `sql` lists the tables with their columns, and
  the first successful query on a table ends with that table's columns
  (once per table and connection): the next query has names to use instead
  of guesses.
- A call whose own action runs into a breakpoint ends as soon as the pause
  is seen ("This call did not finish: the app is paused at a breakpoint
  at …"), not after 30 s.
- `audit_screen_health(routes: …)` goes back to the screen it started on.
- `flutterpilot_server --help`.
- An app blocked outside Dart (a native call, `sleep()`) now gets its
  `WHY:`: the diagnosis itself waited on calls such an isolate never
  answers and timed out without a word.
- An app stopped at a breakpoint is remembered as it happens: calls after
  the first answer at once with "Nothing was done: the app is paused at a
  breakpoint at …" instead of each waiting 30 s.
- `audit_screen_health(routes: ["/a", "/b"])` goes to each route and
  checks it in one call: per route "Clean." or the findings, new errors on
  arriving, and a progress indicator still showing. In field sessions a
  sweep was navigate_to, get_errors and audit_screen_health for every
  screen (75 such rounds in one session). Up to 40 routes a call.
- `get_state(name: "cart")` returns only the states whose name contains
  it, or the names there are; agents passed a name the tool did not take.
- `launch_app` keeps the output of the launch before it as
  `.dart_tool/flutterpilot_run.prev.log`: a relaunch erased what the app it
  had just stopped had printed.
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
- Action responses are shorter. "Tappable now" says "same as after the
  previous call" or only what was added and removed when the screen barely
  changed (the full list returns at least every fourth time and after two
  minutes); the bulk-rebuild note and the nothing-changed hints lost their
  repeated instructions.
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
