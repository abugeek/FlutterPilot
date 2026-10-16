# 09 — Benchmark executable startup and MCP readiness
## Status, priority, and dependencies
Proposed; P1; estimated 2–3 engineering days. Branch suggestion: `test/mcp-startup-benchmark`.
Requires task 00 measurement/fixture conventions and task 03 protocol/process supervision. Capture the baseline before task 08 performance experiments. No paid model access is required.
This is a benchmark and decision task, not approval to reorder server startup.
## Problem and expected benefit
Ahead-of-time compilation already exists. Measure what users actually wait for: process launch, MCP initialization, tool discovery, and a useful response. A fast executable does not guarantee fast readiness if app discovery/connection blocks the transport.
## Verified starting points
- `packages/fp_cli/lib/src/commands/mcp_command.dart` enables compilation by default, invokes `dart compile exe`, and writes client configurations pointing to the executable. Windows uses `build/fp_server.exe`; other platforms use `build/fp_server`.
- The same command supports `--no-compile` for `dart run`. Re-running install recompiles; this is not a missing AOT feature.
- `packages/fp_cli/lib/src/commands/doctor_command.dart` checks for stale compiled server binaries.
- `FlutterPilotServer.start()` in `packages/fp_server/lib/fp_server.dart` awaits `_connectToVmService()` before connecting `StdioServerTransport`.
- Current source establishes that ordering, not its user-visible cost. No startup timings were collected during planning.
## Scope and non-goals
Build a repeatable local stdio benchmark and identify bottlenecks. Do not promise near-zero startup, flush OS caches, disable security software, modify client configs, or start unrelated user apps. Do not implement a connection-order change without reviewed evidence and separate approval.
## Step-by-step implementation
1. Define timestamps using one monotonic clock: immediately before process spawn, completed MCP initialize, completed `tools/list`, completed first representative read, and first connected-app read if connection readiness occurs later.
2. Define a useful response per case. A truthful disconnected summary is useful for no-app tests; a premature disconnected response is not evidence of connected-app readiness.
3. Compile the current server once outside timed trials into a disposable build location. Record server revision/content identity, source freshness, compiler flags, Dart/Flutter versions, executable hash, OS/device, fixture ID, and server arguments.
4. Compare `dart run` and that exact AOT executable. Resolve dependencies before trials; report dependency resolution and compilation separately instead of hiding them in startup measurements.
5. Cover three controlled app states: no running app, healthy pre-running fixture, and explicitly configured unavailable VM endpoint. For unavailable cases use a reserved local endpoint/test fixture, not arbitrary external services.
6. Run explicit project-root discovery and explicit URI cases separately so discovery cost is not confused with VM handshake cost. Isolate discovery from unrelated running apps and use no-call-log mode.
7. Keep normal dynamic listing as the primary case; add a limited static-tools case to distinguish readiness from capability discovery. A large static list must not be presented as faster equivalent dynamic discovery.
8. Label process-cold launches versus launches with warmed filesystem/package caches. Record first trial separately; never claim a truly OS-cold boot without controlled evidence. Do not clear global caches to manufacture one.
9. Use a proposed default of 20 measured trials per case after a small warm-up, interleave launch modes, and retain raw timings plus sample counts. Report median/p95, timeout rate, and errors; p95 from a small sample is descriptive, not a stable SLA.
10. Bound initialization, request, and total-case deadlines. Preserve timeout/failure trials instead of dropping slow samples; stop safely if repeated failures indicate a broken fixture.
11. Reuse task 03's strict stdio framing and bounded stderr capture. Terminate each server/process tree; assert cleanup. The pre-running fixture belongs to the harness and remains isolated from user apps.
12. Write versioned metadata-only JSON results under a gitignored benchmark-results directory. Keep VM authentication URIs/tokens, user paths, and raw application output out of shareable reports.
13. Add fake-process tests for monotonic timestamp ordering, delayed handshake, pending app readiness, early process death, malformed stdout, timeout accounting, and Windows paths with spaces.
14. Run on Windows and at least one supported CI OS. Compare each OS with itself; do not interpret cross-machine timing differences as AOT gains.
15. Identify whether discovery/VM connection dominates MCP readiness. Document the AOT gain and remaining bottleneck even if no code change is justified.
16. If blocking connection is material, propose an independently approved change to start MCP before background discovery. Define connecting/disconnected responses, concurrent connect deduplication, capability list-change notifications, roots handling, and shutdown ordering before implementation.
17. For any approved startup change, repeat identical trials and real connected e2e. A faster initialize must not come at the cost of misleading first results, reconnect races, leaked processes, or incompatible clients.
## Decision gate
Before a candidate experiment, agree a same-machine target. A proposed screening default is at least 20% and 200 ms median improvement in the affected case, with no material p95/error-rate regression and no protocol/correctness regression. These are proposed review thresholds, not measured results or universal targets.
If startup is already acceptable or the gain is within noise, close with the benchmark and retain current ordering. Do not rewrite the server just to produce a performance change.
## Proposed file boundaries
- Add a proposed harness under `packages/fp_server/tool/benchmarks/`, with versioned result schema and usage instructions.
- Reuse protocol/process helpers from task 03 rather than the interactive HTTP bridge or private test classes.
- Add dedicated startup-harness tests under `packages/fp_server/test/`.
- `lib/fp_server.dart` startup ordering and CLI compilation code are investigation targets, not automatic edit scope.
## Validation sequence
1. Test the timing/reporting harness with deterministic fake subprocesses.
2. Prove failures/timeouts remain visible and process cleanup completes.
3. Run matched AOT/source cases against disposable fixtures; inspect identities and all raw samples.
4. Verify compiled and source servers expose equivalent supported behavior.
5. Require protocol checks, live dynamic visibility, and device e2e only if a runtime candidate is approved.
## Acceptance criteria
- Reports separate spawn-to-MCP-ready, discovery, and useful connected response latency.
- AOT versus source comparisons use identical fixture/server inputs and clearly labeled cache state.
- Failing and timed-out trials cannot disappear from summaries.
- No secrets or private app contents enter artifacts.
- The deliverable is an actionable measured decision, including “no change needed” where warranted.
- AOT is recorded as existing behavior; no near-zero latency claim is made without evidence.
## Risks and rollback
OS scheduling, antivirus, first-use caches, and fixture startup can dominate small timing differences. Record conditions, interleave runs, and rerun close outcomes. Benchmarking must not change host security settings.
The harness is independently removable. Any later startup-order experiment must be separately reversible without removing AOT support or the benchmark.
## Handoff
Leave the baseline report, verified harness invocation, environment identities, bottleneck explanation, and approved/rejected startup recommendation. Share relevant startup measurements with task 08; task 10 uses the same measurement conventions, not paid evaluations.
