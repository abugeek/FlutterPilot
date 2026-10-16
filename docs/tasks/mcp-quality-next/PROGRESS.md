# MCP quality next — implementation progress

Durable progress record for the eleven task plans in this folder.

Scope of the effort (agreed with the requester): implement every task's
non-gated work — production code, regression tests, honest validation, and a
durable record — in the order **00 → 01 → 02 → 03 → 09 → 10 → 04 → 05 → 06 →
07 → 08**. Do not commit, push, open PRs, publish packages, or touch external
systems. Preserve the pre-existing changes in `docs/tasks/README.md` and the
untracked `docs/tasks/mcp-quality-next/` folder.

Labels used below:

- **Run** — actually executed on this workstation and observed this session.
- **Not run** — a required action that was deliberately not performed here
  (missing platform, separate approval, missing credentials).
- **Historical** — evidence quoted from the planning documents, not re-verified
  this session.

Measurements distinguish the units required by task 00 (characters, UTF-8
bytes, full-wire bytes, estimated tokens, billed usage). Apples-to-apples
comparisons keep the same fixture and the same unit.

---

## Environment (recorded this session)

- Working tree: `D:\projects\flutter\FlutterPilot`, branch `mcp-quality-next`
  (branched from `main`; **no commits made**).
- Dart 3.13.4, Flutter 3.47.5, Node v24.18.0, npm 11.16.0, 16 CPUs, Windows.
- Sibling fixture apps: `D:\projects\flutter\{fp_lab_shop,fp_lab_notes,
  fp_lab_plain,pos_lab}`. Revisions recorded in the fixture manifest.
- Tool count is **63** (the `CLAUDE.md` "67" is stale).
- Linux CI evidence and real-device e2e are **not run** here (Windows
  workstation only); they are reported as untested, never as passed.

---

## 00 — Reproducible evidence and honest validation gates

Status: **done** (non-gated scope). Gated items listed at the end.

### Delivered

- **Portable fail-closed test runner** — `tool/package_test_runner.dart`
  (library + `main`). Selects Dart vs Flutter per package from package
  metadata exactly once, discovers test-bearing packages deterministically,
  skips only a genuinely missing/empty `test/` directory and reports why.
  Uses argument-vector subprocesses with explicit working directories; a
  missing executable or an un-bootstrapped package is a hard error
  (fail-closed); propagates nonzero exits and never falls back from a failed
  Flutter run to Dart. Windows `.bat` launchers handled deliberately. The exit
  code is set explicitly (the Dart VM ignores `main`'s return value). Output is
  streamed with `stdout.listen(..., stdout.add)`.
- **Runner regression tests** — `packages/fp_server/test/package_test_runner_test.dart`
  (16 tests) cover passing, failing, no-test-directory, nonexistent-executable,
  and space-in-path disposable packages, plus an injected argv prefix for real
  subprocess runs. A deliberately failing package makes the aggregate exit
  nonzero.
- **Melos integration** — `melos.yaml` test script is now
  `dart tool/package_test_runner.dart`; `.github/workflows/unit.yml` and
  `ci.yml` call `melos run test`, so the repaired gate flows into CI.
- **Measurement split** — `lib/src/tool_list_bytes.dart` keeps the legacy
  character measure (`toolListChars` / `toolListTotalChars`) and adds
  `toolListUtf8Bytes` and `toolListWireBytes`. `lib/src/tool_list_report.dart`
  exposes `chars`, `utf8Bytes`, `wireBytes`; `tool/tool_list_report.dart`
  prints/JSON-emits all units. The legacy size metric is preserved under an
  explicit name so an encoding correction is never misreported as growth.
  Existing budgets keep the legacy character numbers (no relaxation).
- **Fixture manifest + read-only preflight** —
  `tool/eval/fixtures/manifest.json` records app ID, source location, exact git
  revision, license, required plugins, build mode, supported devices, scenario
  checksums, and expected capabilities. `tool/eval/src/fixtures.dart` provides
  `preflightFixtures` + `scenarioChecksumsOf`; `tool/eval/check_fixtures.dart`
  is a standalone read-only CLI. Issue levels are `blocking` (missing
  root/dir, revision mismatch, scenario hash mismatch/missing, non-package) vs
  `warning` (dirty checkout, non-git); `--require-clean` promotes dirty to
  blocking. Wired into `run_evals.dart` via `--fixtures`.
- **Fixture manifest tests** — `test/fixture_manifest_test.dart` (11 tests).
- **Eval README** — `tool/eval/README.md` documents the preflight, the units,
  and the exact prerequisites/limitations.
- `crypto: ^3.0.6` added to `packages/fp_server` dev_dependencies (already
  transitive) for the scenario sha256.

### Validation run this session

- `dart run test/package_test_runner_test.dart` → **16 passed** (in-process
  fakes + real subprocess with injected argv prefix).
- Runner end-to-end on real packages:
  `dart run tool/package_test_runner.dart --only fp_cli,fp_shared_preferences,fp_bloc`
  → **3 passed, 0 failed, 0 errored, 0 skipped**.
- `dart run packages/fp_server/tool/eval/check_fixtures.dart` against the real
  sibling labs → all recorded revisions and scenario hashes match.
- `dart analyze` in `packages/fp_server` → clean.
- Full `packages/fp_server` suite → see the "Full-suite status" section.
- `dart format` applied to every touched Dart file.

### Not run / gated

- Linux CI run of the repaired aggregate gate — **not run** here (Windows
  only). The workflows now call the runner; a Linux job is out of scope on
  this workstation.
- `--require-clean` fixture promotion — **not run** as a gate; the labs are
  dirty checkouts, so a baseline run must be marked non-baseline.
- Paid evaluation baseline — **not run** (needs explicit spend approval).
- No product tool names, schemas, or runtime semantics changed by task 00.

---

## 01 — Truthful effects and retry safety

Status: **done** (non-gated scope).

### Delivered

- **Effect/retry policy module** — `packages/fp_server/lib/src/effect_policy.dart`.
  An `ExtensionPolicy` records two independent facts per service-extension
  call: `mutating` (serialize behind other mutations, keep off the read path)
  and `replaySafe` (may be sent again after a lost response). The inventory is
  a reviewed list — `readOnlyExtensions`, `mutatingExtensions`,
  `diagnosticClearExtensions` — plus argument-aware overrides. Anything not
  listed is `known: false` and treated conservatively: serialized and **never
  replayed**.
- **Argument-aware replay** — `getStateHistory` is a replay-safe read, but
  `getStateHistory(clear: 'true')` is a non-replayable diagnostic clear. The
  decision lives in one function, `extensionPolicyOf(extension, parameters)`.
- **Single replay site** — `runWithReplay` in the same module replaces the old
  `_isReadOnlyExtension` prefix heuristic. `fp_server.dart` now:
  - classifies scheduling with `extensionPolicyOf(...).mutating`,
  - replays a dropped-response call only when the policy is replay-safe and the
    reconnect succeeded, and otherwise returns the honest
    "may or may not have run" uncertainty,
  - uses the same policy for the read-vs-action timeout.
  `_isReadOnlyExtension` is deleted.
- **`audit_screen_health` is no longer advertised read-only** — `ToolEffect.acts`.
  The current-screen call still observes internally (the extension stays in the
  read set for scheduling/replay); only the route sweep acts. Its description
  now discloses the sweep and the best-effort return.
- **Clear-capable tools advertise the strongest effect** — `get_state`,
  `get_debug_logs`, `get_http_profile` are `acts` (they can clear
  FlutterPilot's own capture). The non-clearing call is still a read for the
  scheduler and for replay, via the policy.
- **Open-world boundary documented and widened** — `openWorldTools` now covers
  everything that drives the app or runs its own code (a tap can reach the
  network), not merely the three external-service tools. The trust boundary is
  the app's reach, not the server's local VM.
- **Effects reviewed** against every registered tool: annihilation tools
  (`scenario`), screenshot save, memory cycles, custom code, mocks and
  composites were checked; the destructive set and `idempotentTools` were
  re-read and left as they are.

### Task-00 correction found here

Regenerating `TOOLS.generated.md` exposed a task-00 bug: the shared
`toolModelProjection` only stripped `annotations`, but the running server's
`tools/list` also sends an `execution` key that the in-process `Tool.toJson()`
does not — so the generator counted 43,221 while the freshness test rendered
40,701 for the same 63 tools. `toolModelProjection` now returns exactly
`{name, description, inputSchema}` (the model-facing projection its docstring
always described). The generator and the test agree again.

### Validation run this session

- `dart analyze` in `packages/fp_server` → clean.
- `test/effect_policy_test.dart` (12 tests) → passed: unknown extension never
  replayed; action executes exactly once with an execution counter; diagnostic
  clear never replayed; `get_state` read vs clear; replay-safe read sent twice;
  reconnect-failure reported as uncertain; **coverage**: every `ext.…` name in
  `lib/` is in the reviewed inventory.
- `test/tool_registration_test.dart` → passed, including the new assertion that
  `audit_screen_health`, `get_state`, `get_debug_logs` and `get_http_profile`
  are `acts`.
- `test/tools_doc_generated_test.dart`, `test/tool_list_report_test.dart` →
  passed; `TOOLS.generated.md` regenerated and now consistent with the test.
- Full `packages/fp_server` suite → see "Full-suite status".

### Not run / limited

- A live lost-response/reconnect against a real app: not run here (no app).
  The exact-once behaviour is proven at the policy level with an execution
  counter; device e2e for the changed runtime is **not run** on this
  workstation.
- Pinned non-active-device retry (task step 10) is preserved by the existing
  generation/context pinning (`_callExtensionScheduled` re-checks
  `connectionGeneration`); no new test added beyond the policy tests.


## 02 — Nested argument contracts and all-step preflight

Status: **done** (non-gated scope). Handoff matrix at the end of this section.

### Delivered

- **One shared nested-call validator** — `lib/src/action_chain.dart` gained
  `preflightStep(tool, arguments, {...})` (one nested call) and
  `listedTools(allowedTools, isAvailable)` (the "Tools: …" line), and
  `preflightChain(...)` now runs every step through `preflightStep`. Both apply,
  in order: documented retired-name translation, the composite's allowed tool
  family, availability, the profile/capability refusal, then the tool's own
  argument gate (`_toolArgGates`, the exact check a direct `tools/call` uses).
  `preflightChain` gained `field` (default `'steps'`; the leak check passes
  `'cycle'`) and `emptyProblem`, so each composite's refusal reads in its own
  vocabulary.
- **Compact shared step envelope** — `compositeStepSchema()`:
  `{"tool": <string>, "arguments": <object>}`, `required: ["tool"]`. Used as
  the `items` of `execute_action_chain.steps`, `run_on_devices.steps`, and
  `get_memory_details.cycle`. The envelope lets the existing coercion bring a
  stringified nested `arguments` object to a map and enforces `tool`, without
  copying any tool's schema into the composite (no union schema). Each tool's
  own constraints stay authoritative in its registered schema.
- **Preflight runs first on every composite** — `execute_action_chain`
  (`ui_automation_tools.dart`), `run_on_devices` (`app_inspection_tools.dart`),
  `_leakCheck`/`profile_action` (`devtools_tools.dart`). On
  `get_memory_details(cycle:)` and `profile_action` it now runs *before* the
  web/`_deviceContextForParameters` check, so an invalid plan is refused on its
  own terms ("cycle is empty", "tool: … can't be profiled"), never as
  "not on web" or "no active Flutter app connection". `profile_action` validates
  the single nested call before any profiling starts.
- **Nested refusals name the whole path** — `lib/src/arg_coercion.dart` gained a
  `path` prefix on `coerceArguments`; a nested element's argument is now
  reported by its full path (`steps[0].arguments`,
  `steps[0].arguments.durationMs`, `steps[0].tool`) instead of the bare leaf
  name. `preflightStep` wraps a gate problem as `<path>.arguments: <problem>`.
  Direct calls pass no prefix and keep the bare name — the intentional
  direct/nested distinction is unchanged.
- **Unused import removed** — `fp_server.dart` no longer imports
  `src/retired_tools.dart` (translation now lives behind `preflightStep`).
- **Model-facing size stayed within budget without changing a budget number.**
  The envelope added ~270 chars to the three composites; ~160 of now-redundant
  inline examples were trimmed from `execute_action_chain` and `run_on_devices`,
  and the `get_memory_details` description/`cycle` example was tightened
  (the ascii detail already lives in `classes`/`limit`). Result: `all`
  40,737 ≤ 40,987; `sdk_no_plugins` 28,981 ≤ 29,141; `zero_code` 9,698 ≤ 9,974
  (registration budgets) and ≤ 9,700 (the report test's tighter ceiling — it
  had been 9,771 before this trim). No budget number was raised.

### Validation run this session

- `dart analyze` in `packages/fp_server` → clean.
- New `test/action_chain_test.dart` "all-step preflight (task 02)" group (10
  tests): an invalid **last** step is refused and returns no steps; a bad
  argument on the last step is caught (not a sample); a retired tool is
  translated before it is checked; a tool outside the family is refused at its
  path; a scalar array item is not a step; the profile refusal is named at its
  path; an alias survives preflight for the tool to resolve; an empty/non-list
  plan gets its own message; `preflightStep` shares every check for a single
  nested call (profile_action).
- New `test/composite_preflight_test.dart` (12 handler-level tests) drives the
  real callbacks with no running app. Each proof relies on the refusal arriving
  *instead of* the next check the handler would reach (device fan-out, the
  "no running Flutter app" extension error, the web guard): `execute_action_chain`
  invalid-last-before-any-step, family refusal, envelope enforcement/coercion
  (missing `tool`, `arguments` not an object, stringified array/nested object);
  `run_on_devices` invalid-plan-before-fan-out vs a valid plan reaching the
  device check; `get_memory_details(cycle:)` empty/invalid-step/family; and
  `profile_action` unprofilable tool, the profiled tool's own args, and a
  retired name translated before profiling.
- `test/arg_coercion_test.dart` gained a nested-path test
  (`steps[0].arguments`, `steps[0].arguments.durationMs`, `steps[0].tool`).
- Targeted tests green: `action_chain_test`, `composite_preflight_test`,
  `arg_coercion_test`, `structured_results_test`, `run_on_devices_test`,
  `retired_tools_test`, `tool_argument_fuzz_test`, `tool_registration_test`,
  `web_limits_test`, `tool_list_report_test`, `tools_doc_generated_test`,
  `mcp_protocol_compliance_test`.
- Full `packages/fp_server` suite → see "Full-suite status".
- `TOOLS.generated.md` regenerated from the running server (63 tools);
  `tools_doc_generated_test` green.
- `dart format` applied to every touched Dart file.

### Direct / nested compatibility matrix (handoff for task 03)

- **Same accepted shape:** `{"tool": <name>, "arguments": <object>}`.
- **Retired names:** translated in both paths before validation
  (`swipe_widget`/`drag_widget`/`pinch_zoom`/`focus_widget`/`set_slider_value`
  → `gesture_widget` + `gesture`), so a retired name is never an "unknown tool"
  refusal.
- **Aliases** (`target`/`key`, …): accepted by the gate in both paths and
  resolved afterwards (`normalizeToolParams`), so preflight preserves them.
- **Coercion:** identical in both paths because both use `_toolArgGates`
  (`unknownToolArguments` then `coerceArguments`). A malformed JSON string is
  not a valid object in either.
- **Intentional difference:** a direct call reports the bare argument name; a
  nested call prefixes the composite path (`steps[2].arguments.key`).
- **Known limit (not claimed fixed):** a tool's *cross-field* semantic check that
  lives inside its callback and is not expressed in its schema (e.g.
  `gesture_widget`'s "gesture: swipe needs direction") is applied when the step
  runs, not by preflight. Preflight covers shape, family, availability, profile,
  and the schema gate only. Documented here so task 03 does not assume a
  guarantee the code does not make.

### Not run / limited

- Device e2e with a successful vs runtime-failing batch: **not run** here (no
  running app on this workstation). The "zero executed steps" guarantee is
  proven with refusals only; runtime partial-completion reporting is covered by
  existing `describeChain`/structured-result tests, not a live run.
- Replay through the official Inspector: deferred to task 03.

## 03 — Official Inspector interoperability

Status: **done** (non-gated scope). Windows evidence is real; the Linux job is
written but **not run** here.

### Delivered

- **Pinned official Inspector** — `packages/fp_server/tool/inspector/` pins
  `@modelcontextprotocol/inspector` to the exact release **2.11.0** in both
  `package.json` and a committed `package-lock.json` (tarball integrity
  `sha512-gqMw2x0NCotTdjLNv3PSm/IJSeXL7O8u0SpyZXtXGhSukJ2DMoAy8RR7xKngHTCETJcG5gyPdxhOn8zf/ofSRA==`).
  The release's own `engines.node` floor is `>=22.19.0`. `node_modules/` is
  git-ignored; only the pin and the lockfile are committed. Node is a
  development-only extra — the production Dart server never needs it.
- **Portable wrapper** — `tool/inspector/inspector_cli.dart` (library + `main`)
  runs the pinned CLI as one process per probe with explicit argument arrays and
  an explicit working directory. It writes a **read-only** temp `mcpServers`
  `--config` (the Inspector reads it but never writes it), isolates the secret
  store (`MCP_STORAGE_DIR`, `MCP_INSPECTOR_OAUTH_STATE_PATH`) and disables
  auto-open, so a smoke run never touches a developer's real tokens. The config's
  `command` is the **absolute** Dart executable (`Platform.resolvedExecutable`),
  never the `dart` `.bat`/shell shim — the Inspector spawns without a shell.
  Bounded per-probe deadline with process-tree cleanup (`taskkill /T /F` on
  Windows; `pkill -P` then `SIGKILL` on POSIX), stderr logging and call logging
  off, an output cap with a `truncated` flag, single-envelope stdout parsing
  (a banner or any trailing output invalidates the run), and exit-class decoding
  from the pinned CLI's documented `0/1/2/3/4/5/6` classes. Flags:
  `--json`, `--report <path>`, `--node <exe>`.
- **The probes** — ten read-only one-shot invocations (initialize, `tools/list`,
  `resources/list`, `resources/templates/list`, `prompts/list`, `tools/list
  --strict`, a safe no-app `tools/call`, a disconnected `resources/read`, a
  `prompts/get`, and a refusal), plus a negative call the server must refuse and
  a recovery probe that proves the refusal left the server usable. The report
  records Inspector + Node + Dart versions, the server git revision, and the
  requested/negotiated protocol.
- **Protocol era is explicit** — the config sets `"protocolEra": "legacy"` so the
  classic `initialize` handshake is exercised instead of a newer stateless
  profile; FlutterPilot answers `2025-11-25`.
- **Docs** — `tool/inspector/README.md` (pinned identity, install/run, the probe
  list, protocol evidence, the recorded strict warnings, known limits, the manual
  connected-fixture run, and the CI job) and
  `tool/inspector/inspector.config.example.json` documenting the generated
  config's shape.
- **CI job** — `.github/workflows/unit.yml` gained `official-mcp-inspector`
  (matrix ubuntu-latest + windows-latest; `actions/setup-node@v4` with Node
  `22.x` and npm cache on the lockfile; `npm ci --no-audit --no-fund`; `dart pub
  get`; run the wrapper with `--json --report inspector-report.json`; upload the
  sanitized report as an artifact on failure). `inspector-report*.json` is
  git-ignored.
- **Raw suite strengthened (fail-closed framing)** —
  `test/support/stdout_hygiene.dart` adds `StdoutHygiene` (records non-JSON and
  non-protocol stdout lines) and `BoundedStderr` (bounded, redacted stderr).
  `test/fixtures/noisy_stdio_server.dart` and `test/stdout_hygiene_test.dart`
  prove the detector against a live noisy subprocess, not only synthesized
  strings. `mcp_protocol_compliance_test.dart` now routes every stdout line
  through the detector, keeps bounded stderr for diagnosis, and gained a
  "writes only JSON-RPC 2.0 objects to stdout" test — the old comment is an
  assertion now.
- **Hygiene nuance (recorded honestly)** — a `-32700 Parse error` reply carries
  no `id`: JSON-RPC 2.0 says its `id` is `null`, but mcp_dart 2.4.2 *omits* the
  member (`JsonRpcError.toJson()` guards `if (id != null) 'id': …`). A
  `jsonrpc`-versioned object carrying an `error` is unmistakably a protocol
  message, so the detector accepts it; the negative cases it still rejects (a
  scalar/array, a missing `jsonrpc`, an object with none of
  `method`/`result`/`error`) are unchanged.

### Validation run this session

- `dart run tool/inspector/inspector_cli.dart` against the real server (real
  pinned Inspector 2.11.0, Node v24.18.0) → **inspector OK**, every probe `ok`:
  negotiate `2025-11-25` as `FlutterPilot`; `tools/list`, `resources/list`,
  `resources/templates/list`, `prompts/list` all exit 0 with a machine envelope;
  `tools/list --strict` → `0 errors, 3 warnings across 2 tools.` (exit 0);
  `tools/call list_connected_devices` exit 0 no-app; `resources/read` disconnected
  exit 0 with contents; `prompts/get flutterpilot_guide` exit 0 with messages;
  `execute_action_chain {}` exit 5 (`tool_error`, stderr `tool_is_error`) with
  `isError: true` naming `steps`; recovery probe exit 0.
- `test/inspector_cli_test.dart` (9 tests) → passed against a Dart fake launcher:
  argv shape, exit classes, success envelope, tool error, banner/trailing output
  invalidates stdout, empty stdout, output cap/truncation, deadline kill, and a
  verified descendant tree-kill.
- `test/stdout_hygiene_test.dart` (8 tests) → passed, including end-to-end
  banner / mid-stream non-JSON / malformed-JSON-RPC detection.
- `test/mcp_protocol_compliance_test.dart` (21 tests) → passed, including the
  new stdout-hygiene test and the parse-error test that the relaxed rule fixed.
- Full `packages/fp_server` suite → **828 passed, 0 failed** (see Full-suite
  status). `dart analyze` clean. `dart format` applied to every touched Dart
  file.

### Not run / limited

- Linux execution of the new `official-mcp-inspector` job — **not run** here
  (Windows-only workstation). The job is written; its Windows half matches what
  was run locally, the Linux half is untested here.
- The **connected-fixture run** (dynamic SDK/plugin/core/zero-code gating) —
  **not run**; it needs a live device and a disposable app and is documented as a
  manual step. The headless `--list-all` run is not represented as proving live
  gating.
- **Cross-field callback checks are not in preflight** (task-02 limit): a call
  can satisfy the protocol layer and only then be refused by the tool's own
  callback. The wrapper's refusal probe uses a *schema-level* miss (`steps`), not
  a cross-field one.
- **One-shot invocations cannot prove same-session notifications** — persistent
  subscriptions, unsubscribe silence and `notifications/resources/updated` stay
  with the raw suite, by design.
- A real Inspector run needs npm access; a network outage is a **setup failure**,
  never a server pass (the wrapper exits 1 and never prints OK).


## 09 — Startup and MCP-readiness benchmarking

Status: **done.** Windows evidence is real; the connected-app case and the Linux
CI job are **not run** here.

Decision deliverable: **AOT is a large, already-shipped win, and the blocking VM
connection was the remaining readiness bottleneck — so the separately approved
startup-order change is now implemented.** Task 09 itself forbade reordering; the
change was authorized separately ("fix these remaining 3 things", 2026-10-16) and
is independently reversible (`start({transport})`, the `debugInitialConnect` seam
and `_initialConnectPending`).

### Delivered

- **Portable harness** — `packages/fp_server/tool/benchmarks/startup_benchmark.dart`
  (library + `main`). One monotonic clock starts immediately before the spawn and
  records spawn→`initialize`, →`tools/list`, →first read, →first connected read.
  Three app states (`no-app`, `unavailable`, `connected`) and two builds
  (`source` = `dart run`, `aot` = `dart compile exe`) with the AOT build compiled
  **once outside every timed trial**. Explicit `-p` discovery is kept separate
  from explicit `-u` so discovery cost never masquerades as handshake cost;
  `--no-call-log` and `--log-level severe` are always on. Interleaves launch
  modes; labels the first measured trial `first-trial` (or `cold` with
  `--warmup 0`) and reports it separately; keeps 20 raw trials per case plus
  nearest-rank median/p95/min/max over the warm trials; preserves and counts
  timeouts and errors; bounds initialize/request/total deadlines. Reuses task 03's
  helpers via the new shared `tool/support/` (`StdoutHygiene`/`BoundedStderr` and
  `killProcessTree`/`isProcessAlive`), so a failed probe leaves no process behind
  and cleanup is asserted, not assumed.
- **Reserved endpoint, not an external service** — the `unavailable` case binds a
  loopback port, closes it, and hands the server an `http://` VM-service-shaped
  URI for that dead port.
- **Versioned, metadata-only report** — `schemaVersion: 1`, written under the
  git-ignored `benchmark-results/`. Records conditions, environment (OS/Dart/
  Flutter), server revision + `lib/`+`bin/` content hash + source freshness,
  AOT executable hash + compiler flags, server argv, fixture id, every raw trial,
  per-metric summaries and the decision. Redaction: the VM auth token becomes
  `<token>`, the measured package's own path collapses to `<package>`, the home
  directory collapses to `~`, stderr is bounded and token-redacted. No payloads,
  app contents or secrets enter a report.
- **Decision function** — `computeDecision` compares the **same launch mode**
  across app states (so JIT time cannot look like connection cost) against the
  proposed screening threshold (≥ 200 ms **and** ≥ 20% median). It only
  *recommends*; it never edits server code.
- **Tests** — `test/startup_benchmark_test.dart` (26 tests) drives a
  deterministic fake MCP server (`test/fixtures/fake_mcp_server.dart`, env-driven)
  run by the Dart VM: monotonic ordering, delayed handshake, delayed read,
  separately-timed pending connected read, early process death (mid-request, so
  it is deterministic), malformed stdout, per-stage timeout accounting
  (initialize / tools/list / read), tree cleanup incl. a grandchild,
  Windows paths containing spaces, plus pure summary aggregation (failures and
  timeouts retained, nearest-rank p95, empty metric = `n:0`), the decision
  thresholds, and redaction.
- **Docs + CI** — `tool/benchmarks/README.md` (usage, schema, measured result,
  the decision, known limits) and a `startup-benchmark` job in
  `.github/workflows/unit.yml` (matrix ubuntu + windows, `--trials 5`,
  report uploaded on failure). `benchmark-results/` is git-ignored.

### Validation run this session

- `test/startup_benchmark_test.dart` → **26 passed**, twice (before and after the
  path-redaction/metadata change).
- Real run, Windows 11 Pro (Build 26300), 16 CPUs, Dart 3.13.4, Flutter 3.47.5,
  revision `3c9e322`, 20 measured trials + 1 warm-up per case, interleaved,
  `--mode both --case all`:
  - `no-app/source` MCP-ready **2929 ms** (p95 2981); `no-app/aot` **780 ms**
    (p95 794) → AOT removes **~2149 ms (~73%)**.
  - `unavailable/source` **5001 ms** (p95 5039); `unavailable/aot` **2870 ms**
    (p95 2882).
  - 20/20 ok, 0 timeouts, 0 errors, 56 tools, protocol `2025-11-25` in every
    case.
  - Reproduced twice with the same shape (2938/782/5031/2883 first run).
  - Limited `--static-tools` check (AOT, no-app, 3 trials): full 63-tool surface
    at **786 ms** median — indistinguishable from the 56-tool dynamic median, so
    capability discovery is not the readiness bottleneck at this size.
- Decision: `unavailable − no-app = +2072 ms (+71%)` in source, and the same
  ~2.1 s gap in AOT → **`startupOrderingChangeRecommended: true`**, with the
  rationale that any reordering needs separate approval and must not weaken
  first-result honesty, reconnect races, cleanup or client compatibility.
- `dart analyze` clean; `dart format` applied to every touched Dart file.

### Follow-up (2026-10-16) — the reorder, implemented and re-measured

`FlutterPilotServer.start()` now connects the MCP transport **first** and runs the
first VM-service connection **behind it** (`unawaited(_initialConnect())`), which
is exactly the change the decision above recommended. The §16 semantics are
designed, not implied:

- **Connecting vs disconnected.** `_initialConnectPending` is true from `start()`
  until the first attempt settles. While it is true an app-scoped call answers
  `[reconnecting] FlutterPilot is still connecting to the app; retry in a
  moment.` (a retryable category) instead of a premature `No running Flutter app
  found.` Once the attempt settles — connected or definitively none — the normal
  message returns. No call sees a misleading "no app" during startup.
- **Concurrent-connect deduplication.** Pre-existing and unchanged: every path
  (`start`, `roots/list`, `_refreshClientRoots`, tool calls, the reconnect timer)
  goes through `_connectToVmService()`, which shares one attempt via
  `_connecting ??= …`, so the reorder cannot race two live connections.
- **`tools/list_changed`.** Unchanged mechanism: the initial list is computed
  with `hasSdk == null` (everything), and `updateToolVisibility` sends one
  `notifications/tools/list_changed` when the capability probe lands — which the
  reorder makes *more* likely to fire, not less. `_recordListedTools()` still runs
  before the background connect.
- **Roots handling.** `_refreshClientRoots` connects only if not already
  connected and shares the in-flight attempt; client roots are read before
  discovery ends, so discovery still honours them.
- **Shutdown ordering.** `_doConnectToVmService` now re-checks `_disposed` after
  the connection is established and, if the server stopped mid-attempt, closes
  the orphan connection instead of adopting it. `stop()` still never waits on the
  background attempt.

Re-run, same harness, same interleaving, 20 measured trials + 1 warm-up per case,
`--mode both --case all`, revision `e7aed0a` (dirty working tree, as before):

- `no-app/source` MCP-ready **2703 ms** (p95 2758); `no-app/aot` **66 ms** (p95 70).
- `unavailable/source` **2702 ms** (p95 2837); `unavailable/aot` **61 ms** (p95 64).
- 20/20 ok, 0 timeouts, 0 errors, 56 tools in every case; first read tracks
  MCP-ready (no first read was delayed behind the connection).
- The connection penalty is **gone**: `unavailable − no-app` was **+2072 ms**
  (source) and **+2090 ms** (AOT); it is now **−1 ms** and **−5 ms**. The
  post-change decision line correctly reads *"MCP readiness is not dominated by
  the connection"* — the remaining source cost is `dart run` JIT start-up, not
  the VM connection.

Tests: `test/startup_order_test.dart` (2) drives a real `FlutterPilotServer` over
an in-process `IOStreamTransport` and pins `start()` returning while the
connection is still pending, the MCP handshake and `tools/list` answering in that
window, the `[reconnecting]` answer inside it, the normal answer once it settles,
and a clean shutdown mid-attempt. `dart analyze` clean; full suite **983 passed,
exit 0** (was 982; the shutdown test is the addition).

**Real connected e2e** (`dart run tool/e2e_test.dart -d windows` — the §17
requirement). It drives the **local** server source, not an installed build: a
fresh `flutter create` app, `flutterpilot init --local <repo>`, `flutter run`,
the server over stdio, then `tools/call` — covering tool visibility/capability
checks, hot reload/restart, roots (with and without), DTD discovery, `doctor`,
and the config `mcp install` wrote. Three runs on this revision:

- **Run 1:** every connected check green; the one failure was `doctor`'s mtime
  warning, because I edited `lib/` *while the run was in flight* and the
  freshly-compiled `build/fp_server.exe` went stale. Recompiling clears it
  (noted in the task README); it is an artifact, not behavior.
- **Run 2:** `doctor` green, but finding **#345** recurred — `enter_text`
  reported success and the next `press_key` saw `Field: "" (cursor at 0)`,
  cascading four key checks. Recorded as a second sighting in
  `docs/field-test-findings.md`. Intermittent: run 1, same code, passed those
  four.
- **Run 3:** **`E2E passed`, exit 0** (162 printed checks, no failure marker).

### Not run / limited

- **Connected-app case — not run.** No healthy pre-running FlutterPilot app
  existed on this workstation (the sibling labs are not pre-built and
  `pos_lab` has no `fp_sdk` dependency), and faking it would be dishonest. The
  `--case connected` wiring and the separate `spawnToConnectedReadMs` metric are
  in place and unit-tested; the run is a documented manual step. No connected
  number is inferred from the other cases.
- **Linux execution of the `startup-benchmark` job — not run** here
  (Windows-only workstation).
- **No startup-order change was made *in this task*.** The ~2.1 s
  blocking-connection finding was a recommendation only here; the separately
  authorized change and its re-measurement are in the follow-up section above.
- The measured revision was a **dirty** working tree (`sourceFreshness: dirty`),
  recorded honestly: the measured source is not exactly revision `3c9e322`.

## 10 — Conditional analyzer investigation

Status: **done** (investigation + measurement, non-gated scope). No daemon
built. Decision: **retain the log-first one-shot fallback; improve guidance; do
not add a FlutterPilot-owned analysis process.**

### Delivered

- **The fallback is now isolated and testable** — `lib/src/reload_failure.dart`
  gained `analyzerFallbackErrors(...)`: the changed-file scan + one
  `dart analyze --format=machine` + parse, with an **injectable runner** and the
  same behavior (empty string on no files / clean / failure / timeout).
  `_compileErrors` in `self_heal_tools.dart` keeps the log-first branch and
  delegates the analyzer half to it.
- **Opt-in metadata counters** — `CompileFallbackEvent` (outcome, durationMs,
  files count, fromLog, timedOut; **no** paths, messages, contents or arguments)
  and a nullable `compileFallbackObserver`, null by default so a normal server
  records nothing. Every branch reports: `log-errors`, `no-changed-files`,
  `analyzer-errors`, `analyzer-clean`, `analyzer-failed`.
- **Measurement harness** — `tool/benchmarks/analyzer_fallback.dart` (disposable
  Dart package, reuses the **real** library functions, cold-vs-warm one-shot
  `dart analyze`, versioned metadata-only JSON) and
  `tool/benchmarks/companion_capabilities.dart` (read-only MCP handshake +
  `tools/list` against the installed companion). Shared `tool/support/metrics.dart`
  (`summarizeMs`) now backs both this and the task-09 report.
- **Tests** — `test/analyzer_fallback_test.dart` (9 tests): no changed files never
  launches the analyzer; machine-format errors are parsed (and the argv/working
  directory are asserted); clean and failed runs stay quiet; a timeout is
  `analyzer-failed` + `timedOut`; a process failure is not a timeout; no observer
  means no recording and no throw; `maxFiles` is honoured; the non-compiler hints
  never reach the analyzer. `test/metrics_summary_test.dart` (4 tests) covers the
  shared percentile summary. `test/reload_failure_test.dart` still green.
- **Docs** — `tool/benchmarks/README.md` gained the task-10 sections (measurement,
  companion inventory, decision, not-run list).

### Measured evidence (Windows, Dart 3.13.4, 16 CPUs, 15 trials/case)

- Fallback fixed costs: changed-file scan ~0 ms (p95 2), log extraction ~0 ms
  (p95 1).
- One-shot `dart analyze`: clean ~1.9 s, one-error ~1.8 s; all 15/15 ok, 0
  timeouts. **Cold→warm gap only ~4% / 72 ms** — repeating the one-shot does not
  warm it, so a reuse win would require a persistent process (not built or
  measured), so the affected-path gate is **not claimed**.
- Companion `dart mcp-server` v1.2.0 (protocol `2025-11-25`) exposes **14** tools;
  the analysis-relevant ones are **`analyze_files`** ("Analyzes specific paths,
  or the entire project, for errors", with per-root `paths` and `applyFixes`),
  **`lsp`** (hover/signatureHelp/resolveWorkspaceSymbol) and
  **`get_runtime_errors`** (runtime, needs DTD). Schemas were read from
  `tools/list`, not assumed.
- Installed SDK documents `dart language-server --protocol=lsp|analyzer`.

### Decision rationale (task step 12: gate fails / tooling suffices → close)

- Reuse gate not claimed (no prototype; 4% one-shot warm-up).
- Fallback incidence is unmeasured (needs a running app) and rare by
  construction (only after a compile-looking reload failure whose log was
  silent).
- The companion already owns the analyze-this-path surface; a duplicate daemon
  adds lifecycle/memory/staleness risk for no unique capability.

### Not run / limited

- **Incidence (both denominators) and real reload latency** — need a running app
  and a reproducible edit/failure sequence; **not run** here.
- **An Analysis Server / LSP client prototype** — **not built** (separately
  approved scope only). No persistent process was added.
- **Peak memory** of one-shot `dart analyze` — **not measured**
  (`memoryMeasured: false`); only process count is known (one per run, none
  retained).
- No product behavior changed: the fallback returns exactly what it did before;
  the only production additions are the extracted function and the null-default
  observer.

### Follow-up (2026-10-16) — gated item closed, no code

The gated deliverable was a FlutterPilot-owned persistent analyzer, authorized
only if the reuse gate is claimed. Re-ran the same harness on the current
revision (15 trials/case, Windows, Dart 3.13.4): changed-file scan **0 ms**
(p95 3), log extraction **0 ms** (p95 1); `analyze-clean` cold **1921** vs warm
**1964 ms**, `analyze-error` cold **1976** vs warm **1945 ms** — 15/15 ok, 0
timeouts. A repeated one-shot **does not warm**, so the reuse gate is still
**not claimed** and the recommendation is unchanged: retain the bounded one-shot
fallback and point at the companion's analysis tools. Nothing was implemented,
because the gate that would authorize a daemon is not met; there is no code
change to make.

## 04 — Trustworthy evaluation runner

Status: **done** (free scope). Paid canary and the live reset check are gated on
separate approval and a running app.

Implemented (all in `packages/fp_server/tool/eval/`):

- **Versioned outcomes** (`src/outcomes.dart`): passed, failed answer,
  infrastructure error, budget exhausted, explicit skip. `TaskRun` carries the
  outcome; the report counts them apart and `passRate` is over *executed* cases
  only. `Totals.benchmarkValid` is false with zero executed cases, any
  infrastructure error, or any budget stop — so "only skips" or "only errors" is
  never a passing benchmark.
- **Versioned report + run identity** (`src/identity.dart`, `src/report.dart`):
  `schemaVersion: 2` with a `RunIdentity` (model, device, platform, build mode,
  SDK versions, task-suite hash + ids, per-fixture revision/content/scenario
  hashes, runner policy, pricing version). A v1 summary loads as *legacy* and
  `compareReports` refuses it. Comparability requires matching model/device/
  platform/build mode/task suite/fixtures/policy; server commit and guidance/
  tool-schema hashes are reported, not rejected. Missing/extra tasks,
  infrastructure errors, budget stops and skips make the comparison *incomplete*.
- **Explicit pricing** (`src/pricing.dart`, `pricing.json`): a model id maps to
  input/output/cache-read/cache-write USD per million tokens. No substring match
  and no fallback: an unpriced model reports `cost_known: false`, `cost_usd:
  null`. The committed table ships **empty** (no invented price), so `--max-spend`
  refuses to start until a price is supplied. Raw token counts are unaffected.
- **Policy wrapper** (`src/policy.dart`): the model talks to a `PolicyClient`
  whose deny set is the server's own `toolEffects == destructive` set, refusing a
  destructive tool called directly *or* named by a nested
  `execute_action_chain` / `run_on_devices` / `profile_action` step. The reset
  session keeps `--allow-destructive`.
- **MCP adapter hardening** (`src/mcp_session.dart`): keeps the negotiated
  protocol, server identity and `structuredContent`; a non-protocol stdout line
  fails the session (via the task-03 `StdoutHygiene`); a pending request is
  rejected on process exit; response bodies are bounded; close is deterministic
  (stdin, bounded wait, then the task-03 process-tree kill).
- **Bounded I/O and deadlines** (`src/anthropic_runner.dart`): per-request
  timeout, per-run deadline (`--max-run-seconds`), hard call cap (`--max-calls`),
  truncation of forwarded tool results; the whole eval has a deadline and a spend
  guard. Documented that a spend guard cannot undo an in-flight charge.
- **Reset and run validation** (`run_evals.dart`): repeats/limits/ids/apps and
  the pricing table are validated before the key is even required; the lab
  fixture preflight is free. Required resets must succeed, optional ones are
  declared, and the scenario route is read from `get_app_summary`'s structured
  `route` field — not `summary.text.contains(route)`. Bounded, redacted
  artifacts; deterministic exits (1 regression, 2 config, 3 incomplete).

Tests: `test/eval_runner_test.dart` extended from 20 to 33 (outcomes, explicit/
unknown pricing, policy refusals incl. nested steps, identity/legacy/missing-task/
infra-error comparison rules, cache-accounting and truncation, plus three
real-subprocess adapter tests using `test/fixtures/fake_mcp_server.dart`). No
credentials or paid calls. `--max-calls` fixture extended with `FAKE_STRUCTURED`.

### Evidence (free, this session)

- `dart analyze` clean; `dart test test/eval_runner_test.dart` → **33 passed**.
- CLI validation without a key: `--tasks bogus` → exit 2 naming the id;
  `--apps nope` → exit 2; `--max-spend 1` → exit 2 ("needs an explicit price for
  `claude-sonnet-5-5`"); `--repeat 0` → exit 2. The default run reaches the
  missing-key message only *after* the free fixture preflight passes.

### Not run / limited

- **Paid canary and any baseline**: **not run** — needs `ANTHROPIC_API_KEY` and
  separate approval; no money spent.
- **Live reset run twice with identical initial facts** (validation §4):
  **not run** — needs a running lab app and a connected server; the reset is
  verified by unit tests and by construction (structured route + required-reset
  success), not against a live app here.
- **Fixture facts beyond the route** (mocks, settings, seed fingerprints, storage
  counts): only the structured route is asserted; the others are left to a live
  check where a reliable structured source exists (task 07 owns more structured
  results).
- Cost/pricing: no model price is committed, so a real run reports cost unknown
  until a maintainer adds one.

### Follow-up (2026-10-16) — paid path still blocked; fail-closed re-verified

Ran the default suite with `ANTHROPIC_API_KEY` cleared: the run printed **no
fixture-preflight issue**, then stopped at the key gate with exit **2** and the
"everything up to here was free" message — no app was launched, no call was made,
nothing was spent. So the paid canary remains blocked on the key **and** an
explicit spend approval (and a price for the model, since `pricing.json` ships
empty); the free half — including the re-pinned fixture manifest — passes
end to end through the real runner. This cannot be completed without credentials
and a spending decision, so it stays open by design, not by omission.


## 05 — Ten read-only evaluations

Status: **done** (free scope). Ten questions have MCP-verified answers recorded
in `tool/eval/inspection_tasks.yaml`; the paid baseline is a separately approved
milestone.

### Delivered (all in `packages/fp_server/tool/eval/`)

- **Separate suite + schema** — `inspection_tasks.yaml` (canonical YAML) and
  `src/inspection.dart`: `version`, `name`, and `questions` carrying `id`, `app`,
  `category`, `scenario`, `initial_state`, `question`, `answer`, `match`,
  `verified`, `evidence`, `platforms`, `max_calls`. The loader refuses a
  well-formed-but-dishonest entry (a verified question with no answer/evidence, an
  answer without `verified: true`, an unknown category/match/version), and
  `acceptanceProblems()` reports incompleteness (missing/extra cases, duplicate
  ids, an uncovered category) without throwing, so a proposed suite can still be
  reviewed.
- **Ten verified cases, five categories** — `isAccepted` requires exactly ten
  verified cases covering discovery, UI, diagnostics, state/storage and
  zero-code. The committed suite meets it.
- **Optional XML export** — `inspectionSuiteToXml` renders JUnit-style
  question/answer pairs from the parsed entries (every node and attribute
  escaped); the YAML stays canonical.
- **Suite selection** — `run_evals.dart` gained `--suite workflows|inspection`
  (default workflows). An inspection run loads the inspection suite into the same
  runner/report/outcome path, records `suite` in the run policy, and hashes the
  *inspection* suite text into the run identity. It refuses (exit 2) any selected
  question that is not `verified: true`, so a proposed answer can never be scored.
- **Argument-aware read-only policy** — `ReadOnlyPolicyClient` in
  `src/policy.dart`: the allow-list is derived from the server's reviewed effects
  (`toolEffects == reads`) plus the observing mode of the four clear/sweep-capable
  tools; navigation, settings, mocks, clears, scenario, profiler actions, custom
  code and any driving call are refused, and a composite's mutating nested step
  is named. `isReadOnlyCall`/`readOnlyRefusalFor` are pure and unit-tested.
- **Suite-aware reset** — inspection resets only the neutral app settings as
  required; `simulate_network` is optional (the notes lab does not expose it) and
  a missing one is declared, not a reset failure. The workflow reset is unchanged.
- **Free tests** — `test/inspection_suite_test.dart` (24 tests): schema refusals,
  ten-case completeness and category coverage, shuffle independence, XML
  consistency + escaping, and every read-only policy decision including the
  nested-step case and a wrapper that never reaches the session.

### Verified answers (free, this session, twice each from a fresh `scenario(load:)`)

| id | category | answer | confirming call |
|---|---|---|---|
| inspect_shop_list_products | discovery | `8` | `get_network_logs` body lists ids 1..8 |
| inspect_shop_unnamed_controls | ui | `7` | `audit_screen_health` ("Controls without a label (1 finding, 7 controls)") |
| inspect_shop_banner_contrast | ui | `1.61:1` | `audit_screen_health` (contrast 1.61:1, #cccccc on #ffffff) |
| inspect_shop_dark_mode | state | `false` | `get_state` (DarkModeNotifier: false) |
| inspect_shop_list_status | diagnostics | `200` | `get_network_logs` (RESPONSE … 200 [MOCKED]) |
| inspect_notes_note_rows | storage | `250` | `exec_sql_query` (`{"n":250}`) |
| inspect_notes_events_rows | storage | `1200` | `exec_sql_query` (`{"n":1200}`) |
| inspect_notes_tag_two | storage | `ideas` | `get_hive_contents` (tags.2) |
| inspect_notes_secure_key | storage | `lock_pin` | `get_secure_storage` (lock_pin, redacted) |
| inspect_notes_network_simulation | zero_code | `no` | `tools/list` (46 tools; `simulate_network` absent) |

### Validation run this session

- `dart analyze` in `packages/fp_server` → clean.
- `dart test test/inspection_suite_test.dart` → **24 passed**.
- Full `packages/fp_server` suite → **911 passed, 0 failed** (887 + 24).
- CLI: `--help` lists `--suite`; `--suite inspection` without a key runs the free
  fixture preflight and then exits 2 on the missing key (everything before is
  free); a temporarily-added unverified question selected with `--tasks` is
  refused (exit 2) naming it — then the file was restored (0 temp lines).
- Each answer reproduced twice through `tool/fp_bridge.dart` from
  `scenario(load: eval_base|notes_base)` + the neutral settings reset; the
  bridge calls are recorded under `evidence` in the suite.

### Not run / limited (honest)

- **Paid baseline** — **not run** (needs a key and separate approval); no money
  spent. The suite is ready for one canary, then `--repeat 3`.
- **Fixture identity — resolved** — the committed labs (`../fp_lab_shop`,
  `../fp_lab_notes`) were wired to the **pre-rename** package names
  (`flutterpilot_sdk`, …) and no longer resolved against this checkout after the
  `fp_*` rename. They are now rewired (`flutterpilot_` → `fp_` in imports and
  pubspec deps; no app changes — `flutter analyze` clean) and re-pinned:
  `fp_lab_shop` `bde8a67`, `fp_lab_notes` `2700ad3`. `check_fixtures.dart`
  reports "All fixtures match the manifest" and the scenario checksums are
  unchanged. The answers below were taken on `*_scratch` copies of the same
  source (only the package names differed), so they stand; those scratch copies
  have since been removed, and the rewired committed labs are the fixtures in
  use.
- **Linux** — not run (Windows workstation only).
- **The zero-code answer is surface-dependent** — `inspect_notes_network_simulation`
  (`no`) and any tool-count fact change when the curated tool surface changes,
  which the identity hashes catch; that is the point of the question.
- **Unrelated finding** — `fp_lab_notes` exposes 46 tools and **no
  `simulate_network`**; the workflow reset's hard requirement on it would make
  every notes workflow task a reset failure if run. Not changed here (out of
  task-05 scope); the inspection reset treats it as optional.

## 06 — Focused resource reads

Status: **done** (non-gated scope). Windows evidence is real; a live connected
run and any Linux job are **not run** here (see below).

### Delivered (all in `packages/fp_server/`)

- **Per-resource read plans** (`lib/src/resources.dart`): `_resourceExtensions`
  names the app extensions each fixed URI reads, in order. The old
  `_liveResourceData()` always read `getAppSnapshot`, `getErrors` **and**
  `getWidgetTree` for every read; `_liveResourceData(uri)` now reads only the
  plan:
  - `flutterpilot://app/summary` → snapshot + errors (never the tree),
  - `flutterpilot://app/errors` → errors,
  - `flutterpilot://app/widget-tree` → tree,
  - `flutterpilot://app/logs` → snapshot,
  - `flutterpilot://devices` → **nothing** (the fleet is server state), so a
    fleet read makes **zero** app VM calls.
  Errors, tree and logs are read independently: a slow or failing tree call
  cannot delay, fail or grow the others.
- **Injected connection seam** — `ResourceAppConnection` (with
  `ResourceExtensionRead.available`/`unavailable`) and a test-only
  `resourceAppConnectionForTest` field. Production wraps the live
  `DeviceRuntimeContext`/`_callExtensionRaw`; a test installs a fake that counts
  the extensions a URI touched and injects a missing extension, a failure, a
  device switch or a reconnect with no running app.
- **Device/generation pinning** (`_ResourcePin`): a read captures the active
  device id, connection generation and connected state at its start and
  re-checks after every await. A mid-read device switch or reconnect renders a
  `contextChanged` JSON body (or the words for text resources) instead of
  blending two apps. Template reads (`widgets/{key}`, `routes/{path}`) pin too.
- **Unavailable vs clean** — `_extensionData`'s "null on any failure" is split:
  an error list that was asked for and did not come back renders
  `errorsUnavailable: true` (in both the errors and summary resources) rather
  than a silent `count: 0`; a healthy empty list stays unflagged (zero-code's
  locally-tracked `zeroCodeErrors` is still reported as before).
- **Bounded, secret-safe rendering** — JSON resources redact structurally
  (`_redactStrings` applies `Redaction.text` to string values, so the encoded
  JSON stays valid); text resources redact and are bounded with
  `FlutterPilotServer._boundToolText` (512 KiB). Lists are bounded by *items*
  with `truncationNote` metadata instead of cutting serialized JSON: errors cap
  at 50 listed (with `count`/`beforeReloadCount` kept accurate and a `note`),
  a single error field caps at 600 chars, `widgets/{key}` child keys cap at 200
  (`childKeysTotal`/`childKeysTruncated`), route stack/matched routes cap at 100,
  and logs render the newest 500 entries. New limits live in
  `lib/src/constants.dart`.
- **Template safety** — `readWidgetResourceForTest`/`readRouteResourceForTest`
  build the URI from `pathSegments` (`_templateUri`), so a key or route with a
  space, slash, quote or non-ASCII character percent-encodes the echoed URI
  while the app is asked for the raw value. No resource navigates to satisfy a
  read.
- **Unchanged surface** — same five URIs, same names/descriptions/mimeTypes,
  same fields plus additive flags; subscriptions, freshness notifications,
  zero-code fallbacks, no-app shapes and the injected-`ResourceAppData` test
  path are preserved. No new tool, no persistent cache.

### Measured evidence (free, Windows, this session)

Scratch harness (deleted) against a large fixture — 120 errors, a 1,500-node
widget tree, 15 SDK logs — through the public fake connection:

| resource | UTF-8 bytes | parsed | app calls |
|---|---|---|---|
| `flutterpilot://app/summary` | 210 | json ok | 2 |
| `flutterpilot://app/errors` | 9,473 | json ok (120 counted, 50 listed) | 1 |
| `flutterpilot://app/widget-tree` | 112,313 | text | 1 |
| `flutterpilot://app/logs` | 558 | text | 1 |
| `flutterpilot://devices` | 77 | json ok | 0 |

Full five-resource sweep: **5 app calls, `getWidgetTree` once**. Before task 06
every read gathered all three extensions, so the same sweep was **15 calls, the
tree built five times** (verified starting point: `_liveResourceData` read all
three unconditionally). A 30,000-node tree bounds the widget-tree text at
**524,332 bytes** = 512 KiB + the `[response truncated]` suffix, proving the
byte cap.

### Validation run this session

- `dart analyze` in `packages/fp_server` → clean.
- `dart test test/mcp_resources_test.dart` → **37 passed** (16 pre-existing + 21
  new): per-URI call counts and the fleet's zero calls; the five-call sweep;
  failing-tree independence; `errorsUnavailable` vs a healthy empty list;
  device-switch and reconnect pinning (JSON and text); item caps and counts
  (errors and logs); structural redaction of errors/logs/tree text (JSON still
  parses); special-character keys and query routes used verbatim; zero-code
  mode.
- Full `packages/fp_server` suite → **932 passed, 0 failed** (911 + 21).
- `dart format` applied to every touched Dart file
  (`lib/src/resources.dart`, `lib/src/constants.dart`,
  `test/mcp_resources_test.dart`).

### Not run / limited (honest)

- **Live connected-app reads** — the plan/counts/pinning are proven with the
  fake connection and the full server protocol suite, but **not** against a
  running app this session. Task 05's scratch labs were **deleted** during the
  fixture rewire (their committed, pinned replacements remain), so a live run
  must use the committed fixtures; a live confirmed run is not claimed here.
- **Response sizes are a synthetic large fixture**, not a real app screen; they
  demonstrate the bounds and call counts, not a real-world byte total.
- **Same-device latency samples** (step 13) — **not measured**: the change
  removes VM calls, which is the decisive unit here; no timing sample is claimed
  because timing is the flaky signal task 06 says not to rely on.
- **Linux** — not run (Windows workstation only).
- Client guidance was **not** regenerated: URIs and normal response fields are
  unchanged, so no client usage changed (task 06 §"Proposed file boundaries").

## 07 — Structured-result contracts

Status: **done** (non-gated scope). Public `outputSchema` advertisement is the
gated substep in the spec (§11–12); it is now **implemented behind an opt-in
flag, off by default** (see below).

### Delivered (all in `packages/fp_server/`)

- **Executable developer-side contracts** (`lib/src/structured_results.dart`):
  `StructuredField` + `StructuredSpec` describe the supported JSON subset
  (object with required/optional fields, list of items, bool/int/num/string,
  closed string enums), and `structuredProblems(name, payload)` returns every
  way a payload fails its family's contract, at its path
  (`get_errors.errors[0].kind: "boom" is not one of …`). `structuredContracts`
  holds **ten** families: the eight originals (`assert_widget`, `wait_for`,
  `verify_feature`, `run_on_devices`, `get_errors`, `get_app_summary`,
  `execute_action_chain`, `fill_form`) plus the two task-07 pilots
  (`audit_screen_health`, `navigate_to`). It is deliberately **not** registered
  as an MCP `outputSchema`, so nothing validates at the protocol layer and
  `tools/list` does not grow.
- **The documented shape is generated from the contract** — `structuredShapes`
  is now `final`, rendered from `structuredContracts.describe()`, and
  `TOOLS.generated.md` is regenerated from it (`tool/generate_tools_doc.dart`
  is unchanged in shape-authority: it reads `structuredShapes`). Shape strings
  are no longer a second, hand-maintained copy. `structuredResults_test` fails
  if the two disagree, if a family is missing from the doc, or if a shape is not
  a registered tool.
- **Variant honesty: “predicate false” separated from “could not evaluate”.**
  An explicit, optional `status` was added where the two would otherwise read
  alike, documented on every builder:
  - `run_on_devices`: `status: "refused"` with an empty `devices` list
    (`fleetRefusalVerdict`) vs `"partial"` when a device was unreachable, and
    each device now carries `reached: bool` so 0-of-N is never read as “ran
    everything and passed nothing”.
  - `get_errors`: `status: "unavailable"` + `reason` when the app did not
    answer, instead of an empty list that reads as a clean app.
  - `wait_for`: `"unavailable"` when the app did not answer, `"refused"` for a
    call with no condition; a real deadline stays `status`-less and keeps its
    own `timedOut: true` (a genuine, evaluated verdict).
  - `execute_action_chain`: `"refused"` (preflight, zero steps) vs
    `"unavailable"` (the app did not carry the chain out).
  - `fill_form`: `"unavailable"` when the app did not answer.
  - `verify_feature`: a refusal now carries the verdict’s shape
    (`criteria: []`, `status: "refused"`, redacted `reason`); `report`/`feature`
    became optional so a refusal does not fabricate either.
  - `audit_screen_health` / `navigate_to`: `"unavailable"` when the call never
    reached the app.
- **Missing structured verdicts on documented verdict paths were filled in**
  (they used to be bare error results): `run_on_devices` refusal,
  `get_errors` unavailable, `wait_for` unavailable/refused,
  `execute_action_chain` refused/unavailable, `fill_form` unavailable,
  `verify_feature` refusal, `audit_screen_health` unavailable,
  `navigate_to` unavailable.
- **Audit pilot** (`audit_screen_health`, `lib/src/tools/ui_automation_tools.dart`):
  the structured twin reports `requested/visited/audited/failed/skipped`, the
  `findings` counts by category (overflows, tap targets, unlabeled, low
  contrast, reading-order jumps), `restored`, `incomplete`, `loading` and
  `status: "ok"|"partial"|"unavailable"`. A route that could not be reached or
  audited is `failed`; a screen still showing a progress indicator sets
  `loading`; either (or a skipped route past the 40-per-call cap, or errors on
  arrival) makes `incomplete` true, so `status: "ok"` means the sweep covered
  exactly what it was asked to. `restored` is only true when the sweep ended
  back on its start route (or never left it). The prose is unchanged.
- **Navigation pilot** (`navigate_to`): `requested`, `current` (the app’s own
  stack top), `waitRequired`, `waitStatus: "found"|"missing"`, `completed`, and
  `uncertain` (true when the app’s stack could not be read, so `completed` is
  not proof the page is showing). Routes are redacted.
- **Redaction** applied to every new string field (`requested`/`current`
  routes, `reason`, `expected`, device `route`), tested with `token=`/`api_key=`
  fixtures.
- **Consumer facts stay typed** — `fleet_compare` still reads a failed step’s
  structured `reason`; the eval adapter still reads `get_app_summary`’s
  structured `route`; the eval `McpSession` still preserves `structuredContent`;
  `fp_bridge` still prints it. No consumer was changed to parse prose.
- **Registered tool surface unchanged** — no new tool, no description change
  (the opt-in `outputSchema` pilot was added later — see below).

### Measured evidence (free, Windows, this session)

Every family’s representative fixture validated against its contract, UTF-8
bytes of the structured JSON (`out/` scratch harness, deleted after recording):

| family | structured B | keys | family | structured B | keys |
|---|---:|---:|---|---:|---:|
| `assert_widget` | 129 | 4 | `get_app_summary` | 104 | 6 |
| `wait_for` | 65 | 4 | `execute_action_chain` | 109 | 5 |
| `verify_feature` | 233 | 3 | `fill_form` | 88 | 4 |
| `run_on_devices` | 114 | 2 | `audit_screen_health` | 228 | 10 |
| `get_errors` | 185 | 3 | `navigate_to` | 129 | 6 |

- `verify_feature` text **293 B** vs structured **233 B** — the structured
  twin is *smaller* than the text (the criteria list is the only overlap), so
  adding it does not double the payload.
- The whole `structuredShapes` text (documentation only) is **1,890 B**; it
  never reaches `tools/list`.
- **`tools/list` bytes are unchanged** by task 07: `tool_registration_test`’s
  per-profile budgets and `tool_list_report_test`’s numbers are green with no
  threshold moved.

### Validation run this session

- `dart analyze` in `packages/fp_server` → clean.
- `test/structured_results_test.dart` **37 → 62 tests**: the ten contracts and
  their positive fixtures; missing/mistyped/unknown/out-of-enum/nested-path
  failures; every builder’s own output validated; timeout vs unavailable vs
  refused for `wait_for`; clean vs unavailable for `get_errors`; refusal vs
  partial for `run_on_devices`; refusal verdicts for `verify_feature`; the audit
  and navigation pilots; redaction; wrapper preservation; and **handler-level
  variant tests through the real callbacks with no app** proving every
  documented verdict path now carries contract-valid structured content.
- `test/composite_preflight_test.dart` — one expectation updated for the new
  `status: "refused"` field on the chain refusal (an additive field, not a
  weakened assertion).
- Full `packages/fp_server` suite → **957 passed, 0 failed** (932 + 25).
- `TOOLS.generated.md` regenerated (63 tools); `tools_doc_generated_test` green.
- `dart format` applied to every touched Dart file.

### Not run / limited (honest)

- **Public `outputSchema` pilot — implemented behind an opt-in flag, off by
  default.** `StructuredSpec.toJsonSchema` renders the authoritative contracts
  as JSON Schema; `--output-schemas` (`advertiseOutputSchemas`) advertises the
  two pilot families (`audit_screen_health`, `navigate_to`) and nothing else.
  It stays **off** because §11 gates advertisement on a *demonstrated client
  benefit*, which no client here can show — not for budget reasons. Measured
  2026-10-16 on the full registered list: the **model-facing projection** the
  budgets measure (name/description/inputSchema) is unchanged at 40 737 chars
  because it drops `outputSchema` entirely, while the **client wire list** grows
  47 374 → 48 630 B (**+1 256 B**; `audit_screen_health` 822 B +
  `navigate_to` 402 B). Error
  results are exempt from SDK validation on both server and client, so old
  refusal/unavailable paths cannot break; every documented *non-error* variant
  of the two families is proven to satisfy both the contract and the exact
  rendered schema (`test/output_schema_test.dart`, 7 tests, including a real
  in-process `tools/list` round-trip that shows the SDK enforces the schema).
  `toolListJson` now carries `outputSchema` when one is present, so the
  measurement and report can see the cost instead of silently dropping it.
  Reversible: one flag.
- **Text-serialization recommendation review against real clients** (spec §13)
  — not done: it needs Inspector or an eval client’s behaviour on these
  payloads, neither of which runs here.
- **A live connected-app sweep/navigation** — not run (no running app this
  session). The audit sweep’s counts, restoration and `incomplete` flag and the
  navigation `current`/`uncertain` fields are proven at the **builder** level and
  the no-app paths through the real callbacks; the counting loop itself is not
  exercised against a live multi-route app. The scratch labs were **removed**
  during the fixture rewire (task 05 fixtures are now committed and pinned); the
  connected e2e does call `audit_screen_health` once against a live app
  (screen-reader order), which is not a multi-route sweep.
- **`run_on_devices` “partial”/unreachable** is builder-tested only (no two
  registered devices this session).
- **Linux** — not run (Windows workstation only).
- **Paid evaluation** — not run (no key, no approval; no money spent).

### Handoff for task 08

- Contract fixtures: `validStructuredFixtures` in
  `test/structured_results_test.dart` (one payload per family) and
  `structuredContracts` as the authoritative shape source.
- Compatibility notes: every change is **additive** (`status`, `reason`,
  `reached`, `feature?`/`report?` optional) — no existing field was renamed,
  removed or retyped; no consumer needed a change.
- Consumer evidence: `fleet_compare` (structured `reason`), eval adapter
  (`get_app_summary.route`), eval `McpSession` (preserved `structuredContent`),
  `fp_bridge` (prints it) — all unchanged and green.
- Per-profile size deltas: **none** — `tools/list` bytes are unchanged;
  structured payloads are 65–233 B and the doc-only shapes text is 1,890 B.


## 08 — Evidence-led curation and contributor workflow

Status: **done** (free scope). Evidence-dependent *paid* curation is
**inconclusive** — it needs comparable approved runs from tasks 04–05, which
were not run and were not approved; no money was spent and no percentage gain is
claimed.

### Frozen identities (task step 1)

- Server revision `3c9e322` on a **dirty** working tree (all task work is
  uncommitted, so the measured source is not exactly that revision — recorded,
  not hidden). Windows 11 Pro; Dart 3.13.4; Flutter 3.47.5; protocol
  `2025-11-25`; tool surface **63 tools**.
- Task/fixture/model identities: the eval `RunIdentity` from task 04, the
  fixture manifest from task 00, and the default model `claude-sonnet-5-5`
  (pricing table **empty**, so a paid run reports cost unknown and `--max-spend`
  refuses to start). No fixture, task-suite or model identity changed in task 08.

### Static per-profile cost (task steps 2, 5, 6)

`dart run packages/fp_server/tool/tool_list_report.dart` (**Run** this session).
`chars` is the legacy model-facing projection (`toolListChars`, what the budgets
use); `utf8Bytes` its UTF-8 bytes; `wireBytes` the whole object; `tokens` is
`utf8Bytes / 4`, an **estimate**.

| profile | tools | chars | utf8 bytes | wire bytes | ~tokens |
|---|---:|---:|---:|---:|---:|
| all | 63 | 40 737 | 40 789 | 47 374 | 10 197 |
| sdk_no_plugins | 40 | 28 981 | 29 023 | 33 211 | 7 255 |
| sdk_dio | 43 | 30 621 | 30 663 | 35 165 | 7 665 |
| sdk_lab_shop | 48 | 33 734 | 33 782 | 38 806 | 8 445 |
| sdk_lab_notes | 47 | 32 520 | 32 568 | 37 486 | 8 142 |
| zero_code | 15 | 9 698 | 9 710 | 11 282 | 2 427 |
| profile_build | 45 | 31 602 | 31 648 | 36 358 | 7 912 |

These are **static** report numbers (the visibility formula from
`tool_list_report.dart`), not live connected listings — see the gated list.

### Hypotheses ranked (task step 5; at most three)

1. **Guidance avoiding redundant post-action reads** (benefit: fewer duplicate
   `get_app_summary`/`get_widget_tree`/`capture_screenshot` turns after an
   action; risk: low). *Accepted at the free level* — this is already the
   shipped guidance (CLAUDE.md §2 “Trust the response”, `guidance/guide.md`
   “Every action reports … read it before re-checking”, and the tap/chain
   response format). Task 08 did **not** rewrite it, because client usage argues
   for the existing text; only the stale ARCHITECTURE example that still advised
   a re-query was corrected.
2. **Clearer tool distinctions** (benefit: fewer wrong-tool choices; risk:
   medium — a description rewrite can break selection as easily as fix it).
   *Deferred*: ranking benefit needs trace evidence of a specific wrong choice,
   which requires a live session and (for a token claim) an approved paid run.
3. **Compact missing examples** (benefit: smaller `tools/list`; risk: low but
   real — an example the model needed is hard to notice removing). *Already
   exercised* by task 02, which trimmed ~160 chars of now-redundant inline
   examples without raising a budget; nothing further was cut here, because
   cutting on size alone is the cosmetic reduction step 10 rejects.

### Predeclared adoption criteria (task step 9)

A curation candidate is adopted only if **all** hold: no safety regression
(nothing added to the destructive/open-world set, no replay rule weakened); no
newly failing reliable task; no aggregate correctness regression; the target
metric moves beyond ordinary run noise; and no budget is raised. With no
approved comparable run, a paid-metric candidate is labelled **inconclusive**
rather than adopted. Guards recorded: core/profile changes need documented
unsupported tasks and restart/profile guidance (step 10); renames/removals stay
out of default scope and would need separate migration/compatibility approval
(step 11); guidance sources change only when client usage changes, then are
regenerated (step 12).

### Delivered

- **`docs/MCP_DEVELOPMENT.md`** (step 13) — one Dart-specific contributor
  recipe: hypothesis-first curation, research, tool/resource/prompt choice, the
  argument/effect/result contracts, the generated tool reference and guidance,
  test commands and the relevant gate table, the official Inspector, eval
  authoring (fixtures/identity/read-only policy/pricing), budgets, security and
  privacy, compatibility, and the required evidence.
- **PR review integration** (step 14) — `.github/pull_request_template.md` gained
  an “MCP surface changes” section recording the **effect/replay**, **argument
  contract**, **result contract**, **guidance**, **fixture**, and
  **migration/compatibility** decisions, the regenerated-doc requirement, the
  budget rule (lower, never raise), the evidence rule, and the recipe link. Prose
  is backed by gates, not a substitute for them.
- **Automated docs-freshness gate** (step 14) —
  `test/docs_freshness_test.dart` (17 tests): every relative link in the
  published docs resolves to a file that exists (the deleted `TOOLS.md` was
  still referenced from `INDEX.md`, `AI_AGENTS.md`, `BEST_PRACTICES.md` and
  `SETUP.md`); the tool count stated in `CLAUDE.md`, `README.md`,
  `packages/fp_server/README.md` and `CONTRIBUTING.md` equals the registration;
  and `ARCHITECTURE.md` points at the generated inventory and names only real
  tool mixins. Failure messages name the generated reference.
- **Stale references corrected** (step 15), all pointing at the generated
  inventory instead of a hand-maintained copy or a fragile count:
  - `CLAUDE.md`: “67 MCP tools” → the registered count (63).
  - `README.md`: “67 tools” → 63; “a Dio-only app sees 45” → 43 (the report's
    `sdk_dio` number).
  - `packages/fp_server/README.md`: “67 tools” → 63.
  - `docs/INDEX.md`: all 10 `TOOLS.md` links → `TOOLS.generated.md`; the
    obsolete tool-category counts (5/15/8/19/6/12) replaced with the real
    families and a pointer to the generated list; the fragile “~80 KB across 7
    documents” size table replaced with an audience map; `grep '^### \`'` fixed
    to the generated `## \`name\`` heading; the dead `CHANGELOG.md` link
    replaced with `RELEASING.md`; “Last updated” refreshed.
  - `docs/ARCHITECTURE.md`: “~640 lines” and “8 tool mixin files” replaced with
    the real 14 mixins (each named file exists — enforced by the gate) and a
    pointer to `TOOLS.generated.md`; “13 Plugins” → 12; the tap data-flow step
    that advised “use get_navigation_stack or get_errors to verify” replaced with
    the actual combined postcondition the response already carries.
  - `CONTRIBUTING.md`: “across 8 categories” dropped in favour of the generated
    reference (count kept accurate at 63).
  - `docs/AI_AGENTS.md`, `docs/BEST_PRACTICES.md`, `docs/SETUP.md`: `TOOLS.md`
    links → `TOOLS.generated.md`.

### Validation run this session

- `dart analyze` in `packages/fp_server` → clean.
- `dart test test/docs_freshness_test.dart` → **17 passed**.
- Full `packages/fp_server` suite → **974 passed, 0 failed** (957 + 17), see
  “Full-suite status”.
- `dart format` applied to the touched Dart file.
- No production Dart file changed by task 08: no tool, schema, effect, result,
  resource, prompt, guidance or profile was altered, so every existing gate
  (registration budgets, tool-list report, Inspector, protocol) stays green
  with no number moved.
- Guidance was **not** regenerated: client usage did not change (task 06/08
  rule), so there was nothing to regenerate.

### Not run / limited (honest)

- **Live connected-profile listings** (step 2) — **not run**: no running app this
  session, so the per-profile numbers above are the static report formula, not a
  live client's `tools/list`. Live connected gating is documented as a manual
  step (task 03/05).
- **Paid before/after curation** (steps 6–9) — **not run** and **not approved**;
  no `ANTHROPIC_API_KEY`, empty pricing table, no money spent. No model-usability
  or token-saving claim is made; the three hypotheses are labelled accepted at
  the free level, deferred, or already-exercised, and the paid comparison is
  **inconclusive**.
- **Trace-based redundant-follow-up stats** (step 4) — **not run**: needs
  sessions on a live app; the metadata-only `CallLog` cannot by itself prove what
  context a client sends.
- **An installable contributor skill** (step 16) — **not created**; it is a
  separate later decision. `docs/MCP_DEVELOPMENT.md` is the one recipe, kept
  distinct from the generated end-user `SKILL.md`.
- **Linux** — not run (Windows workstation only).
- **Fixture re-pinning** — none attempted (needs separate fixture approval, task
  05); no manifest or scenario hash changed.

---

## Full-suite status

- `packages/fp_server`: `dart test` → **974 passed, 0 failed** (baseline before
  task 00 was 748; the growth is the new runner, fixture-manifest,
  effect-policy, task-01 registration, task-02 preflight/composite, task-03
  Inspector-wrapper / stdout-hygiene / protocol-hygiene tests, task-09's 26
  startup-benchmark tests, task-10's 13 analyzer-fallback / metrics-summary
  tests, task-04's 13 new eval-runner tests, task-05's 24
  inspection-suite tests, task-06's 21 new resource-read tests, task-07's 25
  new structured-contract/variant tests, and task-08's 17 docs-freshness tests).
  **Run** this session, after tasks 00–08, 09 and 10.
- `dart analyze` in `packages/fp_server`: clean. **Run** this session.
- Aggregate runner end-to-end (3 real packages): **passed**. **Run** this
  session. Full-monorepo run through the runner and Linux/CI execution are
  **not run** here.
