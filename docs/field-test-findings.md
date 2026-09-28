# Field test findings (2026-09-26/27)

Raw log from driving the HN reader (`../hn_reader`) through FlutterPilot's MCP
tools on macOS. ✅ works · ⚠️ works with problems · ❌ broken · "→fixed" = fixed
in PR #1. Items still open are tracked in `ROADMAP.md`.

## Round 1 — core tools
| # | Feature | Result | Notes |
|---|---|---|---|
| 1 | init --local | ✅ | detected 6 plugins, printed wiring lines, pub get + analyze clean |
| 2 | auto-discovery | ❌→fixed | looked for files flutter never writes + fixed ports; now reads --vmservice-out-file (ws→http verify) |
| 3 | get_app_summary | ⚠️ | currentRoute "Unknown" with go_router; promised plugins/FPS missing |
| 4 | capture_screenshot | ✅ | 50ms, 0.5x |
| 5 | get_riverpod_state | ✅✅ | surfaced exact root cause (SocketException errno=1 → macOS sandbox) in 1 call |
| 6 | get_network_logs | ⚠️ | showed Riverpod retry storm; ERROR lines omit message |
| 7 | get_http_profile | ❌ | "No HTTP requests recorded" — never enables dart:io http profiling |
| 8 | get_debug_logs | ❌ | empty despite app printing |
| 9 | get_errors | — | caught async errors don't appear (defensible) |
| 10 | reconnect after app restart | ❌→fixed | retried dead URI forever; now rediscovers |
| 11 | hot_reload (real app) | ✅ | ~300ms, edits applied |
| 12 | hot_restart | ❌→fixed | intermittent 2-min hang after rediscovery: reconnect timer + stale onDone handlers caused connection churn. Fixed (single in-flight connect, cancel timer, identity guards). 12/12 after |
| 13 | set_theme | ✅ | zero wiring (uses ext.flutter.brightnessOverride) |
| 14 | set_text_scale_factor / set_locale | ❌→fixed | returned success but did nothing unless app wires notifier; now errors with snippet. Worked after wiring |
| 15 | audit_screen_health | ⚠️ | found real overflow at 1.6x; but each overflow x3 (ancestors), 40 tap-target warnings (InkWell+GestureDetector dupes, mobile rules on desktop) = noise |
| 16 | get_errors | ❌→fixed | overflow had no source location; now "Widget: Row …/story_tile.dart:23:17" |
| 17 | get_debug_logs | ⚠️→fixed | UTF-8 mojibake (Latin-1 decode); no history before connect |
| 18 | self-heal on errors | ⚠️ | 38px overflow logged as "🚨 CRITICAL APP CRASH", marks app UNSTABLE, fires 6 extension calls incl full widget tree per error |
| 19 | wait_for_widget | ⚠️ | key-only; tap_widget accepts text → inconsistent |
| 20 | get_widget_tree | ❌→fixed | default output was 3.4KB of framework internals truncated before ANY app widget (27KB at depth 200, still none). Now DevTools-style summary tree (app-created widgets + Text + user keys): 13.9KB incl. story keys |
| 21 | enter_text / tap_widget postcondition diff | ✅✅ | response says what changed (+39/-63, sample titles) — no follow-up call needed |
| 22 | route tracking w/ go_router | ❌→fixed | currentRoute Unknown, nav stack empty, gorouter location stale after push. Plugin now feeds NavigationTracker; location uses router.state |
| 23 | press_back w/ go_router | ❌→fixed | "context does not include a Navigator"; now uses handlePopRoute (same as OS back) |
| 24 | wait_for_state (riverpod) | ⚠️ | name must be "NotifierProvider<FeedNotifier, Feed>"; "FeedNotifier" fails with last value null, no hint |
| 25 | wait_for_condition | ⚠️ | param is `selector` while every other tool uses `key` |
| 26 | sqflite list/query | ✅ | bookmark tapped in UI verified in DB; write guard works. param `dbName` |
| 27 | exec_sql_query "auto-detect" | ❌ | fails without dbName even with exactly one DB |
| 28 | shared prefs read | ✅ | ; set blocked w/o --allow-destructive (ok) |
| 29 | mock_http_response | ✅✅ | found REAL app bug: Riverpod 3 infinite retry hides error UI → fixed app → verified error UI + Retry recovery in ~8 calls |
| 30 | simulate_network offline (Dio) | ✅ | works |
| 31 | simulate_offline (connectivity) | ❌ | only flips a flag the app must poll itself; returns success, no effect. Also bool param typed as string |
| 32 | swipe_widget (pull-to-refresh) | ⚠️ | no visible effect; hard to verify (network log capped at 50 → flooded by item requests) |
| 33 | wait_for_condition | ✅ | text-based, fast |
| 34 | profile_frame_budget | ✅✅ | p50/p90/p99, build vs raster, detects 120Hz — real DevTools equivalent |
| 35 | get_http_profile | ❌→fixed | never enabled dart:io profiling. Now works for ANY http client: status, timing, sizes. Revealed N+1 (31 req × ~440ms) |
| 36 | get_memory_details / get_allocation_profile | ✅ | DevTools memory class list equivalent |
| 37 | get_perf_metrics | ⚠️ | "FPS 1.6" on idle app — meaningless metric |
| 38 | get_gc_stats | ⚠️ | no GC stats, just heap |
| 39 | enable_widget_rebuild_tracking | ❌ | no tool returns rebuild counts |
| 40 | audit_memory_health | ⚠️ | image cache only |
| 41 | toggle_debug_paint | ✅ | visible in screenshot; useful for layout |
| 42 | get_render_tree / get_layer_tree | ❌ | 1.7MB root dump truncated to 8KB of boilerplate; unusable w/o scoping |
| 43 | execute_action_chain | ✅ | 3/3 steps 589ms; diff samples are framework noise (full tree, not summary) |
| 44 | tap_and_wait / wait_for_widget | ❌→fixed | key-only lookup despite docs; now same finder as tap_widget |
| 45 | simulate_deep_link | ❌→fixed | sent pushRoute TO the platform (wrong direction), success w/o effect; now handlePushRoute |
| 46 | jump_to_screen / navigate_to (go_router) | ❌→fixed | Navigator-context error; now handlePushRoute. (jump says "state injected" when none) |
| 47 | set_riverpod_state | ⚠️ | gated behind --allow-destructive (in-memory state!); value must be JSON-encoded, error unhelpful |
| 48 | save/restore_state_snapshot | ❌ | no plugin wires capture/restore delegates → saves route name only, restore does nothing, reports "successfully rewound" |
| 49 | param naming | ⚠️ | key / target / selector / rootKey / expect / dbName / enabled-as-string across tools |
| 50 | save_screenshot_baseline / compare_screenshot | ❌→fixed | crashed (RangeError) whenever a diff existed: assumed 4 B/px, screenshots are 16-bit; highlight invisible. Now 8.11% + magenta overlay |
| 51 | crash detection + get_latest_crash_report | ✅ | pointed to main.dart:60:50 exactly; but 41KB (~10k tokens): raw+compact stacks, full tree |
| 52 | get_flight_log | ✅ | timeline + crash snapshot |
| 53 | generate_repro_test | ❌ | uses nonexistent `const MyApp()`, raw coordinate taps, omits the deep link that crashed — can't reproduce |
| 54 | press_back at root | ❌→fixed (regression from #23) | OS-back at root called SystemNavigator.pop → app exited. Now refuses unless allowExit |
| 55 | get_semantics_tree | ❌→fixed | always "not yet available": semantics never enabled + wrong PipelineOwner. Now 12KB of real a11y labels |
| 56 | screen mutation counter / contextVersion / ifMutation | ❌ | notifyMutation() is never called → always 0; optimistic-concurrency + tree ETag are dead |
| 57 | get_widget_properties | ⚠️ | TextField reported isEnabled:false (it's enabled) |
| 58 | fill_form_batch | ✅ | state updated (diff says no change — diff unreliable) |
| 59 | long_press_widget | ✅ | |
| 60 | get_app_context / get_build_config / read_dart_file / list_dart_files | ✅ | fine; file tools duplicate what any coding agent already has |
| 61 | start_recording / stop_and_generate_test | ⚠️ | raw action log (semantic + duplicate coordinate taps); agent must write the test itself |
| 62 | export_test_suite | ⚠️ | asked flutter_test, got patrol |
| 63 | record_fixtures / replay_fixtures | ❌ | writes relative to server cwd (ignores project root); saves requests w/o bodies → replay registers 0 mocks |
| 64 | run_chaos_fuzzing | ⚠️ | 50 random events, 0 crashes; low signal |
| 65 | generate_pr_report | ⚠️ | health table + FlutterPilot ad; little value |
| 66 | export_session_gif | ⚠️ | 1 frame, written to server cwd |
| 67 | replay_flight_log | ❌ | deadline exceeded (replays stale coordinates) |
| 68 | list_connected_devices | ⚠️ | empty while connected to the auto-discovered app |
| 69 | set_device_rotation | ⚠️ | "success" on desktop (no-op) |
| 70 | async ops (async:true + get_operation) | ✅ | works; rarely needed (calls are ms) |

## Round 2 — review of the other agent's commits (2f4cb47, 3b6e8fd, 56dbe54)
| # | Feature | Result | Notes |
|---|---|---|---|
| 71 | hidden app window | ❌→fixed | macOS reports covered/minimized windows as `hidden`; Flutter stops frames; every read/tap was stale. SDK now pumps forced frames while an agent is active |
| 72 | get_app_snapshot | ❌→merged | 37 KB, 217 "interactive" framework GlobalKeys + duplicate JSON dump. Merged into get_app_summary (~1 KB) |
| 73 | get_interactive_elements | ❌→fixed | counted any keyed widget + every Text. Now: gesture primitives, named by nearest app widget, hittable only |
| 74 | post-action state | ⚠️→fixed | dropped the widget diff; listed framework keys; error count never reset. Now route + diff + tappable + new errors |
| 75 | audit_ui_design | ❌ dropped | stock Material app scored 0/100 "F"; 48dp mobile rule on desktop; each button counted 3x |
| 76 | get_app_issues / IssueDetector | ❌ dropped | missed real HTTP 500s; overflow without location (get_errors has it); noise |
| 77 | press_key | ⚠️→fixed | success when nothing focused; target shown as "Focus"; no route change reported. Enter/Escape work; Backspace can't edit text on macOS (OS text input) |
| 78 | secondary_tap / pinch_zoom | ✅ | verified in real app + e2e |
| 79 | finder caches | ❌→removed | key index built once, never invalidated; cached text; resolved to widgets on covered routes |
| 80 | assert_text_visible on covered route | ❌→fixed | passed for a page under another page. Traversal now onstage-only (flutter_test semantics) |
| 81 | fuzzy/substring matching | ❌→fixed | "x" tapped a random story; similar labels tapped the wrong button. Ambiguity now an error with candidates |
| 82 | tapping covered widgets | ❌→fixed | tapped whatever was on top and reported success |
| 83 | findElement latency | ❌→fixed | 221 ms (hit-tested every element). Now ~10 ms |
| 84 | press_back | ❌→fixed | reached SystemNavigator.pop and quit the app. Now router popRoute; exit only with allowExit |
| 85 | FlutterPilot.run / FlutterPilotBinding | ❌ dropped | zone mismatch; binding only cleared the removed cache |
| 86 | frame profiler while hidden | ❌→fixed | forced background frames reported as 100% jank |
| 87 | aliases (tap, go_back, get_logs, ...) | dropped | duplicates increase tool-selection cost |
| 88 | tool/ scripts, benchmark_report.json | dropped | hardcoded dead VM URIs; results from one emulator |

## Round 3 — review of the second agent's §1 work (uncommitted in main checkout)
| # | Item | Result | Notes |
|---|---|---|---|
| 89 | getPostActionState made async | ❌→fixed | 4 callers didn't await → enter_text, press_key, secondary_tap, pinch_zoom returned errors *after* performing the action (agents would retry = double actions) |
| 90 | route-settle wait | ❌→rewritten | dynamic `.animation` probe on every widget every 16 ms (exceptions), waited on app spinners, no-op for go_router. Now checks only on-screen ModalRoute transitions |
| 91 | key/target consistency | ⚠️→finished | aliasing ran after schema validation; 16 tools still required `key`. Now every widget tool accepts both |
| 92 | self-heal severity | ❌→fixed | server honoured `severity`, SDK never sent it → overflows still "CRITICAL" |
| 93 | crash report size | ⚠️→fixed | 6.9 KB with all raw stacks → ~4.5 KB with only the crashing stack |
| 94 | flutterpilot_bloc constraint | ❌→fixed | `flutter_bloc ^8` blocked install on current 9.x |
| 95 | Escape via keyData path | ✅ | closes a popup menu on macOS |
| 96 | riverpod plain values/short names, SQL auto-detect, Dio bodies | ✅ | verified in HN reader |

## Round 4 — second field-test app (`../notes_app`, §2.1)

Notes app: Bloc + Drift + Hive CE + flutter_secure_storage + local Supabase
(auth, `notes` table with RLS, realtime). Wired with `flutterpilot init --local`
exactly as a new user would, driven only through fp_bridge.

| # | Item | Result | Notes |
|---|---|---|---|
| 97 | `init` plugin detection | ❌→fixed | `hive_ce` (maintained fork; `hive` last released 2022) not detected |
| 98 | `init` text-scale wiring | ❌→fixed | printed "locale and text scale" but only wired locale: `builder:` of a nested `BlocBuilder` counted as MaterialApp's own |
| 99 | `init` binding | ⚠️→fixed | second `WidgetsFlutterBinding.ensureInitialized()` added |
| 100 | target by field label | ❌→fixed | summary lists `[TextField] "Email"`, `enter_text(target:"Email")` failed; `tap_widget` claimed it was "covered by an overlay" (label Text is a sibling of the input) |
| 101 | `enter_text` password echo | ❌→fixed | obscured text echoed in the response and stored in recordings/flight log |
| 102 | `enter_text` without target | ❌→fixed | used the text itself as the target instead of the focused field |
| 103 | `execute_action_chain` | ❌→rewritten | `enter_text` (the tool's own name) was "unsupportedAction"; no route-settle wait → "covered"; ran on after failures. Now shares tap/type code with the single tools and stops at the first failure |
| 104 | AI overlay badge | ❌→fixed | `🤖 …` Text showed in tree diffs; now invisible to the inspector and cleared before screenshots |
| 105 | `tap_and_wait` | ⚠️→fixed | reported the diff from right after the tap, not the screen it waited for |
| 106 | unnamed routes | ⚠️→fixed | "Unknown" → `EditorScreen`, `(menu)`, `(dialog)` |
| 107 | element labels | ⚠️→fixed | icon glyph names appended to tooltips: "Delete delete", "New note add" |
| 108 | SQL tools | ❌→merged | `query_drift` required `dbName`, hid SQLite's error ("check SQL syntax"), printed Dart maps; `query_sqflite` duplicate. One read-only `exec_sql_query` now |
| 109 | Hive plugin | ❌→rewritten | imported `package:hive` → saw nothing in hive_ce apps; `box.add` int keys broke JSON encoding. Now takes the box itself |
| 110 | plugin `reset()` | ❌→fixed | re-registering an extension threw; SDK now swaps handlers |
| 111 | `get_bloc_state` | ⚠️→fixed | every bloc listed twice; unbounded state strings |
| 112 | `set_bloc_state` | ⚠️→fixed | needed `--allow-destructive` for an in-memory change; class-typed states now refused with what to do instead |
| 113 | secure_storage on macOS | ✅/⚠️ | debug builds need `usesDataProtectionKeychain: false` (-34018, surfaced by `get_errors` with the source line); legacy keychain can't `readAll()` → key listing fails with guidance, `read_secure_storage_key` works |
| 114 | Supabase / Firebase network tools | ❌→fixed | `supabase_sign_out`, `supabase_refresh_session`, `log_analytics_event`, `record_crashlytics_error` ran without `--allow-destructive` |
| 115 | `get_supabase_auth` / `query_supabase_table` / `get_supabase_realtime` | ✅ | realtime verified: row inserted from "another device" appeared in the app |
| 116 | trailing `[operationId: op-N]` on every response | ⚠️→removed | token noise; async results still carry it |
| 117 | summary jank / lifecycle | ⚠️→fixed | "40% jank" from 5 startup frames; `inactive` (visible, unfocused) reported as "not visible" |
| 118 | fp_bridge | ⚠️→fixed | empty POST crashed it |

## Round 5 — e2e on iOS simulator, Android emulator, web (§2.2)

| # | Item | Result | Notes |
|---|---|---|---|
| 119 | core tools on iOS / Android / Chrome | ✅ | same e2e as macOS: tap, text, keys, secondary tap, pinch, chains, password masking, hot reload + restart (web via DWDS) |
| 120 | `set_device_rotation` on mobile | ✅ | rotates for real (viewport checked both ways); e2e assumed desktop |
| 121 | first calls on web | ❌→fixed | extensions register after `app.started`; first calls said "not registered" / "Zero-Code mode". Server now waits once per connection (≤5 s) for the SDK's extensions |
| 122 | `native_*` on other platforms | ⚠️→gated | listed only for iOS apps with `idb`/`xcrun` present (tools/list_changed). `native_tap/text/button/describe_screen` still untested (no idb here) |

## Round 6 — zero-code mode (§2.3)

A plain `flutter create` app (no flutterpilot_sdk) on macOS, driven through
the MCP server; then Chrome via `e2e_test.dart --zero-code`.

| # | Item | Result | Notes |
|---|---|---|---|
| 123 | tools/list | ❌→fixed | all 124 tools listed; ~95 answered "not registered … run flutterpilot init" (the plugin message, not the cause). Now only the 29 that work are listed (one `tools/list_changed`); they come back when the SDK's extensions register |
| 124 | `get_app_summary` | ⚠️→fixed | raw JSON (VM version, heap) and a hint promising "deterministic key tapping" that doesn't exist. Now says what works and what doesn't, errors, and the text/keys on screen |
| 125 | `get_widget_tree` | ❌→fixed | the fallback called `getRootWidgetTree` without `groupName`: failed, and printed a "Null check operator" exception into the user's `flutter run` console on every call. Now the SDK's tree shape from the inspector, with `file:line` for app widgets |
| 126 | covered routes / hidden tabs in tree | ❌→fixed | the inspector's summary tree includes the page under the current one. Now built from the full tree, skipping what `_Theater` (`skipCount`) and IndexedStack (render object `index`) don't paint |
| 127 | `capture_screenshot` | ❌→fixed | refused ("requires the SDK"). Now `ext.flutter.inspector.screenshot`, cropped to the window: its bounds include overflow and a covered route parked at -⅓ width by the Cupertino transition (first version showed the page offset by 266 px) |
| 128 | `get_errors` | ❌→fixed | refused. Now from `Flutter.Error` events (structured errors, on by default in debug except web), summary + culprit `file:line`; reset on hot restart. Errors from before the connection aren't known; hot reload re-reports layout errors |
| 129 | `get_debug_logs` | ✅ | stdout captured; empty result told the user to call `FlutterPilot.initialize()`. Both modes only have output since the server connected — now said so |
| 130 | hot reload / restart, set_theme, debug paint, slow animations, repaint rainbow, memory, allocation profile, HTTP profile, VM info, baselines/compare | ✅ | no SDK needed |
| 131 | `get_self_heal_status` / `get_latest_crash_report` | ⚠️→hidden | always "STABLE" / "none" without the SDK's error events |
| 132 | e2e harness | ⚠️→fixed | a failed `flutter run` build waited 20 min for a VM URI; now fails when flutter exits |

Not possible without the SDK (or expression evaluation): taps, text entry,
navigation, route info, assertions, text scale / locale, plugin state.

## Round 7 — multi-device fleet (§2.4)

One server, three apps: `../hn_reader` on macOS and on the iPhone 17
simulator, `../plain_app` (no SDK) on Chrome. Registered, switched, quit and
relaunched through the MCP tools.

| # | Item | Result | Notes |
|---|---|---|---|
| 133 | `deviceId` parameter (39 tools) | ❌→removed | most tools rebuilt their arguments and dropped it: `get_app_summary(deviceId: "mac")` answered from the iPhone. Removed from every schema; a stray `deviceId` is refused with "call switch_device first" |
| 134 | `switch_device` to a dead app | ❌→fixed | marked the dead device active, and every tool then silently answered from the previous app. Now checks the target first and stays on the current device |
| 135 | `register_device` | ❌→fixed | registered anything (port 1, typos); the `http://…/` URI flutter run prints failed later with "Unsupported URL scheme". Now normalizes http/ws/DevTools URLs, checks the app answers, and reports platform · app · SDK |
| 136 | `connect_app` with its own example URI | ❌→fixed | `http://…` failed the same way; response said "Connected successfully … %3Credacted%3E" |
| 137 | auto-connected app + `register_device` | ❌→fixed | registering the first named device dropped "default" and made the new one active while tools still talked to the old app. Registering a known URI now renames that entry |
| 138 | `list_connected_devices` | ⚠️→fixed | JSON of ids + redacted URIs; didn't say which apps still run. Now one line per device: platform · app · flutterpilot_sdk/zero-code, or "not running (…register_device again)" |
| 139 | active app quits | ⚠️→fixed | "SocketException … If the app was busy or reloading, retry". Now "Device "iphone" is not running … register_device(id, <new URI>)"; rediscovery no longer jumps to another registered device's app |
| 140 | switch to a zero-code app | ⚠️→fixed | first call took 4.2 s (waited 5 s for SDK extensions that will never come). The wait is skipped once the isolate has run for 10 s |
| 141 | tool list per device | ✅ | switching between SDK and zero-code apps shows 124 / 29 tools (tools/list_changed) |
| 142 | per-device state | ✅ | routes, screenshot baselines (`save`/`compare` keyed by device), hot reload go to the active device |

## Round 8 — native iOS tools (§2.2)

`../native_app` (location permission via geolocator, a text field, a
lifecycle label; SDK via `init --local`) on the iPhone 17 simulator, with
idb installed. Driven through the MCP tools.

| # | Item | Result | Notes |
|---|---|---|---|
| 143 | native tools hidden with idb installed | ❌→fixed | `pip3 install --user fb-idb` puts idb in `~/Library/Python/<v>/bin`, off PATH; the server only checked `which idb`. Now looks there too |
| 144 | `native_tap` coordinates | ❌→fixed | description said "native screenshot pixel space", but idb taps in points: a tap at pixel coords reported success and hit nothing. Now points everywhere; `native_screenshot` is scaled to points (240 KB → 45 KB) |
| 145 | `native_describe_screen` | ⚠️→fixed | raw idb JSON (~400 B per element). Now one line per element with its tap point: the location alert is 5 lines |
| 146 | backgrounded app (HOME) | ❌→fixed | iOS suspends it: every call hung 50 s, then "The app may be unresponsive". SDK now posts lifecycle events; the server answers at once "in the background… native_open_app" |
| 147 | no way back to the app | ❌→added | `native_open_app` (simulator): bundle id and simulator from the VM's pid; state kept |
| 148 | large images | ❌→fixed | mcp_dart's base64 check overflows the stack above ~3 MB: a full-size home-screen screenshot became "Internal server error". Every tool's images are now scaled to fit |
| 149 | permission alert after a tap | ⚠️→hint | not in the Flutter tree, and iOS doesn't always make the app `inactive`. A tap that changed nothing now mentions native_describe_screen; the summary flags an inactive app on phones |
| 150 | `press_key` enter | ⚠️→fixed | submitted the field but the response said nothing changed (no tree diff was computed). Now diffs like a tap |
| 151 | summary "Focused" | ⚠️→fixed | named the `Focus` wrapper; now the app's widget (`TextField`) |
| 152 | `native_text` into a Flutter field | ✅ | real iOS text input reaches Flutter's TextField (" Jr" appended) |
| 153 | location allow / deny | ✅ | both paths end in the app's own result text |

## Round 9 — Firebase and plain hive (§2.1)

`../firebase_app` (email sign-up/sign-in, per-user notes in Firestore,
owner-only security rules) on the iPhone 17 simulator against the local Auth
+ Firestore emulators; `../hive_app` (plain `hive` 2.2.3 + `hive_flutter`) on
macOS. Both set up with `flutterpilot init --local`.

| # | Item | Result | Notes |
|---|---|---|---|
| 154 | old Firebase plugin | ❌→replaced | 7 tools for Crashlytics/Analytics/Performance/FCM: none has an emulator; `get_analytics_log` listed only events the agent itself sent; two tools wrote fake data into the real project; it forced all four SDKs on any app with `firebase_core` |
| 155 | `get_firebase_auth` | ✅ new | uid (for paths), providers, token expiry, custom claims, sign-in/out events; email redacted unless showSensitive. 2 ms |
| 156 | `query_firestore` | ✅ new | collection/document, where, orderBy, limit ("limit reached"), cache vs server; Timestamps as ISO. Rules errors name the rule line and whether anyone is signed in. 3–24 ms, < 300 chars |
| 157 | `init` for Firebase | ⚠️→fixed | triggered on `firebase_core` (an Analytics-only app would get Auth + Firestore); now on `firebase_auth`/`cloud_firestore`, with the right register line |
| 158 | toggles in action diffs | ❌→fixed | tapping a SwitchListTile/Checkbox reported "no change": the diff tracked type/key/text only. Now `= true/false` (switch, checkbox, slider) |
| 159 | honest "no change" | ✅ | a hive_app bug (switch reading a box the builder didn't listen to) showed as "no change" while hive held the new value — the diff told the truth |
| 160 | plain `hive` | ✅ | boxes readable, writes from the UI visible (plugin is duck-typed) |
| 161 | native crash on launch | ⚠️ gap | Firebase iOS SDK aborts on a malformed API key (NSException). The agent only sees "not running"; the reason is in the simulator log. Candidate tool: native crash/log reader |
| 162 | generated files in git | ⚠️→fixed | six plugins tracked `.flutter-plugins-dependencies` (with another machine's paths); untracked and ignored |

## Round 10 — only relevant tools (§4.1)

hn_reader (Riverpod, go_router, Dio, sqflite, SharedPreferences,
connectivity) and hive_app on macOS, one server, switching devices.

| # | Item | Result | Notes |
|---|---|---|---|
| 163 | tools/list | ⚠️→fixed | every macOS app got all 119 tools (68 KB of definitions per request; 125 on iOS) whatever plugins it used. Now plugin tools only once the app registers the plugin: hn_reader 104 tools / 57 KB, hive_app 86 / 45 KB |
| 164 | set/wait state tools | ⚠️→gated | `set_riverpod_state`, `set_bloc_state`, `batch_set_state`, `wait_for_state` go through the SDK's generic extensions but only work with the Riverpod/Bloc plugin: listed with it |
| 165 | hot restart | ✅ | list stays stable (extensions re-register within the 300 ms debounce); no list_changed churn |
| 166 | per device | ✅ | switching hn_reader ↔ hive_app changes the list |
| 167 | lazy plugins | ⚠️→doc | a plugin that registers late (Dio created on first request) lists its tools late; `init` now prints `DioPilotInterceptor.register()` for main() |

## Round 11 — fewer tools (§4.2)

125 tools merged into 62 (families → one tool with a parameter). e2e on
macOS (SDK and zero-code) and hn_reader on macOS, driven through every
merged path.

| # | Item | Result | Notes |
|---|---|---|---|
| 168 | tools/list | ✅ | e2e fixture (Dio) 88 → 42 tools; zero-code 29 → 16; all plugins + iOS 125 → 62 (34 KB of definitions, was 58) |
| 169 | `tap_widget` gestures | ✅ | double/long/secondary report the same postcondition as a tap (before: double/long only a bare diff); double/long at x/y refused with the reason |
| 170 | `tap_widget(waitFor)` | ✅ | one call for tap + wait; a missing widget is an error that still reports the tap |
| 171 | `wait_for` | ✅ | route, animations, frames, state (type inferred from the plugins); no condition → error, not a silent pass |
| 172 | `navigate_to` | ✅ | go_router `go` by default, `push` builds a stack (`/search -> /story/1`); response shows the stack |
| 173 | `press_key("back")` | ✅ | pops and reports the new route |
| 174 | `set_app_settings` | ✅ | one line per setting; locale not wired in hn_reader → ✗ with the fix, text scale ✓, both in one call; orientation on desktop "skipped", not ✓ |
| 175 | `get_state` | ⚠️→fixed | a FutureProvider<List> printed every element; values are clipped to 200 chars |
| 176 | `exec_sql_query` | ❌→fixed | with several databases, "Multiple databases registered (a, b)" was taken for "plugin absent" → "No database registered". Only "No … databases registered" counts as absent now |
| 177 | recording, stream logs | ❌→deleted | `start_recording` described recording the user's manual taps but recorded only FlutterPilot-driven actions; nothing ever fed `get_stream_logs` |
| 178 | enum states | ⚠️ known | `set_state` on a Notifier holding an enum (ThemeMode) is refused honestly ("String is not a subtype of ThemeMode") |

## Round 12 — errors vs crashes (§3.10)

The e2e fixture got a Crash button (throws in onPressed) and a Squeeze
toggle (a Row overflow); driven through the MCP tools on macOS.

| # | Item | Result | Notes |
|---|---|---|---|
| 179 | overflow vs exception | ✅ | already split by the SDK's severity: the overflow is listed, the app is not flagged; the throw is flagged until hot reload |
| 180 | crash report | ❌→fixed | 3.5 KB, 2 KB of it a widget-tree dump fetched with a full tree walk for every report, "No data available" sections for absent plugins, "🚨 Critical App Crash Report" and a "DIRECTIVE FOR AI". Now 0.4 KB: exception, app frames, route, state, last requests |
| 181 | stacks | ❌→fixed | an error from an agent's tap listed FlutterPilot's own frames (interaction_manager, widget_extensions) and `dart:developer` with async markers. Only the app's frames are shown now |
| 182 | culprit widget | ⚠️→fixed | "Row Row:file:///private/var/…/lib/main.dart:81:44" → "Row (lib/main.dart:81:44)" |
| 183 | notifications | ⚠️→fixed | level critical, "Self-Heal sequence initiated", once per distinct exception with only a 2 s debounce of repeats. Now level error, once per exception until hot reload |

## Latency observed (debug mode, macOS, HN reader)
- zero-code (plain app): summary 70–230 ms, tree 30–90 ms (full inspector tree: ~60–90 ms / 0.9 MB on HN reader), screenshot 45–130 ms (up to ~350 ms at 1.0x when it has to be cropped)
- trivial read (nav stack): 15–30 ms; get_widget_tree: 40–120 ms; get_app_summary: ~100–180 ms
- tap_widget with post-action state: 300–450 ms (first calls after hot restart: 1–2 s, JIT)
- hot_reload ~300 ms; hot_restart ~350–500 ms
