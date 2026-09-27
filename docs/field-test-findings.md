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

## Latency observed (debug mode, macOS, HN reader)
- trivial read (nav stack): 15–30 ms; get_widget_tree: 40–120 ms; get_app_summary: ~100–180 ms
- tap_widget with post-action state: 300–450 ms (first calls after hot restart: 1–2 s, JIT)
- hot_reload ~300 ms; hot_restart ~350–500 ms
