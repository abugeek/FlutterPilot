# Agent evals

Answer the question a curation change must answer (see `ROADMAP.md`): *given only
FlutterPilot's tools, does a model finish a realistic Flutter task — and how many
calls, tokens and seconds does it cost?* `tool/e2e_test.dart` proves the tools
work; this measures whether a model *picks the right tool*. It calls a paid API,
so it is run by hand before and after surface changes, never in CI.

## Running it

The lab apps (`../fp_lab_shop`, `../fp_lab_notes`) must already be running; the
runner starts the *server*, not the app. Pass `--launch` to have the runner
start each app with `launch_app` instead.

```powershell
cd ../fp_lab_shop && flutter run -d windows        # terminal 1
cd packages/fp_server                    # terminal 2
$env:ANTHROPIC_API_KEY = "<key>"                   # from your secret store
dart run tool/eval/run_evals.dart --repeat 3
```

Options:

```
--model <id>       Messages API model id (default claude-sonnet-5-5); pinned
                   into every result.
--suite <name>     workflows (default, tasks.yaml) or inspection
                   (inspection_tasks.yaml, read-only questions).
--tasks a,b        Run only these task ids (an unknown id is an error).
--apps fp_lab_shop Run only these lab apps.
--repeat N         Runs per task (default 3).
--launch           Call launch_app first, instead of expecting the app to be
                   running already.
--fixtures <dir>   Directory holding one subdirectory per lab app (default:
                   the repository's parent).
--server-args "…"  Extra server arguments (task 08 uses "--tools core").
--pricing <path>   Explicit price table (default tool/eval/pricing.json). No
                   price is invented for a model it does not name.
--max-spend <usd>  Stop the suite before the next run when the estimated spend
                   reaches the limit. Needs a price for the model; 0 disables.
--max-calls N      Hard tool-call cap per run; 0 leaves only the turn cap.
--max-run-seconds N  Per-run wall-clock deadline; 0 disables it.
--max-turns N      Messages API turns per run (default 40).
--deadline N       Whole-eval wall-clock deadline in seconds; 0 disables it.
--compare path     Compare against a baseline summary.json; exits 1 on a
                   regression, 3 when the comparison is incomplete.
```

Exit codes: `0` success, `1` regression, `2` invalid configuration or a failed
free preflight, `3` an incomplete/untrustworthy run (infrastructure errors,
budget stops, skips, missing tasks, or a legacy baseline).

## Fixtures are identified, not assumed (task 00)

The lab apps are separate repositories. `tool/eval/fixtures/manifest.json`
records each one's id, checkout location, exact commit, license, plugins,
build mode, devices, seed version and sha256 of every
`flutterpilot/scenarios/*.json`. The runner runs a read-only preflight before
any paid call: a missing checkout, a revision mismatch or a changed scenario
stops the run with exit 2. A dirty checkout is a warning (the run is not
baseline-grade). Check them at any time without spending anything:

```powershell
cd packages/fp_server
dart run tool/eval/check_fixtures.dart                 # uses ../ as the root
dart run tool/eval/check_fixtures.dart --fixtures D:/projects/flutter
dart run tool/eval/check_fixtures.dart --require-clean # baseline-grade run
```

To bootstrap a machine: clone each fixture at the manifest's `revision` next to
this repository (its `sourceLocation`), then run `flutter pub get` in it and
confirm the preflight passes. The manifest is the source of truth for what
"reproducible" means; regenerate a fixture's hashes with
`scenarioChecksumsOf()` in `src/fixtures.dart` when its scenarios change on
purpose.

### Measurement units

`tool_list_chars` is Dart string units (the legacy measure the budgets use);
`tool_list_utf8_bytes` is the same model-facing projection in UTF-8 bytes. They
are equal for today's ASCII descriptions and differ for non-ASCII text. Neither
is what a client necessarily sends to its model; real billed usage is the
`input_tokens` / `output_tokens` / `cache_*` fields the API reports.

Without `ANTHROPIC_API_KEY` the runner exits 2 with a message; the unit tests do
not need it:

```
dart test test/eval_runner_test.dart test/fixture_manifest_test.dart
```

`--base-url` (or the `ANTHROPIC_BASE_URL` environment variable) points the
runner at a local fake instead of the paid API; the key-shaped check still
applies, so a fake key of any value is fine.

## Read-only inspection suite (task 05)

The workflow suite (`tasks.yaml`) drives the app — navigation, mocks, settings,
profiling. A second, separate suite answers Anthropic's "ten inspection
questions" pattern: ten questions the model can settle by *observing* the
fixture, never mutating it. It lives in `tool/eval/inspection_tasks.yaml` and is
selected with `--suite inspection`; the workflow suite is untouched.

```powershell
dart run tool/eval/run_evals.dart --suite inspection --repeat 3
```

What is different about it:

- **The model may only read.** Instead of `PolicyClient` (which denies only the
  server's destructive tools), an inspection run wraps the session in
  `ReadOnlyPolicyClient`: the allow-list is derived from the server's reviewed
  effects (`toolEffects == reads`), plus the *observing* mode of the four
  tools that can also clear or sweep (`get_state`, `get_debug_logs`,
  `get_http_profile`, `audit_screen_health`). Navigation, settings, mocks,
  clears, scenario loads/writes, profiler actions, custom code and a composite's
  mutating nested step all come back as a refusal, and the refusal is scored.
- **Every answer is verified, or the run refuses.** A question is committed with
  `verified: false` and no `answer` until it has been reproduced through MCP from
  a reset state; `--suite inspection` aborts (exit 2) if any *selected* question
  is not `verified: true`, so a proposed answer can never be scored against a
  model. Each verified question records the manual `evidence` (call + response).
- **The reset is milder.** `simulate_network` is optional (the notes lab does
  not expose it), and the required set is just the neutral app settings; a
  missing simulation tool is declared, not a reset failure.
- **The suite is validated for free.** `dart test test/inspection_suite_test.dart`
  checks the schema and its refusals, ten-case completeness across the required
  categories (discovery, UI, diagnostics, state/storage, zero-code), shuffle
  independence, the optional XML export's consistency, and every read-only
  policy decision.
- **XML is an export, not a second source.** `inspectionSuiteToXml` renders the
  YAML as JUnit-style question/answer pairs for external tooling; the YAML stays
  canonical.

The committed suite ships complete: ten verified questions — five on
`fp_lab_shop` (product count, unnamed controls, banner contrast, dark-mode
state, list HTTP status) and five on `fp_lab_notes` (note/event row counts, a
Hive tag, the secure-storage key name, and whether network simulation is
available). Every answer was reproduced twice from a fresh
`scenario(load:)` through `tool/fp_bridge.dart`.

## Cost and budgets (task 04)

The runner never prints, logs or writes the key; it goes only in the
`x-api-key` request header. It writes bounded, redacted raw runs to
`tool/eval/results/<UTC>/` (gitignored) and a `summary.json`.

Costs come from an **explicit, versioned** `tool/eval/pricing.json` — a model id
mapped to USD per million input, output, cache-read and cache-write tokens:

```json
{
  "version": 1,
  "asOf": "2026-10-16",
  "currency": "USD",
  "models": {
    "<model-id>": {
      "input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite": 3.75
    }
  }
}
```

The committed table is **empty on purpose**: no price is invented. A model that
is not named there reports `cost_usd: null` (the raw token counts are still
recorded), and `--max-spend` refuses to start until a price is supplied. Add a
model's price only from the provider's published list, and bump `asOf`.

Guards and their limits:

- **Spend** stops before the *next* run, estimating it from the costliest run so
  far. It cannot undo an in-flight charge, so it is a bound, not a hard cap.
- **Deadlines** bound each API request (`--max-run-seconds`) and the whole eval
  (`--deadline`); a stop records the affected runs as `budget_exhausted`.
- **Calls/turns** (`--max-calls`, `--max-turns`) bound a single run. A run that
  hits a call or turn cap is a non-pass, never a wrong answer.

## Trust: outcomes, identity, and what a comparison needs (task 04)

A run is only evidence if the instrument can be trusted, so:

- **Outcomes are kept apart** — passed, failed answer, infrastructure error,
  budget stop, skip. The pass rate is over *executed* cases only; an
  infrastructure error or a skip never moves it. A run with no executed case, or
  with an infrastructure error, is `benchmark_valid: false` and exits nonzero.
- **Every report carries a run identity** (`schemaVersion: 2`): model, device,
  platform, build mode, SDK versions, the task suite's content hash and ids,
  each fixture's revision/content/scenario hashes, the runner policy, and the
  pricing version. A v1 summary (no identity) is *legacy* and never comparable.
- **A comparison refuses two different measurements** (model/device/platform/
  build mode, task suite, fixtures, policy). The server commit and the guidance/
  tool-schema hashes are *expected* to differ between a baseline and the change
  under test: they are reported, not rejected. A missing or extra task, an
  infrastructure error, a budget stop or an unapproved skip makes the comparison
  **incomplete** (exit 3) — it cannot accept the change.
- **Setup privileges do not leak.** The reset session runs with
  `--allow-destructive`, but the model talks to a `PolicyClient` that refuses
  every tool the server marks destructive (`scenario`, `call_custom_tool`,
  `set_shared_preference`, …), including one named by a nested
  `execute_action_chain` / `run_on_devices` / `profile_action` step.
- **The reset is verified from structured content.** The scenario's route is
  read from `get_app_summary`'s `structuredContent`, not by matching prose;
  every required reset tool must succeed, and an absent optional one is declared.
- **The adapter is bounded and honest.** It keeps the negotiated protocol,
  server identity and `structuredContent`; a non-protocol line on stdout fails
  the session; a pending request is rejected if the server exits; response
  bodies and forwarded tool results are truncated; close is deterministic.

### What is free, and what needs approval

- **Free, no key:** argument/task/app validation, pricing, and the read-only
  fixture preflight. `dart run tool/eval/run_evals.dart --tasks <typo>` fails
  before any paid call.
- **Free, no key, in CI:** the fake Messages API and fake MCP client cover the
  loop, scoring, outcomes, pricing, the policy wrapper, comparison rules and the
  real-subprocess adapter — `dart test test/eval_runner_test.dart`.
- **Needs a key and separate approval:** one paid canary case, once; review the
  spend and the reset evidence before any repetition or baseline acceptance.
  Then `--repeat 3`, copy `summary.json` to `tool/eval/baseline.json`, and record
  the cost and wall time here. A baseline is only valid with a matching identity
  and no infrastructure errors, budget stops or skips.

## What a result means

- `passed` / `failed` / `errors` / `budget_exhausted` / `skipped` — the outcome
  counts, kept apart. `pass N/M` in the summary table is passed over *executed*
  (passed + failed) cases.
- `calls_median`, `error_calls_median` — the model's tool calls, and how many
  failed, per run.
- `input_tokens_median`, `output_tokens_median`, `cache_read_tokens_median` —
  what it paid. `cache_read` should be most of the input once caching warms up.
- `seconds_median` — wall time.
- `tools_used` — which tools it reached for.
- `cost_usd` — only when `pricing.json` names the model; otherwise `null`
  (`cost_known: false`).

## Adding a task

1. Add an entry to `tool/eval/tasks.yaml` with `id`, `app`, `prompt`, `answer`
   and `match` (`exact` | `regex` | `number`).
2. **Solve it yourself through `tool/fp_bridge.dart` first** and paste the call
   and the response into the PR. A task whose answer you or the model reach two
   ways is ambiguous — rewrite it.
3. Keep the prompt free of the answer's keywords, and make sure it has exactly
   one right answer.
4. Run the task twice with the model before trusting it. Keep a task the server
   handles badly, marked `known_hard: true`; a failure is a finding.

## Adding an inspection question

1. Add an entry to `tool/eval/inspection_tasks.yaml` with `id`, `app`,
   `category`, `scenario`, `initial_state`, `question` and `match`, and leave
   `verified` off (or `false`) with **no** `answer`.
2. Solve it yourself through `tool/fp_bridge.dart` from a fresh
   `scenario(load:)` plus the neutral settings reset, **twice**, then record the
   exact `answer`, set `verified: true`, and paste the call and the response into
   `evidence`. A question whose answer is not stable across resets, or that needs
   navigation/mocks/settings, does not belong in this suite.
3. Keep prompts free of the answer's keywords. `dart test
   test/inspection_suite_test.dart` proves the suite is ten verified questions
   covering the required categories.

## Design notes

- One server process per app, one MCP connection, shared by the runner's own
  reset calls and the model's calls, so the model always sees the app's real
  tool list (`tools/list_changed` is re-read each turn). The model's calls go
  through `PolicyClient` (`tool/eval/src/policy.dart`), which refuses the
  server's destructive tools; the runner's resets use the raw session. An
  inspection run (`--suite inspection`) uses `ReadOnlyPolicyClient` instead, so
  the model can only observe.
- The agent loop is the Messages API directly over `dart:io` `HttpClient`; each
  MCP tool becomes `{name, description, input_schema}`, MCP images become image
  blocks, and `isError` becomes `is_error`. The system block and the last tool
  keep their cache breakpoints. `tool/eval/src/agent.dart` keeps the loop behind
  an interface so a CLI runner can be added later.
- Resets between runs: `scenario(load:)`, the required app settings and network,
  the declared-optional mocks/logs/histories, then the scenario's route read from
  `get_app_summary`'s structured content. A failed reset makes the run an
  infrastructure error, never a failure.
- The report is `schemaVersion: 2` with a `RunIdentity`; a v1 summary loads as
  legacy and is refused by `--compare`. The baseline (once run) is
  `tool/eval/baseline.json`, committed with the model, device, server commit,
  lab-app commits, tool-list sizes and the identity (see `summary.json`).

