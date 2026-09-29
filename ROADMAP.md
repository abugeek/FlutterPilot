# FlutterPilot Roadmap

Handoff document for the next agent (or human). Read this, then `CLAUDE.md`.

**North star:** a *useful, working* tool, not a feature-rich one. Every tool must
be proven on a real app before it ships, return honest results (never "success"
when nothing happened), and cost the agent as few tokens as possible. Fewer
tools that always work beat many tools that sometimes work.

---

## 0. State as of 2026-09-28

- 65 MCP tools (164 → 129 → 62, §4.2; +inspect_widget, profile_action, §5.1–5.2; +generate_test, §6; +scenario, §7; +verify_feature, §8); an app sees only those that work for it
  (a Dio-only app 42, zero-code 16). SDK + 12 plugins + server + CLI. All packages
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
  secure_storage, supabase in `../notes_app`; firebase (Auth + Firestore,
  emulators) in `../firebase_app`; plain hive in `../hive_app`.

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
  entitlement files or all HTTP fails with `errno = 1`. `flutterpilot init`
  adds it; `flutterpilot doctor` checks it.
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

10. **Self-heal is alarmist and heavy:** done. Layout overflows are
    warnings (SDK `severity`), not uncaught exceptions: no flag, no
    notification. An uncaught exception notifies the client once per distinct
    exception until the next hot reload (MCP log level `error`, no
    "CRITICAL"). `get_errors(report: true)` is built on demand from 5 calls
    (no widget tree): exception, the app's frames only (FlutterPilot and
    `dart:` frames are counted, not shown), route, clipped state, last 6
    requests — 3.5 KB → 0.4 KB in the e2e fixture. Layout errors name the
    culprit as `Row (lib/main.dart:81:44)`. Proven by the fixture's Crash and
    Squeeze buttons (e2e). Round 12 of `docs/field-test-findings.md`.
11. **Keyboard simulator:** done. It already used one path
    (`KeyEventManager.handleKeyData`, synthesized); the e2e fixture now
    counts key-downs per key to keep it that way. What didn't work: editing
    keys in a text field on macOS/iOS reported success and changed nothing
    (editing comes from the OS input client). If the key event leaves the
    focused field unchanged, the SDK applies the edit a key press makes
    (character, Backspace/Delete, arrows, Home/End, select-all) as user input
    — on Android/Linux/Windows Flutter's own shortcuts already do, and
    nothing is applied twice (widget tests on all six platforms). `press_key`
    reports the field's text and cursor. `enter_text` left the whole text
    selected on desktop (focus selects all); the cursor now ends up at the
    end. Round 13 of `docs/field-test-findings.md`.
12. **Text scale / locale overrides:** done, with no wiring at all instead
    of `init` wrapping MaterialApp (which missed apps whose MaterialApp is
    not in main.dart, has its own `builder:`/`locale:`, or is Cupertino).
    The locale goes to the app as a device locale change
    (`dispatchLocalesChanged`) and resolves through its `supportedLocales`;
    the text scale is put into the root MediaQuery (the one `View` builds
    from the device), rebuilt first and patched before anything below builds
    when a device change (keyboard, rotation, resize) refreshes it, and
    re-patched after hot reload. The response says what the app shows: an
    unsupported locale or an app that pins `locale:` or clamps text scaling
    is reported ("had no effect" / "partly applied"), not faked. `init` no
    longer rewrites MaterialApp; the notifiers are deprecated and old wiring
    keeps working. Round 14 of `docs/field-test-findings.md`.
13. **Settle timing:** done. Measured on a scratch go_router app and
    hn_reader: page, dialog, sheet and popup transitions were already
    waited out, but long-press, double-tap, fill_form(submitWith), swipe,
    drag, toggle and x/y taps weren't; drawers and tab switches (no route)
    answered mid-slide; navigation 250 ms after a tap read as "nothing
    changed"; tools failed as "not registered" right after a hot restart.
    Every mutating tool now reads the screen once routes are still and the
    on-screen text holds still between frames (text that keeps moving past
    600 ms is a loop — marquee, pulsing badge — and is ignored, and
    remembered); an action that changed nothing is watched 0.5 s more and
    says so; a progress indicator on screen is reported ("may still be
    loading"). Hot restart answers once the new isolate drew its first frame
    and registered FlutterPilot. Round 15 of `docs/field-test-findings.md`.

## 2. Coverage the product claims but hasn't proven

1. **Second real app for untested plugins:** done for Bloc, Drift, Hive CE,
   secure_storage and Supabase — `../notes_app` (own git repo; local Supabase
   via `supabase start`, ports 553xx, test account in
   `supabase/seed_accounts.md`). 22 findings, all fixed: see
   `docs/field-test-findings.md` round 4. **Firebase:** the old plugin
   (Crashlytics/Analytics/Performance/FCM — no emulator for any; it only
   saw events the agent itself sent) was replaced by Auth + Firestore
   (`get_firebase_auth`, `query_firestore`), field-tested in
   `../firebase_app` against the local emulators (`firebase emulators:start
   --only auth,firestore --project demo-flutterpilot`, needs Java). Plain
   `hive` 2.2.3 checked in `../hive_app`. Findings: round 9. §2.1 is done.
2. **Mobile + web:** e2e done — identical results on macOS, iOS simulator,
   Android emulator and Chrome (tap, text, keys, secondary tap, pinch,
   rotation, chains, hot reload + restart; web via DWDS). The `native_*`
   tools are listed only when the app runs on iOS and `idb`/`xcrun` exist
   (`tools/list_changed`). Native tools field-tested on the iOS simulator
   with idb (`../native_app`: location permission alert, text input,
   backgrounding; round 8 of `docs/field-test-findings.md`), e2e checks
   them when idb is present. Left: a real app on a physical phone
   (`../native_app` is ready; needs Xcode signed in to an Apple ID).
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

1. **No `-p` needed:** done for clients that share workspace folders. Without
   `-p` the server asks the client for its roots (`roots/list`, again on
   `roots/list_changed`) and looks for `.dart_tool/flutterpilot_vm_uri` in the
   working directory and each root, 3 levels deep (monorepos; skips build,
   hidden, `node_modules`, a project's platform folders); several live apps →
   the most recently launched. Removed what never worked: probing fixed ports
   (8080 etc. — any web server passed for a VM service) and reading temp/json
   files nothing writes. "No app" errors say how to make the app findable.
   e2e: a server started in an empty folder finds the app only through roots.
   A plain `flutter run` / IDE launch writes no URI file: found through the
   Dart Tooling Daemon since §8's interop (below).
2. **`flutterpilot mcp install`:** done. In the app folder it compiles the
   server (next to the CLI: a checkout or the `pub global activate` clone;
   `--local`, `--no-compile` for `dart run`) and adds `flutterpilot` to
   `.mcp.json` (Claude Code), `.cursor/mcp.json`, `.vscode/mcp.json`
   (`${workspaceFolder}`) — the clients the project uses, or `--client`.
   Other servers and keys are kept; a JSONC file is left alone with the
   entry printed; reinstalling is a no-op. Prints the user-scope
   `claude mcp add` line (no `-p`: Claude Code starts servers in the project).
   `init` ends with it, `dev` suggests it when no config has FlutterPilot.
   e2e starts the server exactly as `.mcp.json` says and drives the app.
   Not yet verified inside Cursor / VS Code themselves.
3. **Publish to pub.dev:** ready; the upload itself is the owner's step
   (see `RELEASING.md`). All 15 packages pass `pub publish --dry-run` with
   0 warnings (`tool/publish_check.dart`, publish order; the plugins get a
   temporary override to the checkout's SDK until pub.dev has it). Every
   package has a README, LICENSE and CHANGELOG, and the plugin READMEs were
   rewritten from one table (host package, wiring line, tools). `init
   --source auto` (the default) uses `^0.1.0` from pub.dev once
   `flutterpilot_sdk` is there, with no dependency_overrides (it drops the
   one a git init left), and git until then. A CLI installed from pub.dev
   has no server beside it: `mcp install` builds one from
   `~/.flutterpilot/server`, a package depending on `flutterpilot_server`
   whose bin calls `runFlutterPilotServer` (the server's CLI now lives in
   its library). All 15 names were free on pub.dev on 2026-09-28.
4. **`flutterpilot doctor`:** done. From the files: SDK added and
   `FlutterPilot.initialize()` called; for each package with a plugin, the
   plugin added and wired (its `…Pilot…` symbol used in lib/); macOS
   `network.client` (❌ for apps with a networking package, else ⚠️); an MCP
   config whose server exists. From the running app (the URI file, over the
   VM service): SDK registered, each plugin's extension registered (else
   the wiring line + "hot restart"); zero-code apps are fine as such. Each
   problem prints the exact fix; exit 1 on problems. Tried on hn_reader
   (running: all ✅), notes_app, firebase_app/hive_app/plain_app (missing
   network.client). e2e runs it against the fixture (SDK + Dio registered,
   MCP config) and a zero-code app. `init` adds the entitlement to both
   macOS entitlement files when the project has a macOS runner (an existing
   key, even `false`, is left alone); none → nothing to do.

## 4. Token efficiency (agents pay for every tool and every byte)

1. **Expose only relevant tools:** done — a plugin's tools are listed once
   the app registers that plugin's extensions (`pluginToolExtensions` in
   `src/plugin_tools.dart`, 35 tools), per device, recomputed when extensions
   are added (debounced: one `tools/list_changed`). on macOS every app got
   119 tools / 68 KB of definitions; now hn_reader (6 plugins) 104 / 57 KB,
   a Hive-only app 86 / 45 KB, the e2e fixture (Dio) 88.
   Native tools only on iOS; zero-code apps 29. Round 10 of
   `docs/field-test-findings.md`.
2. **Shrink further:** done — 125 → 62 tools (58 → 34 KB of definitions with
   every plugin; the e2e fixture 88 → 42 tools, hn_reader 104 → 48).
   Families became one tool with a parameter: `tap_widget` (`gesture`
   double/long/secondary, `waitFor`), `wait_for` (key/route/animations/state/
   frames), `navigate_to` (deep links, go_router push/replace),
   `get_navigation_stack` (go_router routes/history), `set_app_settings`
   (theme, locale, textScale, orientation, debug overlays), `assert_widget`,
   `get_state` / `set_state` (Riverpod + Bloc), `hot_reload` (`restart`),
   `get_errors` (`report`), `compare_screenshot` (`save`), `get_widget_tree`
   (`diff`), and `clear`/`delete` flags on the log, profile, mock and storage
   tools. Deleted: `read_dart_file` / `list_dart_files` / `get_build_config`,
   `start_recording` / `stop_and_generate_test` (recorded only the agent's
   own actions), `get_stream_logs` (nothing fed it), `get_recent_events`,
   the sqflite/drift table listers (`exec_sql_query` on sqlite_master).
   `tool_registration_test` fails above 80. Round 11 of
   `docs/field-test-findings.md`.
3. **Tool descriptions:** done — every description says what the tool
   returns and when to use it (or what to use instead); no "CALL THIS",
   "PREREQUISITES", speed claims or emoji, no "needs the X plugin" (plugin
   tools are only listed when the plugin is there), no implementation
   details (idb commands, pointer maths). `tool_registration_test` rejects
   selling phrases and descriptions over 600 chars. Responses lost their
   emoji banners too (audit, action chain, compare, connect).

## 5. DevTools parity — what developers actually open DevTools for

Highest value first. Each should answer a *why*, not just dump data.

1. ~~**"What code draws this?"**~~ — done (2026-09-28): `inspect_widget(key |
   x,y)` returns the creation location (file:line:col) of the widget or, for
   a framework widget, of the app widget that builds it, plus up to 8 app
   ancestors with their locations. Debug builds only (says so otherwise);
   SDK only (zero-code's `get_widget_tree` already carries `loc`). Findings
   #207–209, e2e check "inspect_widget names the source line".
2. ~~**CPU profile around an action**~~ — done (2026-09-28):
   `profile_action(tool, arguments, durationMs)` runs an action tool while
   sampling the UI isolate (250 µs), then returns app functions by
   self/total ms with file:line and the hottest framework functions with
   the app caller. Samples FlutterPilot itself caused (reading the screen
   after the action) are left out. Paths map to packages through the
   app's `package_config.json` (the VM reports path deps as file paths).
   Findings #210–213, e2e checks "profile_action …".
3. ~~**Jank explanation**~~ — done (2026-09-28), in `profile_action` (no new
   tool): the VM timeline of the same window gives each frame's UI time
   (build/layout/paint/compositing/post-frame), its raster time, and the
   app widgets that rebuilt (`ext.flutter.profileUserWidgetBuilds`, self
   time per type); frames over the display's budget are explained, the
   rest summarised. The AI tap overlay is switched off while profiling
   (it animates every frame). Findings #214–217.
4. ~~**Layout explorer**~~ — done (2026-09-28), as `inspect_widget(...,
   layout: true)` (no new tool): constraints and size of each render box
   from the widget up (identical wrappers folded), flex fit, and issues
   explained — a Row/Column overflow by how much and which children fill
   it (named as the app wrote them: `Text lib/…:32 (RichText)`), a 0-wide
   box and which ancestor gave it max 0. Works without source locations
   (profile builds). Findings #218–220.
5. ~~**Memory leak check**~~ — done (2026-09-29), as `get_memory_details(cycle,
   times)` (no new tool): one warm-up, then GC'd allocation profiles after
   each round; classes that gain instances every round (framework ones
   only when steady and in a library — the debug JIT's Code/ICData grow
   unevenly), confirmed by a last round whose new instances must survive
   GC, with the retaining path of such an instance and who holds it (app,
   framework only, or FlutterPilot itself). leak_tracker not needed.
   Findings #221–224.
6. ~~**Network detail**~~ — done (2026-09-29): `get_http_profile` numbers
   requests (`#23`, position since the last clear), filters by `url`, and
   `id: 23` returns one in full via `getHttpProfileRequest`: connection
   timeline, redirects, error, request/response headers and bodies (JSON
   compact, capped at 3000 chars, binary as a size). Credential headers and
   secret-looking JSON/form fields are masked. The listed duration was the
   time to *send* the request; it now runs to the end of the response.
   Findings #225–227.
7. ~~**Accessibility audit**~~ — done (2026-09-29), in `audit_screen_health`
   (no new tool): from the semantics tree, tappable nodes with no
   label/tooltip (grouped per source, attributed to the widget that adds
   the tap action, with a hint when it covers a labeled control with the
   same box); WCAG contrast of every on-screen text from the rendered
   pixels (text color from its style when opaque; 4.5:1, large 3:1); the
   screen reader order of the controls and where it jumps back up.
   Findings #228–231.
8. ~~**Native crash reason**~~ — done (2026-09-29), with no new tool: when
   the connection drops, the next tool's error says whether the app
   crashed and why. Apple (macOS apps, iOS simulator apps): the kernel logs
   a crash at once (`name[pid] Corpse allowed`; a normal exit has none),
   the uncaught NSException message comes from the app's log (`log show`,
   in the simulator via `simctl spawn`), and ~20 s later the `.ips` report
   in `~/Library/Logs/DiagnosticReports` adds the kind, the frames where it
   was thrown (system frames on top skipped) and the report path. Android:
   `adb logcat -b crash` (Kotlin/Java `FATAL EXCEPTION` or a native signal
   with its abort message), unit-tested only (no emulator here). Not
   covered: a physical iPhone (reports stay on the phone; `devicectl`), and
   an app that dies before FlutterPilot connected (no pid to match).
   Findings #232–235.

## 6. ~~Test generation done right~~ — done (2026-09-29)

`generate_test` (one tool): `start: true` hot-restarts the app and records
from there, as the test starts from `main()`. The SDK records each action at
the point it resolves its widget, with a `flutter_test` finder for that
widget alone on screen (key, also on an ancestor drawn in the same box →
unique text → tooltip → type with text → the same inside the nearest
uniquely keyed ancestor → by type and position, flagged as fragile); a tap
that had to scroll records `scrollUntilVisible` on the same Scrollable;
coordinate taps become taps on the control drawn there. Assertions
(`assert_widget`, `wait_for`) become waits and expects; mocked responses
become `DioPilotInterceptor.mock` calls (new public API) in order;
obscured text becomes `--dart-define` values, never written.
`name: "x"` writes `integration_test/x_test.dart`, formats it, adds
`integration_test` to dev_dependencies if missing, **runs it** on the same
device (`flutter test -d`) and reports passed, or the step it failed at with
the framework's message. Not replayed (listed in the response):
`navigate_to`, `set_slider_value`, keys without a test equivalent. Not
recorded: taps by the user's own hand. Findings #236–239.

## 7. ~~State time travel done right~~ — done (2026-09-29), as scenarios

The "simpler and more honest" version: `scenario` (one tool).
`save: "name"` writes `flutterpilot/scenarios/<name>.json` in the app — the
route (go_router location, else the top route), all SharedPreferences except
sensitive keys, the active Dio mocks (new `ext.flutterpilot.getHttpMocks`),
and the Riverpod/Bloc values `set_state` can put back (bool/number/String;
plugins report values as `toString()`, so enums, lists and classes are
listed as not saved). `load: "name"` replaces the preferences (needs
`--allow-destructive`), leaves the mocks for after the restart in a file in
the app's temp folder (`FlutterPilot.takeRestartData`; the Dio plugin applies
them in `register()`, before the first request), hot-restarts, goes to the
route and sets the state. No argument lists them. Not a snapshot of
everything: provider values are set behind the widgets (a TextField keeps its
own text), and databases, secure storage and files are not captured.
Findings #240–243.

## 8. Longer-term vision

- ~~**Verify-a-feature macro**~~ — done (2026-09-29): `verify_feature`.
  The agent gives the criteria (optionally a scenario to start from), picks
  each criterion in turn, drives and checks as usual; every action and check
  is recorded against the current criterion, and closing one adds the HTTP
  requests made meanwhile (dart:io profile), the app's new errors and a
  screenshot. A pass needs a passing check, no failed check and no error
  (overflows are warnings); driven but unchecked is NOT VERIFIED — the
  agent's say-so is not evidence. `finish` writes
  `flutterpilot/reports/<feature>-<time>/report.md` in the app. Findings
  #244–247.
- ~~**Interop with the official Dart & Flutter MCP server**~~ — done
  (2026-09-29). Checked against `dart mcp-server` 1.1.2 (Dart 3.13). Its
  default tools overlap ours on hot reload/restart, runtime errors, the
  widget inspector and Flutter Driver; `run_tests`, `dart_format`/`dart_fix`
  and `launch_app` are off by default (its choice, kept). `flutterpilot mcp
  install` adds it as `dart` with `--disable flutter,dart_tooling_daemon`:
  the agent gets its analyzer, `lsp` and pub, and our running-app tools, one
  of each. A Dart MCP server already configured is kept, with that advice.
  The DTD, shared: `flutter run`, the IDEs and Dart's `launch_app` register
  apps with a tooling daemon, so the server (and `doctor`) find apps through
  `dart tooling-daemon --list` and `ConnectedApp.getVmServices` besides the
  URI file — a plain `flutter run` works now. Daemons whose workspace is a
  root, in one (3 levels) or above one (an IDE workspace: the package name
  must match); the newest launch wins across both. e2e: with the URI file
  hidden, a fresh server and doctor find the app; the installed Dart server
  lists `analyze_files` and none of the running-app tools. Not covered: a
  daemon's workspace far above the project without a pubspec name to match;
  web apps through DTD. Findings #257–259.
- ~~**Profile-mode support**~~ — done (2026-09-29). The server reads the
  build mode from the VM (`precompiled_mode`) on connect; the summary says
  "Build: profile", `profile_action` / `profile_frame_budget` say which
  build their numbers come from, and `hot_reload`, `generate_test` and
  `scenario` are not listed for profile builds (hot_reload explains why if
  called). SDK: source locations require a debug build (profile builds
  report creation tracking on but record no locations or `debugCreator`),
  and hit testing falls back to the element tree, so `inspect_widget(x, y,
  layout: true)` and coordinate taps in recordings work in profile. On
  hn_reader the same feed switch: debug 219 ms Dart, 2 janky frames, widget
  builds 12.7 ms; profile 87 ms, none, 1.0 ms. Not covered: zero-code apps
  in profile (the inspector extensions they rely on are debug-only), e2e in
  profile. Findings #248–251.
- **Parallel devices:** run the same flow on iOS + Android + web and diff
  results.
- ~~**Security review**~~ — done (2026-09-29): `docs/security-review.md`.
  Fixed: obscured field text in widget properties/tree, credentials in
  logs/errors/URLs/state (one redactor, SDK and server), `exec_sql_query`
  write bypasses (`WITH … DELETE`, writing PRAGMAs), the shell bridge
  answering browsers, generate_test secrets on the command line. Remote
  connections, destructive gating, secure storage and process launches
  reviewed OK. An e2e sweep plants secrets in the fixture and checks every
  read tool. Findings #252–256.
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
- **`stream_inspector.dart`** — nothing wires it; its tool is gone (§4.2),
  the SDK code can go too.
- **`flight_recorder.dart`**, `get_flight_log` — useful only if §6 is built
  on top. (The recording tools were deleted in §4.2.)
- **`native_automation_tools.dart`** (`native_tap` etc., needs `idb`, iOS
  simulator only) — test on a simulator or hide on other platforms.
- **Plugin write tools** that make real network calls (`supabase_session`,
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
