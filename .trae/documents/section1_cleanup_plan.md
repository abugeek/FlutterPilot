# Section 1 Cleanup Implementation Plan

## Repository Research

### Project State (from ROADMAP.md §0)
- 136 MCP tools across SDK + 12 plugins + server + CLI. All packages analyze clean, unit tests pass.
- Gate: `packages/flutterpilot_server/tool/e2e_test.dart` (25/25 checks pass on macOS).
- Field-tested on macOS only; plugins proven: riverpod, go_router, dio, sqflite, shared_preferences, connectivity (read-only).
- North star: fewer tools that always work, honest responses, minimal token cost.

### Section 1 Problem Summary
Thirteen field-test observations grouped into:
1. **Weak perf tools** that return misleading/useless data
2. **Inconsistent parameters** across the 136-tool surface (`key`/`target`/`selector`/`rootKey`/`expect`/`dbName`)
3. **State tool friction** (destructive gating on memory-only writes, JSON-only values, strict provider naming)
4. **`exec_sql_query`** auto-detect broken with single-db apps
5. **Dio plugin** missing bodies/error messages/mock markers, small log cap, drifting tool description
6. **Plugin registration timing** — lazy init means tools say "not registered" until plugin first used
7. **Response size bloat** — `get_latest_crash_report` ~41KB, target <4KB
8. **Small bugs** (TextField disabled, empty device list, set_rotation lies, jump_to_screen lies, stale elements during transition, unverified swipe)
9. **Doc drift** — `TOOLS.md` hand-written vs `TOOLS.generated.md`, stale README counts
10. **Self-heal alarmist** — 38px overflow = "🚨 CRITICAL", 6 extension calls (incl. full widget tree) per error, no debouncing
11. **Keyboard simulator double-dispatch** + deprecated path + no text editing on desktop
12. **Text scale / locale wiring** — tools exist but init doesn't inject the `ValueListenableBuilder`
13. **Settle timing** — post-action state read ~150ms too early (~300ms route transitions show old screen)

### Key Code Locations
| Item | Files |
|------|-------|
| 1 (Perf tools) | `devtools_tools.dart`, `testing_tools.dart` (get_perf_metrics), `memory_auditor.dart`, `flutterpilot_sdk.dart` (_extractWidgetProps context) |
| 2 (Params) | Every `*_tools.dart` mixin, `widget_extensions.dart`, `navigation_extensions.dart`, `state_extensions.dart` |
| 3 (State tools) | `state_management_tools.dart` (set_riverpod_state lines 53-79), `flutterpilot_riverpod.dart` |
| 4 (SQL) | `state_management_tools.dart` exec_sql_query lines 346-391, drift/sqflite plugins |
| 5 (Dio) | `flutterpilot_dio.dart`, `state_management_tools.dart` get_network_logs lines 164-179 |
| 6 (Plugin init) | All 12 `packages/plugins/flutterpilot_*/lib/*.dart`, `flutterpilot_cli/lib/src/commands/init_command.dart` |
| 7 (Size) | `self_heal_manager.dart` (CrashReport.toMarkdown), `e2e_test.dart` |
| 8 (Bugs) | `flutterpilot_sdk.dart` _extractWidgetProps (line 652), `fleet_manager.dart`, `navigation_tools.dart` set_device_rotation/jump_to_screen, `flutterpilot_sdk.dart` getPostActionState line 326 |
| 9 (Docs) | `TOOLS.md`, `README.md`, `packages/flutterpilot_server/tool/generate_tools_doc.dart` |
| 10 (Self-heal) | `self_heal_manager.dart`, `flutterpilot_server.dart` line 448 (error→handleCrash), `error_inspector.dart` |
| 11 (Keyboard) | `keyboard_simulator.dart` _dispatch line 129-136 |
| 12 (Wiring) | `flutterpilot_sdk.dart` localeNotifier/textScaleNotifier lines 186-225, `init_command.dart` |
| 13 (Settle) | `flutterpilot_sdk.dart` getPostActionState, widget_extensions.dart tap/enterText post-delta capture |

---

## Files and Modules

### Server package (`packages/flutterpilot_server/lib/`)
- `flutterpilot_server.dart` — main class, event stream handler (line 448 handleCrash trigger)
- `src/tools/devtools_tools.dart` — get_gc_stats, audit_memory_health, enable_widget_rebuild_tracking
- `src/tools/testing_tools.dart` — get_perf_metrics, wait_for_condition
- `src/tools/navigation_tools.dart` — wait_for_widget, set_device_rotation, jump_to_screen
- `src/tools/state_management_tools.dart` — set_riverpod_state, exec_sql_query, query_drift, query_sqflite
- `src/tools/app_inspection_tools.dart` — list_connected_devices, connect_app flow
- `src/self_heal_manager.dart` — handleCrash, CrashReport, severity classification
- `src/fleet_manager.dart` — register/switch device, auto-discovered device tracking

### SDK package (`packages/flutterpilot_sdk/lib/`)
- `flutterpilot_sdk.dart` — _extractWidgetProps, getPostActionState, FPS counter, locale/textScale notifiers, registerServiceExtensions
- `src/keyboard_simulator.dart` — _dispatch double-dispatch
- `src/memory_auditor.dart` — audit() image-cache only
- `src/error_inspector.dart` — error capture, severity signals
- `src/extensions/widget_extensions.dart` — parameter aliasing (key/target), post-action state capture
- `src/extensions/navigation_extensions.dart` — route animation status

### Plugins (`packages/plugins/`)
- `flutterpilot_dio/lib/flutterpilot_dio.dart` — log bodies, mock markers, log cap, explicit register()
- `flutterpilot_riverpod/lib/flutterpilot_riverpod.dart` — loose name matching, candidate listing, plain values
- `flutterpilot_bloc`, `flutterpilot_sqflite`, `flutterpilot_drift` — explicit register() pattern
- All 12 plugins: add `static register()` method

### CLI package
- `flutterpilot_cli/lib/src/commands/init_command.dart` — ValueListenableBuilder injection, plugin register() line printing

### Docs
- `TOOLS.md` — delete or regenerate
- `README.md` — update category counts
- `TOOLS.generated.md` — regenerate via `dart run packages/flutterpilot_server/tool/generate_tools_doc.dart`

---

## Implementation Steps

### Phase A: Deletions & Honesty (Items 1, 9, 6+12 init wiring)
**Depends on**: nothing; independent

1. **Delete `get_perf_metrics` tool** from `testing_tools.dart`. In every place that references it (server README, TOOLS*.md, e2e), point to `profile_frame_budget` + `get_memory_details` instead.

2. **Delete `get_gc_stats`** from `devtools_tools.dart` (it re-reads heap via allocation profile without a real GC; get_memory_details already covers this).

3. **Decide & act on `audit_memory_health`**: Delete for now (only checks ImageCache and the "oversized decode width" check uses Image.width which is almost never set vs cacheWidth). Add a TODO to §5 (DevTools parity item 5 — memory leak check) for a real implementation. Remove from `devtools_tools.dart`, `flutterpilot_sdk.dart` exports, and docs.

4. **Decide & act on `enable_widget_rebuild_tracking`**: Delete the server tool for now (it turns on `ext.flutter.profileWidgetBuilds` but there's zero readout path). Mark as prerequisite for §5.3 (jank explanation). Remove from `devtools_tools.dart` and docs.

5. **Doc sweep**: Delete `TOOLS.md` (it drifts from `TOOLS.generated.md`). Update README §"MCP Tools Across 10 Categories" counts to match actual 136-tool list minus deletions above. Regenerate `TOOLS.generated.md`.

6. **Plugin `register()` + init printing**:
   - Add `static void register()` to every plugin that today lazily inits via constructor (all 12: riverpod, bloc, dio, drift, hive, sqflite, shared_preferences, supabase, gorouter, connectivity, firebase, secure_storage). Move the registerExtension/registerCapability calls from the constructor into `register()`. Constructor calls `register()` if not initialized for backward compatibility.
   - Update `init_command.dart` to print a `PluginName.register();` line per detected plugin, and print the `ValueListenableBuilder` wrapping snippet for `textScaleNotifier` + `localeNotifier` in main.dart.

### Phase B: Parameter Consistency (Item 2)
**Depends on**: Phase A (deleted tools don't need migration)

7. **Canonicalize to `target`**: Create helper `_normalizeTarget(params)` in server base that accepts:
   - `key`, `identifier`, `selector` → alias to `target`
   - `rootKey`, `rootSelector`, `root` → alias to `rootTarget`
   - `expect` (wait_for_state) → alias to `expected`
   - `dbName` (query_drift/list_drift_tables/list_sqflite_tables/query_sqflite) + `database` (exec_sql_query) → alias to `dbName`
   Apply at the server layer (`_withDeviceId` or a new `_normalizeParams`) so SDK-side also accepts the aliases it already does (widget_extensions.dart:1083 already does `key ?? target`). Keep old names accepted for at least one release via aliasing.

8. **Merge `wait_for_widget` into `wait_for_condition`**:
   - `wait_for_condition` already takes `selector` (semantic/key). Extend its schema to accept `key` and `text` aliases (mapped to `selector`). Add `timeoutMs` (already there).
   - Keep `wait_for_widget` as a deprecated alias server-side that calls the same callback. Log a one-time server-side warning pointing to `wait_for_condition`.

### Phase C: State Tooling & SQL (Items 3, 4)
**Depends on**: Phase B parameter helpers

9. **Relax `set_riverpod_state`**:
   - Remove `allowDestructive` check in server `state_management_tools.dart` lines 70-71 (it's memory-only). Keep destructive flag ONLY for storage/DB tools (shared_preferences write, secure_storage delete, sqflite/drift writes).
   - Accept plain Dart values for `value` (int/bool/String/num) in addition to JSON strings: on server side, if `value` is not already a string, pass through raw; on SDK/riverpod plugin side, attempt JSON.decode first then fall back to raw assignment.
   - Loose provider-name matching in `RiverpodPilotObserver` (state setter lookup). If exact name match fails, try: substring match, suffix match (e.g. `FeedNotifier` matches `NotifierProvider<FeedNotifier, Feed>`). On miss, return an error listing top-5 candidate names (by Levenshtein or substring) from `_providers.keys`.
   - Apply same candidate-listing fix to `wait_for_state` in `state_extensions.dart` (both riverpod + bloc paths).

10. **Fix `exec_sql_query` auto-detect**:
    - In `state_management_tools.dart` lines 360-391, first query both `list_sqflite_databases` and `list_drift_tables` (with dbName=null) extensions to enumerate registered DBs. If exactly one exists, use it (no dbName param). If multiple, return an error listing them. If none, return "Neither Sqflite nor Drift registered".
    - Also pass the resolved `dbName` through to drift extension (currently drift call passes only `sql`, missing `dbName`).

### Phase D: Dio Plugin & Response Size (Items 5, 7)
**Depends on**: Phase A

11. **Dio plugin upgrade**:
    - In `_onRequestAsync`: capture request body (truncate to 2KB, redact keys matching `_sensitiveKey` pattern), `Content-Type`.
    - In `onResponse`: capture response body (truncate to 4KB, redact), mark `mocked: true` if the response came from handler.resolve path.
    - In `onError`: capture full error message + type + response body if present.
    - Raise `maxLogEntries` from 100 to 500 with per-request grouping cap (same URL within 1s → single entry with count).
    - Fix server-side `get_network_logs` description to match payload: include that bodies are truncated+redacted, mocks are marked.

12. **Crash report size budget (<4KB) + size assertions**:
    - In `CrashReport.toMarkdown()`: Truncate each JSON section to 512 chars. Replace full widget tree with 1-level ancestor chain of the error-causing widget (from ErrorInspector's captured widget info if available). Remove "DIRECTIVE FOR AI" boilerplate. Omit riverpod/bloc data unless they contain the error substring.
    - Mark only `isUnstable = true` for actual uncaught exceptions (postpone severity to item 10).
    - Add e2e size assertions: `get_app_summary` < 2KB, `get_widget_tree` (e2e scaffold) < 8KB, `get_latest_crash_report` < 4KB, each action response < 2KB.

### Phase E: Self-Heal, Keyboard, Settle, Small Bugs (Items 8, 10, 11, 13)
**Depends on**: Phase D (partially independent, but share e2e gate)

13. **Self-heal severity + debounce + lazy diagnostics**:
    - Classify errors at capture time in `error_inspector.dart`:
      - `warning`: RenderFlex overflow, debugPrint'd asserts that don't throw
      - `error`: StateError, RangeError, FormatException, DioException.response (status >= 400), etc.
      - `critical`: Uncaught top_zone exceptions (FlutterError.onError non-overflow), Isolate errors
    - `flutterpilot_server.dart` line 448: only call `handleCrash` for `critical`. For `error`, just append to event buffer. For `warning`, event buffer only (no self-heal).
    - Debounce repeated identical errors (hash of exception string, 2s window).
    - Lazy diagnostics: `handleCrash` no longer does 6 parallel extension calls. Instead, it stores timestamp+exception. Full 6-call gather runs ONLY inside `get_latest_crash_report` callback, and cached for 5s.
    - No more "🚨 CRITICAL APP CRASH" for layout — "⚠️ Layout overflow detected" for warning level.

14. **Keyboard simulator fix**:
    - Delete the deprecated `keyMessageHandler` path in `KeyboardSimulator._dispatch` (line 133-135).
    - Use `KeyEventManager.handleKeyData` path (the platform key-data path matching flutter_test's KeyEventSimulator).
    - Document clearly: `press_key` dispatches raw key events for Shortcuts/Focus traversal. Text editing on desktop goes through the OS IME → use `enter_text` for typing characters/Backspace into fields. Add a server-side note when `press_key` is called with a character key on desktop suggesting `enter_text`.

15. **Settle timing & stale elements (Item 8 transition bug + Item 13)**:
    - In SDK, add a helper `_waitForRouteSettled()` that polls `NavigatorObserver` + `ModalRoute.animation?.status == AnimationStatus.completed` (or `dismissed` for pops) + no open popup routes. Timeout 1s.
    - Call this at the START of `getPostActionState()` before capturing interactive elements.
    - Also add to get_interactive_elements / get_widget_tree entry points (the extension wrapper via registerExtension already pumps frames; add route-settled wait there too).

16. **Small bug fixes**:
    - **TextField `isEnabled:false`**: In `_extractWidgetProps` (SDK line 652), BEFORE the onPressed/onTap/onChanged checks, for TextField/TextFormField/EditableText read `widget.enabled` (default true) AND `!widget.readOnly`; set `isEnabled` from that FIRST so later checks don't overwrite it to false.
    - **`list_connected_devices` empty for auto-discovered app**: When `connect_app` (or auto-discovery) succeeds without an explicit `register_device`, add a synthetic fleet entry `id: "default"` with the connected URI, marked active.
    - **`set_device_rotation` "success" on desktop**: Return honest "Not applicable on desktop; window size is controlled by the OS." Check `defaultTargetPlatform` via `get_capabilities` or pass platform info in connect.
    - **`jump_to_screen` "state injected"**: Only include "with state injected" in the response message if `state` was actually non-empty. Otherwise: "Teleported to route X directly."
    - **`swipe_widget` pull-to-refresh**: Add an e2e check that verifies swipe on a scrollable with enough distance triggers refresh indicator (if RefreshIndicator is in tree, simulate refresh callback fire).

### Phase F: Verification & Regeneration
**Depends on**: Phases A-E complete

17. Run `dart analyze` on all packages. Fix all new issues.
18. Run all package unit tests (`melos run test` or per-package `dart test`).
19. Run `e2e_test.dart` end-to-end (fresh app, init, drive via MCP). Fix regressions. Add new e2e checks per §300 of ROADMAP for user-visible items (especially 8, 10, 13).
20. Regenerate `TOOLS.generated.md`: `dart run packages/flutterpilot_server/tool/generate_tools_doc.dart`.

---

## Dependencies and Considerations

- **Backward compatibility**: Old parameter names (key, selector, dbName) must be accepted for at least one release; removing them silently breaks agents that already learned the current names.
- **Deletion rationale vs field-proof**: Per ROADMAP method, features that can't be made honest should be deleted rather than half-fixed. Items 1 perf tools are all "half" and cheaper to delete than to correctly implement right now.
- **Riverpod plugin state injection**: `container.read(provider.notifier).state = value` works only for Notifier/StateNotifier-style providers. Some providers (e.g. `Provider` without notifier) don't support injection — the honest error must say so with candidates, not a generic fail.
- **Self-heal severity**: Overflow detection in `UiHealthAuditor.audit` uses `RenderFlex.toString().contains('OVERFLOWING')` — these are NOT caught by FlutterError.onError the same way uncaught exceptions are. Need to ensure overflow events from ErrorInspector are tagged with `severity=warning` so handleCrash isn't triggered by the 38px Row overflow in hn_reader story_tile (ROADMAP §293 explicitly keeps that bug).
- **macOS-only field test so far**: Item 11 keyboard path changes must not regress iOS/Android physical-keyboard handling (even though untested). The `handleKeyData` path is the Flutter-recommended one and is cross-platform.
- **Settle wait timeouts**: Adding `_waitForRouteSettled()` adds ~0–300ms latency per action; this is acceptable per the performance budget (tap_widget target <200ms currently is 300–450ms so this is tradeoff of correctness vs speed — cap the wait at 300ms and document that animated transitions can show stale state if still running after 300ms).
- **e2e gate is macOS only today** (§128). All changes must pass on macOS; we do not gate on iOS/Android/web per §2 §2.

---

## Validation

1. **Static**: `cd packages/flutterpilot_sdk && dart analyze` (repeat for server, CLI, all 12 plugins). Zero errors, zero warnings above info.
2. **Unit tests**: Run `dart test` in:
   - `packages/flutterpilot_sdk/test/`
   - `packages/flutterpilot_server/test/`
   - `packages/flutterpilot_cli/test/`
   - Each plugin test folder. All tests pass.
3. **E2E gate**: `cd packages/flutterpilot_server && dart run tool/e2e_test.dart`. All 25+ checks pass. New e2e checks added for:
   - `get_latest_crash_report` size <4KB (provoke error then read)
   - `get_widget_properties` TextField with `enabled: true` → reports `isEnabled: true`
   - `exec_sql_query` with single DB, no `dbName` param → works
   - Post-navigate `get_interactive_elements` does not list old-route widgets
   - Deprecated `wait_for_widget` still works and returns hint to use `wait_for_condition`
   - `set_device_rotation` on desktop returns honest message
4. **Field smoke on hn_reader** (per §29-41 method):
   - `cd packages/flutterpilot_server && dart run tool/fp_bridge.dart -p ../../../hn_reader`
   - `get_app_summary` <2KB JSON, app window visible
   - `tap_widget` on story tile → route transition settled; tappable list shows detail screen
   - Intentionally provoke Dio 404 → get_network_logs shows error message + body, not marked mocked
   - Provoke mock via `mock_http_response` → same request in log shows `mocked: true`
   - Trigger 1.6× text scale (keep the known overflow bug) → self-heal does NOT fire "CRITICAL" and `isUnstable` stays false
   - Provoke uncaught StateError (delete a provider read) → self-heal fires, `get_latest_crash_report` <4KB, not 41KB
5. **Tool doc generation**: `dart run packages/flutterpilot_server/tool/generate_tools_doc.dart` succeeds; diff shows only expected deletions (get_perf_metrics, get_gc_stats, audit_memory_health, enable_widget_rebuild_tracking) and parameter alias notes.
6. **Response-size regression check**: Run `tool/.fp/calls.jsonl` latency/size on hn_reader top-5 tools (summary, tree, tap_widget, get_errors, crash_report) — none larger than budgets.

---

## Risks

| Risk | Impact | Handling |
|------|--------|----------|
| Deleting 4 perf tools breaks agent scripts that already call them | Medium (agents regenerate, but human devs may have scripts) | Keep server-side stubs returning a clear error pointing to `profile_frame_budget` / `get_memory_details` for 1 release cycle; don't silently return empty data |
| Parameter aliasing layer introduces subtle bugs (wrong param passed to extension) | High | Add unit tests in `flutterpilot_server/test/` for `_normalizeParams`: old names `key`/`selector`/`dbName`/`database` all map correctly; SDK-side already accepts `key ?? target` (verified at widget_extensions.dart:1083) |
| Self-heal lazy-diagnostics: report is empty or stale if extensions changed between error and read | Low-Med | Cache extension data on first `get_latest_crash_report` after error with 5s TTL; on cache miss, do synchronous gather. Timestamp the report with both error time and gather time |
| Route settle wait blocks forever if an animation never completes | Medium | Hard cap 300ms (≈ one material page transition) with a fallback note that state may be stale; never infinite-wait |
| Riverpod loose name matching accidentally sets wrong provider | High | Require at least 60% similarity (Levenshtein) AND match on class-name tokens; if ambiguous, return error listing candidates instead of auto-picking. Keep exact match as first path |
| Dio body capture grows response / memory budget | Medium | Hard truncate per body (2KB request / 4KB response); sensitive key regex redaction; 500-entry cap with LRU RingBuffer (already RingBuffer so bounded) |
| Adding default device to fleet_manager breaks switch_device / multi-device semantics | Low | Treat `id: "default"` as special; if user runs `register_device(id)` explicitly, remove "default" and make the explicit one active |
| e2e test on macOS CI can't open app windows (headless) | Low | Current e2e works on macOS runner per §16; leave GitHub Actions CI setup to §2.6 (separate roadmap item); validate locally only for this plan |
