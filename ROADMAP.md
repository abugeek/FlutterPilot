# FlutterPilot Roadmap

Handoff document for the next agent (or human). Read this, then `CLAUDE.md`.

**North star:** a *useful, working* tool, not a feature-rich one. Every tool must
be proven on a real app before it ships, return honest results (never "success"
when nothing happened), and cost the agent as few tokens as possible. Fewer
tools that always work beat many tools that sometimes work.

---

## 0. State as of 2026-09-27 (PR #1 merged)

- 136 MCP tools (down from 164). SDK + 12 plugins + server + CLI. All packages
  analyze clean and pass unit tests.
- `packages/flutterpilot_server/tool/e2e_test.dart` — the real gate: creates a
  fresh app, runs `flutterpilot init --local`, launches it with `flutter run`,
  drives it through the MCP server over stdio. 25/25 checks pass on macOS.
- Field-test app: `../hn_reader` (sibling of this repo, its own git history):
  Hacker News reader with Riverpod 3, go_router 18, Dio (+ Algolia search),
  sqflite bookmarks, shared_preferences theme, connectivity banner, right-click
  context menu, Enter-to-search. Launch it with
  `flutter run -d macos --vmservice-out-file=.dart_tool/flutterpilot_vm_uri`.
- Only macOS desktop has been field-tested. iOS/Android/web: untested.
- Plugins field-tested: riverpod, go_router, dio, sqflite, shared_preferences,
  connectivity (read-only). **Untested in a real app:** bloc, drift, hive,
  supabase, firebase, secure_storage.

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

## 1. Finish the cleanup (small, do first)

Each item was observed in the field test; file:line pointers are in git history
of PR #1.

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

## 2. Coverage the product claims but hasn't proven

1. **Second real app for untested plugins:** e.g. a notes app with Bloc +
   Drift + Hive + secure_storage + Supabase auth. Field-test every plugin tool;
   delete the ones that don't hold up.
2. **Mobile + web:** run the e2e and the field test on iOS simulator and
   Android emulator (touch vs mouse pointers, keyboard/IME, lifecycle, native_*
   tools which are iOS-only today) and on web (DWDS VM service differs;
   hot restart path differs). Gate platform-specific tools so they don't show
   up where they can't work.
3. **Zero-code mode** (no SDK installed) is advertised but untested.
4. **Multi-device fleet** (`register_device`/`switch_device`) untested.
5. **VS Code extension** (`packages/flutterpilot_vscode`) untested — test or remove.
6. **CI:** there is none (PR #1 had zero checks). Add GitHub Actions: analyze +
   unit tests for every package on Linux; `e2e_test.dart` on a macOS runner.
   Required status check on `main`.

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

## Definition of done for any roadmap item

- Proven on a real app through the MCP tools, not only unit tests.
- A check in `e2e_test.dart` if it's user-visible.
- Honest responses (errors say why and what to do next), small outputs.
- All packages analyze clean, all tests pass, `TOOLS.generated.md` regenerated
  (`dart run packages/flutterpilot_server/tool/generate_tools_doc.dart`).
