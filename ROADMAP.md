# FlutterPilot Roadmap

Handoff document for the next agent (or human). Read this, then `CLAUDE.md`.

**North star:** a *useful, working* tool, not a feature-rich one. Every tool must
be proven on a real app before it ships, return honest results (never "success"
when nothing happened), and cost the agent as few tokens as possible. Fewer
tools that always work beat many tools that sometimes work.

---

## 0. State as of 2026-09-27 (PR #1 merged)

- 129 MCP tools (down from 164). SDK + 12 plugins + server + CLI. All packages
  analyze clean and pass unit tests.
- `packages/flutterpilot_server/tool/e2e_test.dart` — the real gate: creates a
  fresh app, runs `flutterpilot init --local`, launches it with `flutter run`,
  drives it through the MCP server over stdio. 32/32 checks pass on macOS
  (also runs in CI on `macos-latest`).
- Field-test app: `../hn_reader` (sibling of this repo, its own git history):
  Hacker News reader with Riverpod 3, go_router 18, Dio (+ Algolia search),
  sqflite bookmarks, shared_preferences theme, connectivity banner, right-click
  context menu, Enter-to-search. Launch it with
  `flutter run -d macos --vmservice-out-file=.dart_tool/flutterpilot_vm_uri`.
- e2e passes on macOS, iOS simulator, Android emulator and web (Chrome);
  all four run in CI. Field tests (real apps) so far on macOS only.
- Plugins field-tested: riverpod, go_router, dio, sqflite, shared_preferences,
  connectivity (read-only) in `../hn_reader`; bloc, drift, hive_ce,
  secure_storage, supabase in `../notes_app`. **Untested in a real app:**
  firebase.

### How to work (the method that found every real bug so far)

1. Build or extend a *real* feature in a real app (`../hn_reader`, or a new app
   for untested plugins — see §2.1).
2. Drive it only through FlutterPilot tools, like an agent would:
   `cd packages/flutterpilot_server && dart run tool/fp_bridge.dart -p ../../../hn_reader`
   then `curl -s localhost:8765 -d '{"name":"<tool>","arguments":{...}}'`.
   `tool/.fp/calls.jsonl` records latency and response size per call.
3. For each tool ask: did it do the thing? Is the response true? Is it small?
   Would an agent pick the right tool from its description?
4. Fix at the root, add a check to `e2e_test.dart` for anything user-visible,
   run all package tests + e2e before committing.
5. If a feature can't be made to work honestly, delete it.

### Gotchas that cost hours (don't rediscover them)

- **Hidden windows:** when the app window is covered/minimized the OS reports
  `AppLifecycleState.hidden` and Flutter stops frames. The SDK now pumps forced
  frames while an agent is active (`_ensureFreshFrame` in `flutterpilot_sdk.dart`).
  If something looks stale, check `get_app_summary` → "App window: hidden".
- **Hot reload can't re-run global/static initializers or change registered
  service-extension closures** → SDK changes and provider definitions need
  `hot_restart`. In-app mocks/state reset on restart.
- **macOS sandbox:** apps need `com.apple.security.network.client` in both
  entitlement files or all HTTP fails with `errno = 1`.
- **Riverpod 3 retries failed providers forever by default** (endless spinner).
- **`dart format` on a whole directory reformats unrelated files** → format
  only files you touched.
- Shell: BSD `sed` has no `\|`; zsh doesn't word-split `$VAR` into a command;
  never `git stash` during a merge (drops `MERGE_HEAD`).
- Tests mocking gestures: an empty `SizedBox` under a `GestureDetector` is not
  hittable unless `behavior: HitTestBehavior.opaque` (that's real Flutter).

---

## Rules for agents working on this repo

Learned from reviewing agent-made changes:

1. **Work on a branch and commit.** Uncommitted work in the main checkout is
   invisible to reviewers and easy to lose.
2. **Run `tool/e2e_test.dart` before saying "done".** In one review, the e2e
   test would have shown 5 action tools returning errors (a missing `await`
   on a function made async) — the unit tests were all green.
3. **Add a test for every behaviour you change.** ~800 changed lines with zero
   new tests means nothing proves the changes work.
4. **Change both ends.** A server feature that reads a field the SDK never
   sends (e.g. error `severity`) silently does nothing. Verify in the real app.
5. **Version ranges must include today's release.** Twice an agent capped a
   plugin below the current major (`flutter_bloc ^8`, then `go_router <16`,
   `connectivity_plus <7`, Firebase, secure_storage) — every up-to-date app,
   including `../hn_reader`, failed `pub get`. Upper bound = next major after
   the latest on pub.dev, and verify with `flutter pub upgrade` + tests.
6. **Code injected into a user's `main.dart` must compile** on the template,
   `runApp(const MaterialApp(...))`, and arrow `main() =>` apps; `init`
   unit tests cover these now.
7. **Schema first.** A parameter alias only helps if the tool's JSON schema
   accepts the new name — MCP validates arguments before your code runs.

## 1. Finish the cleanup (small, do first)

Each item was observed in the field test; file:line pointers are in git history
of PR #1.

**Status (2026-09-27, second agent + review):** items 1–13 are addressed:
perf tools deleted, `key`/`target` accepted by every widget tool (schema and
callbacks), Riverpod state accepts plain values and short names without
`--allow-destructive`, `exec_sql_query` auto-detects, Dio logs bodies,
plugins have explicit `register()`, crash report 41 KB → ~4.5 KB with the
failing line, overflows no longer mark the app unstable, keyboard dispatch
uses one path, post-action state waits for route transitions. **Follow-up (agent + review):** `init` now injects the
text-scale/locale wiring (only the parts that can take effect; arrow `main`
supported; import guaranteed), `wait_for_widget` removed, navigation waits for
route transitions before the next tap, plugin version ranges bounded to the
current major. §1 is done.

**Loose ends closed (2026-09-27, branch `chore/ci-and-section1-loose-ends`):**
- CI had failed at the format step on *every* run since it was added, so
  analyze and tests never ran there. One format-only commit; CI now runs
  format, analyze, tests, the plugin-range check and the macOS e2e.
- `tool/check_plugin_ranges.dart` (repo root) fails when a plugin's
  constraint rejects the latest release of its host package; CI runs it on
  every push and weekly (cron), so a new go_router/flutter_bloc major shows
  up without anyone pushing.
- Fleet: after the app restarted on a new port, the active device kept its
  dead URI; the connect path now refreshes it.
- README tool list rewritten without counts (it named four tools that no
  longer exist); `TOOLS.generated.md` is the reference.
- **Still manual:** make `analyze-and-test`, `e2e-apple-web (macos|ios|web)`
  and `e2e-android` required status
  checks on `main` (GitHub → Settings → Branches).

1. **Weak perf tools — fix or delete:**
   - `get_perf_metrics`: "FPS" on an idle app is meaningless → delete; point to
     `profile_frame_budget` + `get_memory_details`.
   - `get_gc_stats`: returns heap only, no GC data → delete (or read real GC
     counts from `getIsolate().extensionRPCs`/`getAllocationProfile(gc: true)`).
   - `audit_memory_health`: only checks the image cache → either implement the
     real check (decoded image size vs displayed size, via
     `debugInvertOversizedImages`/`ImageCache.currentSizeBytes` per image) or delete.
   - `enable_widget_rebuild_tracking`: no way to read counts → implement a readout
     (`ext.flutter.inspector.trackRebuildDirtyWidgets` + `Flutter.RebuiltWidgets`
     events, aggregated per creation location) or delete.
2. **Consistent parameters.** Today: `key` / `target` / `selector` / `rootKey`
   / `expect` / `dbName`, and booleans typed as strings. Pick one noun
   (`target`), accept old names as aliases for a release, fix schemas.
   Merge `wait_for_widget` into `wait_for_condition`.
3. **State tools:** `set_riverpod_state` needs `--allow-destructive` although it
   only touches memory — allow it by default (keep the flag for storage/DB).
   Accept plain values, not only JSON-encoded. Match provider names loosely
   (`FeedNotifier` → `NotifierProvider<FeedNotifier, Feed>`) and list
   candidates on a miss (`wait_for_state` has the same problem).
4. **`exec_sql_query`** claims to auto-detect the database but fails without
   `dbName` even when exactly one is registered.
5. **Dio plugin:** log request/response bodies (truncated + redacted) and the
   error message on failures; mark mocked responses; the 50-entry cap is
   flooded by N+1 request patterns → group or raise it. Its tool description
   promises payloads it doesn't return.
6. **Plugin registration timing:** plugins register extensions only when first
   constructed (lazy `Dio()`, lazy DI) → tools say "not registered". Give
   plugins an explicit `register()` called at startup, consistent across all
   plugins, and have `flutterpilot init` print it.
7. **Response size budget:** `get_latest_crash_report` is ~41 KB (raw + compact
   stacks + full tree). Target < 4 KB. Add a size assertion to e2e for the
   top tools (summary, tree, crash report, action responses).
8. Small bugs: `get_widget_properties` reports TextField `isEnabled:false`;
   `list_connected_devices` is empty for an auto-discovered app;
   `set_device_rotation` says "success" on desktop; `jump_to_screen` says
   "state injected" when none was passed; the tappable list captured during a
   page/menu transition shows the old screen (wait for route animations in
   `getPostActionState`); pull-to-refresh via `swipe_widget` unverified.
9. **Docs sweep:** `TOOLS.md` (hand-written) duplicates `TOOLS.generated.md`
   and drifts — delete it or generate it. README still advertises old
   category counts.

10. **Self-heal is alarmist and heavy:** a 38px layout overflow is logged as
    "🚨 CRITICAL APP CRASH", marks the app UNSTABLE, and every captured error
    fires 6 extension calls (including a full widget tree) from the server
    (`SelfHealManager.handleCrash`). Classify by severity (layout vs uncaught
    exception), debounce repeated errors, and fetch diagnostics lazily when
    `get_latest_crash_report` is actually called.
11. **Keyboard simulator** (`keyboard_simulator.dart`) dispatches each key
    twice — `HardwareKeyboard.handleKeyEvent` *and* the deprecated
    `keyMessageHandler`. Use one correct path (the platform key-data path
    `KeyEventManager.handleKeyData` like flutter_test's `KeyEventSimulator`),
    and decide what "type characters" means per platform (desktop text editing
    goes through the OS text-input client, so Backspace/characters don't edit
    fields today — `enter_text` is the supported way).
12. **Text scale / locale overrides** need the app to wrap MaterialApp in a
    `ValueListenableBuilder` (tools now say so). Let `flutterpilot init` inject
    that wiring, like it injects `NavigationTracker`.
13. **Settle timing:** post-action state is read ~150 ms after an action, so
    during page/menu transitions (~300 ms) it can list the previous screen's
    elements. Wait for route animations (`ModalRoute.animation` status) and
    popup menus before snapshotting.

## 2. Coverage the product claims but hasn't proven

1. **Second real app for untested plugins:** done for Bloc, Drift, Hive CE,
   secure_storage and Supabase — `../notes_app` (own git repo; local Supabase
   via `supabase start`, ports 553xx, test account in
   `supabase/seed_accounts.md`). 22 findings, all fixed: see
   `docs/field-test-findings.md` round 4. Left: **Firebase** (needs the
   emulator suite), plain `hive` (only `hive_ce` exercised).
2. **Mobile + web:** e2e done — identical results on macOS, iOS simulator,
   Android emulator and Chrome (tap, text, keys, secondary tap, pinch,
   rotation, chains, hot reload + restart; web via DWDS). The `native_*`
   tools are listed only when the app runs on iOS and `idb`/`xcrun` exist
   (`tools/list_changed`). Left: `native_tap/text/button/describe_screen`
   are untested (idb not installed here); field-test a real app on a phone
   (IME, permissions dialogs, lifecycle/backgrounding).
3. **Zero-code mode:** done — plain app on macOS + Chrome (`e2e_test.dart
   --zero-code`, in CI for macOS and web). Without the SDK only the 29 tools
   that work are listed (`zeroCodeTools` in `src/zero_code.dart`): tree,
   screenshot and errors come from Flutter's inspector, plus hot reload,
   debug toggles, memory/HTTP profiles and logs. Findings: round 6 of
   `docs/field-test-findings.md`. Left: driving the app (taps, text) would
   need expression evaluation — not attempted; iOS/Android zero-code
   untested.
4. **Multi-device fleet:** done — hn_reader on macOS + iPhone simulator and
   a plain app on Chrome through one server (round 7 of
   `docs/field-test-findings.md`). `deviceId` on 39 tools was ignored by
   most of them (answers came from the wrong device) and is gone:
   `switch_device` is the one way to target a device. Register checks the
   app is running and accepts the `http://` URI `flutter run` prints; list
   shows platform / app / SDK / "not running"; a failed switch stays on the
   current device. e2e checks register/list/switch/refusals. Left: running
   the same flow on several devices at once (§8 "Parallel devices").
5. **VS Code extension:** removed. It had never worked: it sent `tools/call`
   without the MCP `initialize` handshake (every call rejected), found the
   server via a path that exists only inside this repo, polled tools that
   don't exist (`get_bloc_state`), had no icon and no tests, and ran a
   private server the AI agent never talks to. VS Code agents use the
   `.vscode/mcp.json` config in the README; §3.2 (`flutterpilot mcp
   install`) should write it. Not yet verified inside VS Code itself.
6. **CI:** done (`.github/workflows/ci.yml`): format + analyze + tests +
   plugin-range check on Linux; `e2e_test.dart` on macOS, iOS simulator and
   Chrome (macos runner) and Android emulator (Linux + KVM); weekly cron.
   Left: mark them as required checks on `main`.

## 3. Setup that "just works"

1. **No `-p` needed:** the server should find the app without being started in
   the app folder: scan `.dart_tool/flutterpilot_vm_uri` under the MCP client's
   workspace roots (MCP `roots` capability), or discover via the Dart Tooling
   Daemon (DTD) that `flutter run`/IDEs already run.
2. **`flutterpilot mcp install`**: writes the MCP config for Claude Code /
   Cursor / VS Code for the current project (the exact `claude mcp add ...`
   line with `-p`), and `flutterpilot dev` prints it.
3. **Publish to pub.dev** (sdk, plugins, server, cli) with a melos release
   flow, so `init` can use hosted versions instead of git deps. Needs
   `dependency_overrides` removal and version constraints between packages.
4. **`flutterpilot doctor`**: verify entitlements, SDK wiring, plugin
   registration, VM service reachability, and print exact fixes.

## 4. Token efficiency (agents pay for every tool and every byte)

1. **Expose only relevant tools:** register plugin tools only when the app
   reports that capability (`get_capabilities` already knows), and send
   `notifications/tools/list_changed` after connect. Hide iOS-only native tools
   on other platforms. Target: an app without Supabase/Firebase/Hive never
   sees those ~20 tools.
2. **Shrink further:** candidates to merge/remove after field-testing —
   `navigate_to` / `jump_to_screen` / `simulate_deep_link` / `gorouter_navigate`
   (one navigation tool), the `wait_*` family (one), `read_dart_file` /
   `list_dart_files` / `get_build_config` (coding agents already read files),
   `start_recording` / `stop_and_generate_test`. Realistic target: 60–80 tools.
3. **Tool descriptions:** remove marketing language ("360-degree", "<5ms",
   "Superpowers"); state what it returns and when to use it. Agents choose
   tools from descriptions.

## 5. DevTools parity — what developers actually open DevTools for

Highest value first. Each should answer a *why*, not just dump data.

1. **"What code draws this?"** — `inspect_at(x, y)` / `inspect(target)`:
   returns the widget's creation location (file:line) and its ancestor chain
   of app widgets. Uses `WidgetInspectorService` creation locations (already
   used for the summary tree). This is the single most useful tool for an
   agent fixing UI.
2. **CPU profile around an action:** `profile_action(action)` — start
   `getCpuSamples`, run the tap/scroll, stop, return the top functions by
   self time *in app code* (filter framework), with file:line.
3. **Jank explanation:** for janky frames, which widgets rebuilt and how long
   build/layout/paint took (timeline events + rebuild tracking readout).
4. **Layout explorer:** constraints and sizes up the ancestor chain for a
   widget ("why does this Row overflow / why is this Expanded 0 wide").
5. **Memory leak check:** navigate into/out of a screen N times, compare class
   instance counts (or integrate `leak_tracker`), report retained classes.
6. **Network detail:** `get_http_profile` request detail (headers, bodies) via
   `getHttpProfileRequest`; works for any dart:io client, not only Dio.
7. **Accessibility audit:** missing semantics labels on icon buttons, contrast
   ratios, focus order — on top of the (now honest) tap-target check.

## 6. Test generation done right

The old generators were deleted because the output couldn't run. Rebuild only
with a verification loop:

1. Record semantic actions (targets by key/text, not coordinates) plus the
   assertions an agent made.
2. Emit an `integration_test` using the app's real entrypoint (`main.dart`),
   with `find.byKey` / `find.text` finders and the same postconditions.
3. **Run it** (`flutter test integration_test/...`) and only report success
   if it passes. Mocked network responses become test fixtures with bodies.

## 7. State time travel done right

Deleted because nothing captured/restored state. A real version:
- Riverpod: snapshot provider values and restore via overrides in a
  re-created `ProviderContainer` (needs plugin support), or
- Simpler and more honest: "reset to scenario" = hot restart + deep link +
  seeded mocks/prefs, driven by a named scenario file checked into the app.

## 8. Longer-term vision

- **Verify-a-feature macro:** given acceptance criteria in plain language,
  the agent drives the flow and returns a pass/fail report with evidence
  (diffs, screenshots, network log). This is FlutterPilot's reason to exist.
- **Interop with the official Dart & Flutter MCP server:** don't duplicate
  analyze/test/pub/hot-reload basics; focus on live-app driving, runtime state
  and profiling. Consider sharing the Dart Tooling Daemon connection.
- **Profile-mode support** for trustworthy performance numbers (debug-mode
  timings are inflated).
- **Parallel devices:** run the same flow on iOS + Android + web and diff
  results.
- **Security review:** remote VM connections, redaction coverage (PII in
  trees, logs, network bodies), destructive-operation gating.
- **Docs site + short demo** of the real loop (bug → mock → fix → verify).

---

## 9. Code not yet reviewed in a real app (suspect until proven)

These exist and compile, but nobody has checked them against real behaviour.
Review each the same way as PR #1 — keep, fix, or delete:

- **`ai_overlay_manager.dart`** — the "🤖 AI Tap" ripple. Verify it is *not*
  captured in `capture_screenshot` / `compare_screenshot` (would make visual
  diffs flaky) and not listed in widget trees or tappable elements.
- **`operation_scheduler.dart` + `get_operation` / `cancel_operation` /
  `async:true` / `operationDeadlineMs`** — a lot of machinery added to every
  tool's schema (5 extra params each). Calls take milliseconds; measure whether
  any agent ever needs async/cancel, otherwise delete and shrink every schema.
- **`scroll_simulator.dart`** (`scroll_into_view`, auto-scroll before tap) —
  test on long lists, nested scrollables, horizontal lists, lazy lists where
  the target isn't built yet.
- **`stream_inspector.dart`** (`get_stream_logs`) — WebSocket/stream capture;
  what wires it? Probably nothing in a normal app.
- **`flight_recorder.dart`**, `get_flight_log`, `start_recording` /
  `stop_and_generate_test` — useful only if §6 is built on top.
- **`native_automation_tools.dart`** (`native_tap` etc., needs `idb`, iOS
  simulator only) — test on a simulator or hide on other platforms.
- **Plugin write tools** that make real network calls (`supabase_sign_out`,
  `log_analytics_event`, `record_crashlytics_error`, ...) — keep behind
  `--allow-destructive` and verify they're labeled as such.
- **Example app** (`examples/flutter_pilot_example`) — 12 demo screens incl.
  `chaos_screen.dart` and `animation_lab_screen.dart` referencing removed or
  untested features. It's a showcase, not a test; trim it to what the tools
  still do, or replace it with the e2e fixture.

## 10. Performance targets

Measured in debug mode on macOS (see `docs/field-test-findings.md`). Keep
these as budgets, add assertions to e2e:

| Operation | Now | Target |
|---|---|---|
| Trivial read (nav stack, errors) | 15–30 ms | < 20 ms |
| `get_widget_tree` (HN feed) | 40–120 ms, ~14 KB | < 60 ms, < 8 KB |
| `get_app_summary` | 100–180 ms, ~1–2 KB | < 80 ms |
| `tap_widget` incl. post-action state | 300–450 ms | < 200 ms |
| `findElement` | ~10 ms | < 10 ms |

Known costs: post-action state captures the tree twice and lists interactive
elements (hit-testing each); the forced-frame pump runs at 60 Hz for 30 s after
the last call while the window is hidden (CPU cost; consider 20–30 Hz).

## Where things are

- `docs/field-test-findings.md` — every tool observation (88 rows), latency.
- `../hn_reader` — field-test app. It **intentionally** keeps a layout bug:
  the story subtitle `Row` in `lib/ui/story_tile.dart` overflows at 1.6× text
  scale (used to test overflow detection) — don't "fix" it without adding
  another known defect.
- `packages/flutterpilot_server/tool/e2e_test.dart` — the gate.
- `packages/flutterpilot_server/tool/fp_bridge.dart` — shell driver.

## Definition of done for any roadmap item

- Proven on a real app through the MCP tools, not only unit tests.
- A check in `e2e_test.dart` if it's user-visible.
- Honest responses (errors say why and what to do next), small outputs.
- All packages analyze clean, all tests pass, `TOOLS.generated.md` regenerated
  (`dart run packages/flutterpilot_server/tool/generate_tools_doc.dart`).
