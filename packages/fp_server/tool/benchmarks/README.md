# Development benchmarks (tasks 09–10)

Two independent measurement tools live here:

- **`startup_benchmark.dart`** (task 09) — startup and MCP readiness.
- **`analyzer_fallback.dart`** and **`companion_capabilities.dart`** (task 10) —
  see the task-10 sections at the end.

They share `tool/support/` (metrics, stdio hygiene, process-tree supervision) and
write metadata-only JSON under the git-ignored `benchmark-results/`.

---

# Startup and MCP-readiness benchmark (task 09)

Measures **what a user actually waits for** when a client launches the
FlutterPilot server, on one monotonic clock:

```
spawn → MCP initialize complete → tools/list complete → first useful read
      (→ first connected-app read, when a live app is attached)
```

It exists to answer one question — *does app discovery / VM connection dominate
MCP readiness, or is a fast executable already enough?* — and to leave behind a
raw-data decision. It is **not** an approval to reorder server startup.

We already ship AOT compilation (`packages/fp_cli` invokes `dart compile exe` by
default and points client configs at `build/fp_server.exe`). What was never
measured is its effect on readiness, and whether `FlutterPilotServer.start()`
awaiting `_connectToVmService()` before connecting `StdioServerTransport` costs
a user anything. This harness is what makes that a measurement instead of an
assertion.

## Run it

From `packages/fp_server` (the harness refuses to run anywhere else):

```sh
# The authoritative local run: source + AOT, no-app + unavailable, 20 trials each.
dart run tool/benchmarks/startup_benchmark.dart --mode both --case all

# One build, one state.
dart run tool/benchmarks/startup_benchmark.dart --mode aot --case no-app
dart run tool/benchmarks/startup_benchmark.dart --case unavailable

# A live app (needs its VM Service URI; see "Connected case" below).
dart run tool/benchmarks/startup_benchmark.dart --case connected --uri <vm-uri>

dart run tool/benchmarks/startup_benchmark.dart --json            # print the report
dart run tool/benchmarks/startup_benchmark.dart --trials 5 --warmup 1
```

| Flag | Default | Meaning |
|---|---|---|
| `--mode` | `both` | `source` (`dart run`), `aot`, or `both` |
| `--case` | `no-app` | `no-app`, `unavailable`, `connected`, or `all` (`no-app`+`unavailable`) |
| `--trials` | `20` | measured trials per (case, mode) |
| `--warmup` | `1` | unmeasured launches before the trials |
| `--root` | empty temp dir | explicit project root for discovery |
| `--uri` | – | VM Service URI for `--case connected` |
| `--aot` | compiled in `benchmark-results/build` | reuse an existing AOT executable |
| `--static-tools` | off | add a limited static `tools/list` variant |
| `--list-all` | off | set `FLUTTERPILOT_LIST_ALL_TOOLS` |
| `--json` | off | print the JSON report to stdout |
| `--initialize-timeout`, `--request-timeout` | 30 s | per-stage deadline (seconds) |

Exit code is `0` when every measured trial of every case succeeded, `1`
otherwise (a setup error, or any failed/timed-out trial). A red run means a
trial misbehaved — **not** that startup got slower.

## What one trial does

1. Compile the AOT executable **once, outside every timed trial** (`dart compile
   exe`). Dependency resolution and compilation are reported separately; they
   are never hidden inside a startup number.
2. Warm up once per (case, mode), unmeasured, **interleaving the launch modes**
   so OS scheduling drift cannot favour one build.
3. Measure 20 trials, interleaved. The first measured trial is labelled
   `first-trial` (a warm-up already ran); it is reported separately and excluded
   from the medians, which use the `warm` trials only. `cold` appears only with
   `--warmup 0`, and never claims an OS-cold boot.
4. Reuse task 03's strict `StdoutHygiene` (a banner or malformed line on stdout
   fails the trial) and bounded, redacted `BoundedStderr`, and kill the whole
   process tree with task 03's `killProcessTree`, asserting the pid is gone.

Three controlled app states:

- **no-app** — explicit `-p <empty root>` discovery that finds nothing. Isolated
  from any unrelated app on the machine.
- **unavailable** — explicit `-u <reserved local endpoint>` (a port bound then
  closed, so nothing answers) that fails fast. Never an external service.
- **connected** — a healthy pre-running fixture addressed by its VM Service URI.

## The report

Written as versioned, metadata-only JSON under the git-ignored
`benchmark-results/` (`schemaVersion: 1`, one timestamped file per run). It
contains conditions, environment/server identity, every raw trial, per-metric
median/p95/min/max for the warm trials, timeout and error rates, the separate
first trial, and the computed decision.

Redaction: the VM authentication token is replaced (`http://127.0.0.1:29765/
<token>/…`), the measured package's own location collapses to `<package>`, the
home directory collapses to `~`, and stderr is bounded and token-redacted. No
server payloads, app contents, or secrets enter a report.

## Measured result — Windows, 2026-10-16

Conditions: Windows 11 Pro `10.0 (Build 26300)`, 16 CPUs, Dart `3.13.4`,
Flutter `3.47.5`. Server revision `3c9e322`, source freshness **dirty**
(uncommitted working-tree changes under `lib/`/`bin/`, so the measured source is
not exactly the reported revision — recorded honestly). AOT executable
`65b0c5b8…`, compiler flags `dart compile exe`. 20 measured trials + 1 warm-up
per case, interleaved. Every case: 20/20 ok, 0 timeouts, 0 errors, 56 tools,
protocol `2025-11-25`.

Median spawn→`tools/list` (a single clock; median over 19 warm trials):

| case | source (`dart run`) | AOT (`dart compile exe`) | AOT gain |
|---|---|---|---|
| no-app | **2929 ms** (p95 2981) | **780 ms** (p95 794) | −2149 ms (~73%) |
| unavailable | **5001 ms** (p95 5039) | **2870 ms** (p95 2882) | −2131 ms (~43%) |

First useful read (`list_connected_devices`) adds ~10 ms in every case.

**Limited static-tools case.** A short `--static-tools` check (AOT, no-app, 3
trials) returned the full 63-tool surface at a 786 ms median — indistinguishable
from the 56-tool dynamic median (780 ms). At this size, readiness is dominated by
process launch and connection, not by capability discovery; a large static list
is *not* presented here as a faster equivalent to dynamic discovery.

## The decision

`computeDecision` compares the **same launch mode** across app states, so JIT
compile time cannot masquerade as connection cost:

- no-app vs unavailable, source: `5001 − 2929 = +2072 ms (+71%)`.
- The same gap appears in AOT (`2870 − 780 = +2090 ms`): an unreachable VM
  endpoint costs **~2.1 s in both builds**, because `start()` awaits
  `_connectToVmService()` before the stdio transport is connected.

So the honest reading is two-part:

- **AOT is a win and already exists.** It removes ~2.15 s of JIT startup from
  every launch — this is the largest single readiness improvement available, and
  it is already the default in `fp_cli`.
- **The remaining bottleneck is the blocking connection.** A ~2.1 s delay before
  MCP is even reachable is a real user-visible cost, and it clears the proposed
  screening threshold (≥ 200 ms and ≥ 20% median).

`startupOrderingChangeRecommended: true` is therefore a **proposal for a
separately approved change** (start MCP before background discovery), not a
change made here. Task 09 explicitly forbids reordering startup in this task.
Any such change must be designed and reviewed against: connecting vs
disconnected first results (no premature/misleading summary), concurrent-connect
deduplication, `notifications/tools/list_changed` semantics, roots handling, and
shutdown ordering — then re-measured with identical trials and a real connected
e2e. If the reviewed gain lands inside noise, the correct outcome is to keep the
current ordering.

## Connected case

**Not run here.** It needs a healthy, pre-running FlutterPilot app, and this
machine had none (the sibling sample labs are neither pre-built nor dependency-
resolved). Rather than fake it, the connected path is left unmeasured; the
`--case connected` wiring and the separate `spawnToConnectedReadMs` metric are in
place and unit-tested, and the run is a documented manual step. A `connected`
result must never be inferred from the `no-app`/`unavailable` runs.

## Known limits (recorded, not hidden)

- **Not an OS-cold boot.** `first-trial` is labelled, but global caches are never
  cleared to manufacture a cold number.
- **p95 from a small sample** is descriptive, not a stable SLA.
- **Machine-specific.** CI numbers are directional; AOT/source comparisons are
  only valid *within* one machine and one run.
- **No device e2e.** A connected app run needs a live device and is manual.
- Faults stay visible: failed and timed-out trials are counted in the summary and
  force exit `1`; they are never dropped to make a median look good.

## Tests

`test/startup_benchmark_test.dart` (26 tests) drives a deterministic fake MCP
server (`test/fixtures/fake_mcp_server.dart`) run by the Dart VM — no real
server, app, or network — and covers monotonic ordering, delayed handshake,
pending app readiness, early process death, malformed stdout, per-stage timeout
accounting, tree cleanup, and paths containing spaces; plus pure tests for the
summary aggregation (failures/timeouts retained, nearest-rank p95, empty metric),
the decision thresholds, and redaction.

## CI

The `startup-benchmark` job in `.github/workflows/unit.yml` runs the harness on
Linux and Windows with `--trials 5` and uploads the report on failure. Fewer
trials keep the gate quick; the numbers there are directional and never compared
across operating systems.

## Removable

The harness, its fixture, its test, its CI job and its git-ignored output
directory are self-contained. Deleting `tool/benchmarks/`, the test, and the CI
job removes the benchmark without touching server code, AOT support, or the
shared task-03 helpers.

---

# Analyzer-fallback measurement (task 10)

FlutterPilot analyses whole files in exactly one place: after a reload fails in
a way that *looks* like a compile error and the supervised `flutter run` log held
no errors, `_compileErrors` runs `dart analyze --format=machine` on the files
edited since the last good reload. Task 10 asked whether that fallback is
frequent and slow enough to justify reusing a persistent analysis process.

```sh
# from packages/fp_server
dart run tool/benchmarks/analyzer_fallback.dart --trials 15
dart run tool/benchmarks/companion_capabilities.dart
```

`analyzer_fallback.dart` builds a disposable Dart package (20 clean files + one
erroring file), then times the fallback's real components with the **real**
library functions (`dartFilesChangedSince`, `compileErrorsIn`,
`analyzerErrorsIn`): the changed-file scan, the log extraction, and one-shot
`dart analyze` **cold versus warm** under identical files. It does **not** build
a persistent process — that is out of scope.

Measured on Windows (Dart 3.13.4, 16 CPUs, 15 trials per case):

| component | median | p95 |
|---|---|---|
| changed-file scan (20 edited files) | ~0 ms | 2 ms |
| log extraction (a compile-error block) | ~0 ms | 1 ms |
| `dart analyze`, clean project | ~1.9 s | 1.9 s |
| `dart analyze`, one error | ~1.8 s | 1.8 s |

Every trial succeeded (0 timeouts, 0 errors). The cold→warm gap was only
**~4% / 72 ms**, i.e. simply repeating the current one-shot invocation does not
warm it. So a reuse win could only come from a persistent in-process analysis
session — which this harness did **not** build or measure, so the adoption gate
(≥ 30% and ≥ 250 ms on the affected path) is **not claimed**.

`companion_capabilities.dart` starts the installed companion **`dart mcp-server`**
(v1.2.0, protocol `2025-11-25`) read-only and lists its real tools. It exposes
**14** tools, including three analysis-relevant ones (schemas verified, not
assumed):

- **`analyze_files`** — *"Analyzes specific paths, or the entire project, for
  errors"*, with per-root `paths` and optional `applyFixes`. This is the same
  surface FlutterPilot's fallback provides.
- **`lsp`** — hover / signature help / workspace-symbol resolution.
- **`get_runtime_errors`** — recent **runtime** errors (needs DTD), a different
  signal from compile errors.

## Task-10 decision

**Retain the log-first, bounded one-shot analyzer fallback; improve guidance;
do not add a FlutterPilot-owned analysis daemon.** Reasons:

- The reuse gate is **not claimed** — no persistent prototype was built, and
  one-shot runs do not warm (4% / 72 ms).
- The fallback is **rare by construction**: it runs only after a
  compile-looking reload failure whose supervised log was silent, and only for
  files edited since the last good reload. Its **incidence was not measurable
  here** (no running app), and neither denominator is known.
- The companion **already owns** the "analyze this project/path" surface, so a
  duplicate daemon adds lifecycle, memory and staleness risk for no unique
  capability. Guidance toward `dart mcp-server` is the cheaper, reversible path.

The affected-path cost (~1.8 s per invocation) is real but is paid rarely and is
bounded by a 30 s timeout. Opt-in counters
(`compileFallbackObserver` in `lib/src/reload_failure.dart`) let a future run
with a live app measure incidence and duration without changing default
behavior; the extracted `analyzerFallbackErrors` makes every branch (no changed
files, clean, errors, timeout, process failure) unit-testable.

### Not run

- **Incidence** (both denominators) and **real reload latency** — need a running
  app and a reproducible edit/failure sequence; **not run** here.
- **Analysis Server / LSP client prototype** — out of scope. The installed SDK
  (Dart 3.13.4) documents `dart language-server --protocol=lsp|analyzer`; a
  persistent client would have to define analysis-root setup, overlays vs disk,
  diagnostic completion/freshness and shutdown, and is a separately approved
  implementation only.
- **Peak memory** of a one-shot `dart analyze` — not measured (reported
  `memoryMeasured: false`); only the process count (one per run, none retained)
  is known.
