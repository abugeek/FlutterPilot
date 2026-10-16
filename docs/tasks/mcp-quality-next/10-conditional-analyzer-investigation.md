# 10 — Investigate analyzer reuse only where measured
## Status, priority, and dependencies
Proposed investigation; P2; estimated 1–2 engineering days for investigation only. Branch suggestion: `research/analyzer-fallback-latency`.
Requires task 00 disposable fixtures/measurement units, task 01 effect/safety conventions, and task 09 benchmark conventions. It does not require paid evaluation access.
A persistent analyzer implementation, if justified, needs a separate approved scope/estimate. This document does not authorize building one automatically.
## Problem and expected benefit
Repeated cold analysis can waste time, but FlutterPilot does not routinely run whole-project analysis for every tool call. Determine whether its narrow reload-error fallback is frequent and slow enough to justify process reuse, and avoid duplicating diagnostics already offered by the companion Dart tooling.
## Verified starting points
- `_compileErrors` in `packages/fp_server/lib/src/tools/self_heal_tools.dart` first extracts errors from the existing supervised `flutter run` log after a potentially compile-related reload failure.
- Only when that yields no errors does it inspect recently edited files and invoke `dart analyze --format=machine`, with a 30-second future timeout.
- `packages/fp_server/lib/src/reload_failure.dart` deduplicates/caps compiler errors and reduces analyzer output to actionable locations/messages.
- `packages/fp_cli/lib/src/commands/mcp_command.dart` configures a companion `dart mcp-server` with selected categories disabled. The actual installed SDK/tool listing must be inspected; comments are not evidence of available diagnostic methods.
- No frequency or latency evidence currently establishes that this fallback is a dominant cost. “8 seconds to 300 ms” is not a project benchmark.
## Scope and non-goals
Instrument synthetic fixture runs, compare approaches, and write a decision. Keep supervised-log extraction first. Do not create a duplicate analysis tool surface, assume access to an editor's analysis process, analyze private projects without approval, or install an always-on daemon by default.
## Step-by-step investigation
1. Enumerate reload error paths: successful reload, compiler errors available in launch logs, external/IDE-launched app without those logs, non-compiler failure, no changed files, and unavailable SDK/process.
2. Add test-only or opt-in metadata counters for fallback attempts, reason, duration, timeout, and process outcome. Preserve the metadata-only privacy promise: no file contents, compiler messages, full paths, tokens, or arguments in shared telemetry.
3. Use deterministic disposable apps and a reproducible edit/failure sequence. Record changed-file counts, project size, dependency identity, SDK, OS, and launch ownership.
4. Measure reload latency, log-extraction latency, analyzer process startup, diagnostic completion, and total time until actionable errors. Report source identification/cleanup separately; do not time only the fastest protocol reply.
5. Compare repeated cold analyzer processes and warmed runs under identical file edits. Follow task 09 sample/cache/error-reporting rules and include memory/process count.
6. Measure fallback incidence in a declared representative synthetic workflow. An incidence measured only among intentionally failed reloads is not the incidence among all interactions; report both denominators.
7. Query the installed companion Dart MCP server's actual schemas/capabilities with the configured disabled categories. Record whether relevant diagnostics exist, their freshness, and how an agent can use them.
8. Do not make FlutterPilot depend on access to another client's MCP session. If the companion already solves the task, compare a guidance-based handoff rather than silently invoking an editor-owned daemon.
9. Review current Dart Analysis Server/LSP documentation for the installed SDK before prototyping. Specify initialization, project roots, overlays versus disk state, diagnostic completion/freshness, and shutdown semantics; do not invent analyzer commands from old examples.
10. Compare three choices: keep log-first/current fallback; prefer existing companion diagnostics with a clear handoff; or a lazily owned per-project analysis process. Include operational cost and correctness, not latency alone.
11. Set an explicit proposed adoption gate before experiments: fallback is a meaningful contributor to task latency, and a reuse prototype improves the affected end-to-end median by at least 30% and 250 ms on the same fixture without stale diagnostics or unacceptable memory/process growth. Review thresholds for the actual workload; do not treat them as promised gains.
12. If the gate fails or existing tooling suffices, close with “retain current fallback” or “improve guidance only.” Preserve benchmark evidence; no persistent process is added.
13. If the gate passes, return a separately reviewable implementation proposal with the lifecycle/safety requirements below, memory/idle budgets based on measurements, compatibility, tests, estimate, and rollback.
## Requirements for a separately approved implementation
1. Lazily create a process only for an explicit canonical project root and SDK identity. Bound process count; do not launch one per tool call or device.
2. Isolate multiple projects, SDKs, worktrees, and trust boundaries. No diagnostics from a different root/generation may be returned.
3. Match diagnostics to the requested disk content/version. Handle rapid edits, unsaved overlays, renames/deletes, pubspec/package configuration changes, and analysis completion. Stale or incomplete diagnostics are not “no errors.”
4. Serialize/coalesce overlapping requests safely; a canceled request must not consume another request's result. Bound startup, analysis, and shutdown independently.
5. On timeout/crash, terminate owned processes/descendants and clean pending requests. A Dart future timeout alone does not prove the subprocess stopped.
6. Keep log extraction first and a bounded one-shot fallback on owned-daemon failure. Avoid reconnect/retry loops and repeated expensive analyzer restarts.
7. Stop owned processes on server disposal and a measured idle timeout; make background memory/process cost visible and configurable.
8. Return concise actionable errors through existing redaction/formatting. Do not introduce a broad log dump or duplicate analyzer tool definitions.
9. Keep a straightforward disable/fallback path. An installation without a companion MCP server or IDE must still function.
## Proposed file boundaries
- Investigation targets: `packages/fp_server/lib/src/tools/self_heal_tools.dart`, `reload_failure.dart`, process helpers in `app_launcher.dart`, and companion setup in `packages/fp_cli/lib/src/commands/mcp_command.dart`.
- Add synthetic benchmark scenarios under task 09's proposed `packages/fp_server/tool/benchmarks/` and focused tests.
- Actual analyzer manager, configuration, or protocol client modules remain outside scope until the decision gate and separate approval.
## Validation sequence
1. Test log-first behavior and prove successful/non-compiler reload paths do not launch analysis unnecessarily.
2. Record matched synthetic fallback cases, frequency denominators, timing distributions, and memory.
3. Verify companion capabilities against the installed SDK rather than names/comments.
4. If a prototype is approved, compare diagnostics to fresh one-shot analysis after edit/delete/config changes; inject crash/timeout and verify process cleanup.
5. Run existing reload-failure tests and full server tests for any changed behavior; run device e2e before shipping a runtime implementation.
## Acceptance criteria
- Investigation identifies where fallback happens, how often, and its end-to-end contribution.
- Companion-tool overlap is verified, not assumed.
- The decision can legitimately be “no daemon”; no fixed millisecond result is promised.
- Any reuse proposal includes freshness, project isolation, memory limits, deadlines, cleanup, and fallback.
- No persistent process or runtime architecture change is implemented merely by approving this investigation document.
## Risks and rollback
Warm analyzer caches can return quickly while diagnostics are stale; require content/version evidence and complete analysis. Process reuse adds steady memory and lifecycle work that may exceed savings on a rare path.
Revert opt-in instrumentation independently. A later approved manager must be removable/disableable while retaining log extraction and bounded one-shot diagnostics.
## Handoff
Leave the measured decision, companion capability inventory, verified benchmark invocation, limitations, and either closure without a daemon or a separate implementation proposal awaiting approval.
