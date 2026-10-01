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

## Round 13 — keyboard (§3.11)

The e2e fixture counts key-downs per key with a HardwareKeyboard handler;
driven through the MCP tools on macOS.

| # | Item | Result | Notes |
|---|---|---|---|
| 184 | double dispatch | ✅ | each press_key is one key-down in the app (⌘A: one for Meta, one for A); already fixed in the simulator |
| 185 | editing keys in a field | ❌→fixed | backspace and "x" reported "pressed on TextField" and left "Pilot" as it was. Now "Field: "Pilo" (cursor at 4)"; arrows, select-all and typing over a selection work, and onChanged fires |
| 186 | enter_text selection | ❌→fixed | on desktop the focus change after enter_text selected the whole text, so the next backspace would have cleared the field. The cursor is at the end now (also fill_form) |
| 187 | other platforms | ✅ unit | Android/Linux/Windows edit through Flutter's shortcuts, macOS/iOS through the new fallback: same result, never twice (widget tests on all six platforms; e2e on CI's iOS/Android/web runs) |

## Round 14 — locale and text scale without wiring (§3.12)

e2e fixture: a plain `MaterialApp` (supportedLocales en_US, en_GB) showing
the scale and locale its screen gets. hn_reader (go_router,
`MaterialApp.router`) driven on macOS, with its old wiring and without it.

| # | Item | Result | Notes |
|---|---|---|---|
| 188 | unwired app | ❌→fixed | set_app_settings refused both ("not wired in this app"); `init` only wired a MaterialApp in main.dart without its own builder:/locale:. Now both work with no app code: fixture shows "Scale 1.5" and "Locale en_GB"; hn_reader with its wiring removed renders at 1.5x |
| 189 | unsupported locale | ✅ | "locale de had no effect: the app does not support de (supportedLocales: en_US); it shows en_US" — the device locale was set, the app ignores it, as on a phone |
| 190 | "system" and "zh-CN" | ❌→fixed | the SDK split tags on "_" only and parsed "system" as a language code. Tags with "-"/"_", scripts (zh-Hans-CN) and regions (es-419) parse; "system" restores the device locale |
| 191 | keeps applying | ✅ | a hot reload on hn_reader kept 2x (screenshot); window resize and MaterialApp rebuilt with a new supportedLocales list are covered by widget tests, each failing when its fix is removed |
| 192 | real bug found | ✅ | at 2x hn_reader's story row overflows by 65–212 px: get_errors names `Row (lib/ui/story_tile.dart:30:19)` |
| 193 | old wiring | ✅ | hn_reader's ValueListenableBuilder + withClampedTextScaling still passes the scale through; the notifiers are deprecated, nothing sets them |

## Round 15 — settle timing (§3.13)

A scratch go_router app with each kind of motion (push, go, delayed go,
dialog, sheet, popup menu, drawer, tabs, long-press, Enter-submit, a looping
marquee), then hn_reader, driven on macOS. Before → after:

| # | Item | Result | Notes |
|---|---|---|---|
| 194 | push / go / dialog / sheet / popup / Enter / chain | ✅ | already waited for route transitions |
| 195 | long-press, double-tap, fill_form(submitWith) | ❌→fixed | answered mid-transition (+7/-0: new page in, old not out) with no tappable list; all mutating extensions now share one after-action step (also swipe, drag, toggle, x/y and secondary taps, pinch) |
| 196 | drawer, tab switch | ❌→fixed | not routes: answered at ~130 ms with the drawer/tab mid-slide ("Drawer item", "In Two" missing). Now waits until on-screen text holds still between frames (~400 ms). Tappable elements alone weren't enough: they drop out of the list while sliding |
| 197 | navigation 250 ms after the tap | ❌→fixed | showed the old screen, "Route unchanged". An action that changed nothing is watched 0.5 s more; it now shows the new page. A tap that really does nothing says "Nothing changed in the 0.5 s after it either" |
| 198 | looping text (marquee) | ✅ | ignored after moving 600 ms, remembered for later actions: no-op tap 1.3 s the first time, then ~0.75 s; navigation unaffected (the marquee is covered) |
| 199 | hot restart | ❌→fixed | tools failed "not registered" for a moment after hot_reload(restart) returned; it now waits for the new isolate's first frame and FlutterPilot's extensions (~600 ms) |
| 200 | request in flight | ✅ new | hn_reader's chips and story page answer while a spinner shows; the response now says "A progress indicator is showing: results may still be loading" |
| 201 | seen in passing | → tasks | `Tooltip['Menu']` picked "Open navigation menu" (fixed: selector exact values beat substrings, an icon's name ranks below real labels, IconButtonTheme is not a button; on every platform but Android plain "Menu" hit the drawer's menu icon); go_router app without the plugin reports route "Unknown" (fixed: without an observer or router plugin the route is read from the pages in the widget tree — `/ → /details`, `/ → (dialog)`, hidden shell branches skipped — and a route the app can't name is reported as unknown, never "unchanged"; init's step 2 says what it wired and points go_router apps to flutterpilot_gorouter); drawer scrim listed as one element with all screen text; not-found hints list `_ScaffoldSlot.body` |

## Round 16 — Android and web CI (after merging §3.10–§3.13)

`main` was red on Android and web; the stack's branches had been red before
merging. Reproduced on a local emulator at CI's 320x640 dp with the soft
keyboard forced on, and in Chrome:

| # | Item | Result | Notes |
|---|---|---|---|
| 202 | button under the on-screen keyboard | ❌→fixed | after the text checks the keyboard stays up; the Scaffold shrinks, the bottom row is clipped, and tap_widget refused "a dialog, menu or overlay covers it". A tap now closes the keyboard first (focus kept, like the back gesture), taps, and says "Closed the on-screen keyboard first"; if it won't close the error names the keyboard |
| 203 | text-selection handle listed as "MaterialApp" | ❌→fixed | Android shows handles after select-all; they live in the root Overlay, whose nearest app widget is MaterialApp, so the whole screen was listed with every text on it. A handler is never reported under an owner across an Overlay |
| 204 | web crash report | ❌→fixed | web stacks (`package:app/main.dart 12:5  f`, `dart-sdk/…`) weren't recognised: 1.4 KB of framework frames. Filtered like VM stacks, app frames rewritten as `f (package:app/main.dart:12:5)` |
| 205 | URI file on web | ❌→fixed | discovery probed the URI with HTTP; DWDS doesn't answer 200, so the web app was never found. It now checks that something listens on the port |
| 206 | fixture "Scale 1.0" on web | test fix | `1.0.toString()` is "1" in JS; the fixture formats with one decimal |

## inspect_widget (ROADMAP §5.1), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 207 | inspect_widget by key | ✅ | `story_…` → `ListTile lib/ui/story_tile.dart:24:14`, then GestureDetector, `StoryTile lib/ui/feed_screen.dart:96:44`, ListView … FeedScreen; every line checked against the source. 16 ms, ~0.8 KB |
| 208 | inspect_widget at x,y | ✅ | a story title and a filter chip hit the RichText that Text builds inside the framework; the source is the app's `Text` (story_tile.dart:29, feed_screen.dart:31) with a note saying so. 2–3 ms |
| 209 | inspect_widget errors | ✅ | a point outside the window, no arguments and an unknown key each say why (unknown key lists the visible targets). Ancestors capped at 8 (12 was ~0.9 KB and ran past the screen widget) |

## profile_action (ROADMAP §5.2), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 210 | FlutterPilot's own work in the profile | ❌→fixed | the SDK is a path dependency, so the VM reports its frames as plain file paths, not `package:`; the post-action tree walk (~20–36 ms) showed as the hottest code. Paths are now mapped to packages via the app's package_config.json and those samples are left out (and reported as such) |
| 211 | planted hotspot | ✅ | a slow `_slowChecksum` in `StoryTile.build`: top app function `_slowChecksum lib/ui/story_tile.dart:91` (5.8 self / 8.8 total ms), `StoryTile.build` 8.8 total, `ListIterator.moveNext ← _slowChecksum` among the hottest. Reverted |
| 212 | work that lands after the action | ❌→fixed | tap "Top" returns when the spinner shows; the stories (and their builds) arrive later, outside the window. `durationMs` now keeps sampling after the action |
| 213 | errors and idle | ✅ | a non-action tool is refused with the list of action tools; no tool samples idle time ("no app function was sampled"). A 180 ms tap costs ~1 s to profile (getCpuSamples + line lookups) |

## Jank explanation in profile_action (ROADMAP §5.3), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 214 | no frames found | ❌→fixed | a real engine nests `Animator::BeginFrame` inside `VsyncProcessCallback` (the synthetic unit test had it at top level): "none drawn" while the spinner animated. Frames are now found anywhere in the span tree, and an `E` whose `B` predates the window no longer closes an unrelated span |
| 215 | AI tap overlay in the frames | ❌→fixed | the ripple (AnimatedBuilder/Opacity/Text) rebuilt on every frame, ~1.3 ms each, listed as app rebuilds. `ext.flutterpilot.profiling` switches the overlay off for the window and restores it |
| 216 | real jank, feed switch | ✅ | the frame the new list appears in: 28.7 ms UI (build 22.8 · layout 3.0), raster 0.5; IconButton ×10 7.0 ms, ListTile ×10 5.7 ms |
| 217 | planted slow build | ✅ | `_slowChecksum` in `StoryTile.build`: one 81.4 ms frame (build 70.7), `StoryTile ×10 39.2 ms` first; the CPU section named `_slowChecksum lib/ui/story_tile.dart:91`. Reverted |

## Layout explorer in inspect_widget (ROADMAP §5.4), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 218 | the known subtitle overflow (textScale 1.6) | ✅ | `inspect_widget(x, y, layout: true)` on the subtitle: "Row lib/ui/story_tile.dart:30:19 overflows by 60.6 px: its children need 732.6 px, it has 672", widest children the two Texts at :32 and :37 (not flexible); the Text line shows `w 0–∞` (a Row lets it be as wide as it likes). Matches get_errors' RenderFlex message |
| 219 | children named RichText | ❌→fixed | the Row's children are the RichTexts Text builds; boxes are now named after the nearest app widget that owns them: `Text lib/ui/story_tile.dart:32:13 (RichText)` |
| 220 | the suggested fix | ✅ | wrapping the Text at :32 in Flexible + ellipsis (temporarily, hot reload): the Text gets `w 0–368 Flexible(flex 1)` and no issue is reported. Reverted (the overflow stays as the known defect) |

## Leak check in get_memory_details (ROADMAP §5.5), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 221 | planted leak (listener never removed) | ✅ | cycle open story → back, 5 rounds: `_ReadTrackerState lib/ui/story_screen.dart:129 +5 (1 → … → 6)`, kept alive: `_ReadTrackerState ← closure _onRead ← _List[6] ← ChangeNotifier._listeners ← static readEvents`. Reverted. ~3.4 s |
| 222 | noise | ❌→fixed | the debug JIT's Code/ICData/Instructions and `_List` grew every round; framework classes are now listed only when they grow by the same amount each round and belong to a library |
| 223 | path of an arbitrary instance | ❌→fixed | `getInstances` returned a live DateTime, not a leaked one, so the path pointed at Riverpod state. A confirming round now diffs instance identities; the path is taken from an instance that round created and GC kept; classes with none are dropped. It also showed a DateTime held by the SDK's `_agentActiveUntil`: instances FlutterPilot holds are reported as FlutterPilot's, not the app's |
| 224 | clean app | ✅ | no app class leaks; `_RecognizerEventData` (+5/tap) and `GestureArenaEntry` (+1/tap) are labelled "held only by framework objects": gesture recognizers keep an entry per pointer id (Flutter never removes `_pointerToEventData` entries; `_entries`, flutter/flutter#117356) |

## Network detail in get_http_profile (ROADMAP §5.6), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 225 | wrong duration | ❌→fixed | the list showed the top-level `endTime`, when the request finished *sending* (310 ms); the response ended at 529 ms. Durations now run to `response.endTime` |
| 226 | request in full | ✅ | `get_http_profile(id: 1)` on the Show feed: `#1 GET …/showstories.json → 200 OK in 545 ms`, timeline "Connection established +317 ms … Waiting (TTFB) +544 ms" (connecting was most of it), both header sets and the JSON body. `url` filters; a filter matching nothing now says how many were recorded instead of "none recorded yet" |
| 227 | e2e, unmocked request | ✅ | the fixture's Send through Dio without a mock appears as `#1 [404] GET https://example.com/ping` and in full with `id: 1`. The fixture doesn't catch Dio's 404, so the check runs just before the hot reload that clears the exception flag. Redaction of credentials (headers, JSON, form fields) is covered by unit tests only: no field-test app sends credentials |

## Accessibility audit in audit_screen_health (ROADMAP §5.7), HN reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 228 | unlabeled stop per story | ✅ found | `GestureDetector(onSecondaryTapUp)` in `lib/ui/story_tile.dart:22` adds a tap action with no label over each ListTile: `Tappable ×6 at (0, 162), (0, 227), … 800×64 has no label … Code: GestureDetector lib/ui/story_tile.dart:22:12. It covers "1 World Labs…" (same box)`. Adding `excludeFromSemantics: true` (tried, then reverted) clears it (excludeFromSemantics leaves the gesture itself working) |
| 229 | first versions of that line | ❌→fixed | positions were physical pixels (semantics transforms carry the device pixel ratio); the source was the title Text (hit test), then StoryTile (nearest app widget); the same node was listed 6 times. Now logical points, the render object that owns the node and adds the tap, grouped per source |
| 230 | contrast missed after a theme switch | ❌→fixed | with a grey 400 subtitle (tried, then reverted), `audit_screen_health` 90 ms after `set_app_settings(theme: "light")` reported nothing: `AnimatedTheme` fades for 200 ms and the pixels were still dark. The audit now waits up to 1 s for animations, then reports `"74 pts · …" contrast 1.79:1 (#bdbdbd on #fff8f6) … Code: Text lib/ui/story_tile.dart:33:13`. The real app's colors pass in light and dark |
| 231 | contrast lines per row | ❌→fixed | one line per list row; now one per code and colors (`… and 4 more like it`); the row over the tinted bar stays separate (1.61:1 on #fceae5). Reading order: 27 controls top to bottom, no jumps |

## Native crash reason (ROADMAP §5.8), HN reader on macOS and the iOS simulator

| # | Item | Result | Notes |
|---|---|---|---|
| 232 | uncaught NSException | ✅ | raised in the running, unmodified app through lldb (`[[NSOperationQueue mainQueue] addOperationWithBlock:^{ [NSException raise:…] }]`, then detach). The next `get_errors`, 0.1–1.2 s later: "The app crashed in native code. *** Terminating app due to uncaught exception 'FPFieldTest', reason: '…'"; after the report: `EXC_CRASH (SIGABRT)`, frames, report path. Same on the iOS simulator (hn_reader on iPhone 17; the message from the simulator's log via `simctl spawn`). Frames there are only `main`: the block was lldb's; a real thrower's frames come first (checked on #161's Firebase report: `+[FIRInstallations validateAPIKey:] FIRInstallations.m:162`). Reproducing #161 itself needed editing firebase_app's key; not done |
| 233 | report takes ~20 s | ❌→fixed | the first version waited 12 s for the `.ips` and found nothing: macOS wrote it 22 s after the crash (2 s on another run), and a normal exit also cost 11 s. Now the kernel's `name[pid] Corpse allowed` log line (only for crashes, ~1 s to query) answers at once; frames follow when the report is in. SIGTERM (normal exit): no note, 3 s once |
| 234 | lost before onDone | ❌→fixed | in e2e a tool call hit the dead socket before the connection's `onDone`, which then skipped (not the live connection any more): no crash note. The watch now starts in `_scheduleReconnect`, however the loss was noticed |
| 235 | not covered | ⚠️ gap | Android (`adb logcat -b crash`) unit-tested only: no emulator or adb here. A physical iPhone keeps its reports (`devicectl`). An app that crashes before FlutterPilot connected (Firebase in `main()` can be that fast) has no pid to match |

## Test generation (ROADMAP §6), HN reader and the e2e fixture on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 236 | hn_reader flow | ✅ | `generate_test(start)`, then Settings → Dark → assert "Theme" → System → Saved → Stories → filter "zzzz-no-match" → assert "No stories match"; `generate_test(name: "settings_and_filter")`: 8 steps, `find.text('Settings')`, `find.widgetWithText(TextField, 'Filter stories')`, passed on the first run in 22 s. The dev app (flutter run) kept running during the test run. The test file and the added `integration_test` dependency were then removed from hn_reader |
| 237 | a failing test fails | ✅ | a copy expecting "No stories matchX" failed after the 10 s wait, at the step's line. The response first gave the last 30 lines of output; now "Failed at step 8, expect text (line 43)" and the framework's Expected/Actual |
| 238 | e2e: mock + field + button | ✅ | recorded `mock_http_response(/ping, 201)`, `enter_text(Name)`, tap Send, `assert_widget("Hello, Recorded (201)")`: the test calls `DioPilotInterceptor.mock('/ping', statusCode: 201, …)` and passes on a fresh app (`package:fixture/main.dart`) |
| 239 | generated source | ❌→fixed | unformatted (one 110-char line): the tool now runs `dart format` on it. Not field-tested: Android/iOS runs (the test reinstalls the app there; the response says to start it again), obscured fields (unit-tested: `--dart-define`, never written). Tests over live data (hn_reader's `story_<id>` keys, today's titles) fail tomorrow: the flow above avoids them |

## Scenarios (ROADMAP §7), HN reader and the e2e fixture on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 240 | save and load on hn_reader | ✅ | Settings → Dark, feed filter "AI", `scenario(save: "dark_ai_filter")`: `{"route": "/", "prefs": {"theme_mode": "dark"}, "state": {"riverpod": {"NotifierProvider<SearchNotifier, String>": "AI"}}}`. Back to System and no filter, then `load`: 0.9 s, `theme_mode` dark, the app dark (it reads the preference at startup, so the unsaveable `ThemeMode` enum came back anyway), the feed filtered to AI stories. Removed from hn_reader afterwards and the theme set back to system |
| 241 | state behind the widgets | ⚠️ | the filter provider was "AI" but the filter field showed nothing: the TextField keeps its own controller. Said in the tool description; a scenario can't know which widgets copy which state |
| 242 | noisy "not saved" | ❌→fixed | saving listed `Instance of 'HnApi'`, `SharedPreferences` and an `AsyncLoading` future as "not saved"; now only real values it can't restore (the `ThemeMode` and `Feed` enums) |
| 243 | e2e: mocks across the restart | ✅ | mock `/ping` 202, save, clear the mock, load: the restarted app has 1 mock active before anything calls it, and Send shows "Hello, Scenario (202)". hn_reader has no Dio: mocks are e2e-tested only |

## Verify a feature (ROADMAP §8), HN reader and the e2e fixture on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 244 | "Story filter", 3 criteria | ✅ | empty state for a word no story has (assert "No stories match") ✅, clearing brings stories back (wait_for Bookmark) ✅, dark theme in Settings driven but not checked ⚠️ NOT VERIFIED (the screenshot shows it dark: a picture is not a check). The first attempt at criterion 1 started on the Settings screen and failed; picking criterion 1 again replaced its evidence |
| 245 | misleading reason | ❌→fixed | a failed `assert_widget` was blamed when `enter_text` had failed first (the filter field was not on screen): the reason now names the failed action before the check. Step lines lost the `[extensionError]` prefix, the agent-facing hints and passed checks' raw JSON |
| 246 | network evidence | ✅ | "Switching to New loads the newest stories": `GET …/newstories.json → 200 (668 ms)` and one request per story (30); the report now lists 15 and "… and N more (k failed)" |
| 247 | e2e | ✅ | the fixture (with its intentional overflow) passes "Send greets the user by name" (mock + field + Send + assert), an unchecked second criterion is NOT VERIFIED, report.md and criterion-1.png are written |

## Profile mode (ROADMAP §8), HN reader on macOS (`flutter run --profile`)

| # | Item | Result | Notes |
|---|---|---|---|
| 248 | what works | ✅ | the SDK runs in profile builds: taps, text, assertions, summary, tree, screenshots, audit, state, frame budget, CPU profiles with file:line for app functions (AOT keeps them). hot_reload, generate_test and scenario (built on hot restart) are no longer listed there |
| 249 | debug vs profile numbers | ✅ | `profile_action(tap_widget New, durationMs: 2500)`: debug 219.5 ms Dart on the UI isolate, 2 frames over budget, app widget builds 12.7 ms (IconButton ×10); profile 86.8 ms, none over budget, 1.0 ms. `profile_action` printed "Debug build: times run several times slower" on the profile build too (it assumed debug whenever a framework debug extension answered); now it says which build it is, and so do profile_frame_budget and the summary |
| 250 | source lookups | ❌→fixed | `inspect_widget(key)` returned a type without file:line instead of its "needs a debug build" message (profile builds report widget creation tracking on, but record no locations), and `inspect_widget(x, y)` said "Nothing is drawn" (no `debugCreator` in profile). Source locations now need kDebugMode, and hit tests fall back to the element tree: `layout: true` by point works in profile |
| 251 | app widgets in profile | ⚠️→kept | I relabelled profile rebuild lists "Widgets (app and framework)"; the debug/profile comparison showed the same app-created types and no framework internals in both, so profile builds do know the app's widgets (not where): reverted |

## Security review (ROADMAP §8), the e2e fixture and hn_reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 252 | password field | ❌→fixed | with "s3cret-pin" typed into the fixture's obscured PIN field, 9 read tools were swept: `get_widget_properties(key: PIN)` returned `"text":"s3cret-pin"`; now `"••••••••••"`. The others were clean |
| 253 | secrets the app logs and sends | ❌→fixed | the fixture's Sign in logs `api_key=LOGSECRET1 password: LOGSECRET2` and POSTs to `…/login?api_key=URLSECRET3` with `Bearer HDRSECRET5` and `{"password": "BODYSECRET4"}`. Before: the log line in get_debug_logs and the summary, the URL in get_network_logs. After: `api_key=<redacted> password: <redacted>`, `?api_key=<redacted>&page=1`, `authorization: •••`, body `"password":"•••"` in all six tools. The first sweep had HTTP profiling off, so get_http_profile "passed" on nothing: the sweep now turns it on first and prints what it saw with --verbose |
| 254 | read-only SQL | ❌→fixed (unit) | `WITH x AS (SELECT 1) DELETE FROM users`, `PRAGMA main.journal_mode = DELETE`, `PRAGMA user_version = 5`, `PRAGMA optimize` passed the prefix check; one shared allowlist check now refuses them and still passes `SELECT replace(…)`, strings containing "DELETE" and `PRAGMA table_info(t)`. The existing sqflite/drift tests pass unchanged |
| 255 | shell bridge | ❌→fixed | `curl -H "Origin: https://evil.example" -H "Content-Type: text/plain" localhost:8765 -d '{"name":"get_app_summary"…}'` (what a web page can send without preflight) was answered; now 403, and scripts still work |
| 256 | redactor false positives | ❌→fixed (unit) | the first name pattern hid "author", "passengers", "sessionCount"; `https://` swallowed the query string, so `api_key` in URLs escaped. Both fixed and tested in SDK and server copies |

## Dart MCP interop (ROADMAP §8), the e2e fixture and hn_reader on macOS

| # | Item | Result | Notes |
|---|---|---|---|
| 257 | overlap with `dart mcp-server` 1.1.2 | ⚠️→fixed | listed its tools with the project as root: by default hot_reload, hot_restart, get_runtime_errors, widget_inspector and flutter_driver_command duplicate ours (theirs need a `dtd` connect first). `--disable flutter,dart_tooling_daemon` leaves analyze_files, lsp, pub, pub_dev_search, read_package_uris, rip_grep_packages, roots. `run_tests`/`dart_format`/`launch_app` are off unless enabled (their default, kept). `mcp install` now adds it that way |
| 258 | a plain `flutter run` | ❌→fixed | hn_reader with its URI file hidden: before, "No running Flutter app found"; now a fresh `-p hn_reader` server finds it through the tooling daemon (`dart tooling-daemon --list`, 0.35 s, then `ConnectedApp.getVmServices`) and `get_app_summary` answers. `flutter run --machine` registers too (it prints `app.dtd`) |
| 259 | symlinked temp folders | ❌→fixed | the first e2e run failed both DTD checks: the daemon records `/private/var/…`, the fixture is under `/var/…` (a link). Paths are resolved (nearest existing folder) before matching |

## Consolidating the stack into main (CI on all platforms)

| # | Item | Result | Notes |
|---|---|---|---|
| 260 | web apps | ❌→fixed | profile_action (no CPU samples/VM timeline in the browser), get_http_profile (no dart:io) and get_memory_details cycle/classes (no allocation profile) failed with raw -32601 errors on web. The two tools are no longer listed for web apps (like debug-only tools in profile builds); the modes refuse in one line. e2e checks both lists on web |
| 261 | Android CI | ❌→fixed | failing on main since #17–#24 merged. Not the app: the emulator itself died mid-run (adb lost it, 9 GB free, no OOM kill) after its host GPU layer logged "Failed to find ColorBuffer"; google_apis 33, 34 and 35 all did, `-gpu guest` was ignored. The aosp_atd 34 image passes; the job blocks again. A failed run now says whether the app or the emulator died |
| 262 | native crash on a slow Mac | ❌→fixed | the §5.8 check failed once on CI: the kernel's crash note came after 3 looks, and a slow `log show` (timeout) ended the watch. It keeps looking for 30 s; tools still wait for 3 looks only |

## §9 review: code not yet proven in a real app

| # | Item | Result | Notes |
|---|---|---|---|
| 263 | async ops (`async:true`, `get_operation`, `operationId`, `operationDeadlineMs`) | 🗑️ removed | only 6 read tools (Dio logs, Hive, state...) carried the 3 parameters, and they answer in ms; the slow tools (profile_action, generate_test, leak cycles) never had them, and no field test or agent used them (#70: "rarely needed"). The mutation ordering and a fixed 30 s deadline stay. |
| 264 | SDK extensions no tool calls | 🗑️ removed | `getStreamLogs`/`clearStreamLogs` (+ `StreamInspector`), `tapAt`, `jumpToScreen`, `getPerfMetrics`, `getDebugLogs`, `auditMemoryHealth` (+ `MemoryAuditor`): registered in every app, reachable by no tool, their tools deleted earlier (§4.2). `sdk_extensions_used_test.dart` keeps it that way. |
| 265 | screenshots of dialogs (and the 🤖 badge) | ❌→fixed | `capture_screenshot`/`compare_screenshot` captured the first repaint boundary: the bottom page. A `showDialog` (root navigator), or any popup in an app with one navigator, was missing, and the contrast audit measured a dialog's text against the page behind it. hn_reader's context menu showed only because it opens on a tab's nested navigator. The badge was left out by the same accident. Now the view's root layer, after a forced frame that removes the badge; e2e fails on the old capture ("a dialog is in the screenshot"). |
| 266 | scrolling to a widget (`scroll_into_view`, tap_widget's auto-scroll) | ❌→fixed | lab app on macOS, window covered: before, only items already built were reached (Item 150/499, a list opened mid-way, a grid, a reversed list: not found after 3–7 s); a card in a horizontal row inside a vertical list crashed ("Null check operator"); "Item 3" tapped "Item 399" (only partial match on screen); a missing item took 6 s. After: all found (0.3–3 s; nested card ~5 s; not found 1.7–3 s), the exact item tapped. Frames on a covered window arrive every ~70 ms, so the search builds and lays out itself; skipping the frame's finalizeTree left scrolled-out rows inactive and threw from a scroll-metrics microtask (fixed). e2e fails on the old code ("Row 3"). |
| 273 | `get_flight_log` (hn_reader, macOS) | 🗑️ removed | 3 actions (chip tap, text entry, bookmark tap) → 1 event: a pointer-down on `IgnorePointer` with a `GlobalKey`. Story → back: no route events (go_router changes never reached it), no key or text events. After the first error it froze on that snapshot, so every later event was hidden until cleared. §6 (generate_test) was built without it; `get_errors(report: true)` has the route and last requests. Deleted with the global pointer route that hit-tested every pointer-down in the app to feed it, and `DiagnosticPayload` (its only user). 66 → 65 tools. |
| 274 | `navigate_to` to an unknown go_router route | ❌→fixed | `navigate_to("/bookmarks")` (hn_reader's route is `/saved`) answered "Navigated to /bookmarks" while the app showed go_router's error page and our plugin's route listener threw `Bad state: No element` into the app (`router.state` with no match). `push` to an unknown route added an error page on top and also "succeeded". Now: "No route matches "/bookmarks". Routes: /, /saved, /settings, /search, /story/:id", the app is put back where it was (pop for push), and the listener reads the configuration's URI. Plugin test on go_router 15, field-tested on 18. |
| 275 | plugin write tools (`supabase_session`, `set_secure_storage_key`, `set_shared_preference`) | ✅ | all behind `--allow-destructive` and say so; the Firebase write tools §9 listed (`log_analytics_event`, `record_crashlytics_error`) went with the old Firebase plugin (§2.1). |
| 276 | example app | 🔁 replaced | 12 demo screens (5.4k lines) advertised deleted tools (`get_perf_metrics`, `get_gc_stats`…) on old plugin majors. Now a todo app (Dio, Riverpod 3, go_router 18, shared_preferences) with a widget test in CI and a README walkthrough, every step of it run through the bridge on macOS. |
| 277 | `mock_http_response` with an error status (example app) | ❌→fixed | a mocked 500 was `resolve`d: Dio skips `validateStatus` then, so the app got a successful response whose data was the error body (`get<List>` → a type error, "Couldn't load todos" without the status). A status the request's `validateStatus` rejects now fails as `DioException.badResponse`, like the server's, and is logged `[MOCKED]`. |
| 278 | pull to refresh with `swipe_widget` (§1.8 "unverified") | ❌→fixed | on macOS a down swipe showed the indicator and loaded nothing. Apple's bouncing physics overscroll less the further they go: 20 moves over 300 px never armed a RefreshIndicator in a 494 px list (measured: 20 moves need ~500 px in 600; Flutter's own `dragFrom` gets there only by jumping in 2–3 moves). A swipe down in a RefreshIndicator whose list is at its top now pulls from the list's top by 85% of its height and answers "Pulled to refresh". Android and macOS tests; the response said "a progress indicator is showing" while nothing loaded. |
| 279 | checkboxes by screen reader label | ❌→fixed | 15 rows listed as "Checkbox" ×15; `toggle_checkbox(key: "Done: Buy milk")` (its `semanticLabel`) → not found. Finders and the tappable list now read Semantics labels the app wrote (Checkbox/Image `semanticLabel`, `Semantics(label:)` in app code), not the framework's own ("Dismiss" on a drawer's scrim). Profile builds have no creation locations, so there they are still unnamed. |
| 280 | unknown tool arguments | 🔎 open | `get_network_logs(clear: true)` (no such parameter) answered with the logs, cleared nothing and said nothing. |

## §1 re-check (hn_reader, macOS, 2026-10-01)

| # | Item | Result | Notes |
|---|---|---|---|
| 284 | `set_state` on an enum state | ❌→fixed | `set_state(name: "Feed", value: "new")` answered `type 'String' is not a subtype of type 'Feed' of 'newState'`: an enum can't be built from JSON without reflection, and the description only promised an explanation for class states. Now: "NotifierProvider<FeedNotifier, Feed> holds a Feed (Feed.top); a JSON value (String) can't be converted to it … for an enum state, drive the UI". An int now sets a double state (the Bloc plugin already did). The other §1 items (1–9) checked out: see ROADMAP §1. |

## §8 parallel devices (hn_reader: iPhone 17 simulator + macOS, 2026-10-01)

| # | Item | Result | Notes |
|---|---|---|---|
| 285 | `run_on_devices` (new) | ✅ | wait_for → tap "Best" → wait_for on iphone + mac in parallel: 1.7–1.9 s, both passed; "new errors: iphone 13 (last: A RenderFlex overflowed by 132 pixels on the right.)" — the story subtitle Row on a 402 pt wide screen. A failing assert shows each device's reason in one line. Three devices (a stale copy started from the build folder): 400 ms; its tab labels ("Stories" vs "Stories Tab 1 of 3", an older SDK) listed as "tappable on mac2 only". |
| 286 | errors in the comparison | ❌→fixed | the first version counted `recentErrors` from the snapshot: the iPhone's launch-time overflows (5) showed as the flow's. The SDK's snapshot now has `errorCount` (all captured, past the 10-entry buffer) and `lastError`; the report counts the difference before/after, and nothing for an SDK without it. "Only on X" for tappables was misleading with 3 devices (an element on 2 of 3 read as "only on" each); now grouped by the devices that have it. |
| 287 | register_device → run_on_devices | ❌→fixed | e2e called run_on_devices right after registering the second device: "Tool 'run_on_devices' is disabled" — the list was refreshed in the background. register_device now waits for it. |

## CI flakiness (required checks failing at random)

Failing checks over the last 30 CI runs (90 Apple/web e2e jobs; Android before #48 excluded):

| # | Item | Result | Notes |
|---|---|---|---|
| 267 | read before the frame (macOS `backspace edits the field`, 1×) | ❌→fixed | the key edited the field ("Pilo") but the response had no widget-tree diff: `pumpAndSettleAdaptive` waits for two frames but gave up after 80 ms (150 ms for press_key); a slow runner, or a covered window (~70 ms a frame), needs longer. Now 1 s (two frames still take ~32 ms normally), and frames are forced while the window is hidden. |
| 268 | iOS: Dart Tooling Daemon discovery + doctor (7× each) | 🔎 still open | #53's output: `dart tooling-daemon --list` answered in 102 ms with the fixture's daemon, so neither a slow listing (#54 read the instance files instead; reverted) nor a missing daemon. The app is lost after that: in the daemon's `getVmServices` answer or the root match. A failed check now prints `DtdDiscovery.report`: each daemon's raw answer and, per app, whether it counts as under the roots (real paths). |
| 269 | iOS: `profile_action` (10×), then `mocked response reached UI` / `network log has mocked call` (3×) | ❌→fixed (#272) | the simulator was busy with first-boot indexing (the app's log: "Indexed: 1097 … Finished in 331.678776s") while the first attempt ran; the connection was already gone at `getFlagList`, before any sampling. #54 dropped the 250 µs sampling for this; restored (short actions need the finer samples). |
| 270 | iOS: `viewport is landscape` (4×) | ❌→fixed (#272) | same busy simulator. #54's wait (set_app_settings returns once the view has turned, ≤ 2 s) is kept. |
| 271 | iOS: keyboard (`a character is typed`, `arrow`, `select all`, 2×) | ❌→fixed (#272) | same busy simulator (12–15 s per step). #54 made any key re-focus the last text field when nothing had focus: a field the app, Enter or a tap had unfocused got typed into. Reverted; a test now checks that a key after unfocus leaves the field alone. |
| 272 | iOS: the first attempt ran on a busy simulator | ❌→fixed | the CI log of #53's first attempt: booted 18:51, Shortcuts indexing for Spotlight 18:55:44–19:01:15 ("Indexed: 1097 … Finished in 331.678776s", printed with the app's log), app running at 19:00:17 — the checks ran in it; the retry, on a simulator done with it, passed. A fresh iPhone 17 simulator on a 10-core Mac: 500–900% CPU for ~1 min, 100–300% until ~3.5 min (lsd, siriactionsd, BackgroundShortcutRunner, STExtractionService, healthappd…), then quiet. CI now boots the simulator first and `tool/ci_wait_simulator_idle.sh` waits until its processes (on the host, under its RuntimeRoot) use under 60% CPU for 30 s, at least 5 min after boot, at most 15; it logs what was busy. |

## §10 performance targets (hn_reader, macOS, debug; medians of 8 calls)

| # | Item | Result | Notes |
|---|---|---|---|
| 281 | slow calls on a hidden or covered window | ❌→fixed | the §10 "Now" numbers came from App Nap, not our code: once the window had been hidden a while the app ran at scheduling priority 4 (background QoS) and its timers were throttled — tap 386 ms (279–558), tree 13–28 ms, summary 16–22 ms, the same with the old SDK. Just after launch (priority 31+) the same calls took 156 / 5 / 4 ms. While an agent is active (until 30 s after the last call, as the frame pump) the SDK now holds an `NSProcessInfo` activity (user-initiated, latency-critical, idle sleep allowed) through `dart:ffi`: priority 47, tap 156 ms, tree 5 ms, summary 5 ms on the hidden window; released on time (priority back to 4). |
| 282 | forced-frame pump CPU (hidden window) | ❌→fixed | 60 Hz for 30 s after every call: ~20% CPU (debug) while the agent thinks. Now 60 Hz for 2 s after a call or while an animation ticks, ~10 Hz otherwise, and a call arriving at 10 Hz forces a fresh frame first: ~5% CPU, the same latencies. |
| 283 | `get_widget_tree` size (feed of 5 stories) | ❌→fixed | 10.8 KB → 6.9 KB: bounds as `rect: [x, y, w, h]`, left out where equal to the parent's (7 wrappers at 800×600 on the feed), no selector on a Text (it repeated the text), keys as written (`story_1`, not `[<'story_1'>]`), and framework widgets' numeric keys (NavigationBar's `LayoutId` slots) no longer kept as nodes. The tap diff still compares the tree as captured. |

## Latency observed (debug mode, macOS, HN reader)
- 2026-10-01, after #281–283, window hidden: nav stack / errors / assert_widget 1–2 ms, get_widget_tree 5 ms (6.9 KB), get_app_summary 5 ms, tap_widget (feed chip, incl. settle + diff) 156 ms (142–173). Before (below) was App Nap.
- zero-code (plain app): summary 70–230 ms, tree 30–90 ms (full inspector tree: ~60–90 ms / 0.9 MB on HN reader), screenshot 45–130 ms (up to ~350 ms at 1.0x when it has to be cropped)
- trivial read (nav stack): 15–30 ms; get_widget_tree: 40–120 ms; get_app_summary: ~100–180 ms
- tap_widget with post-action state: 300–450 ms (first calls after hot restart: 1–2 s, JIT)
- hot_reload ~300 ms; hot_restart ~350–500 ms
