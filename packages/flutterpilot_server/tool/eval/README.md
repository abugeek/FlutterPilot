# Agent evals

Answer the question later changes in `docs/tasks/mcp-curation/` need: *given only
FlutterPilot's tools, does a model finish a realistic Flutter task — and how many
calls, tokens and seconds does it cost?* `tool/e2e_test.dart` proves the tools
work; this measures whether a model *picks the right tool*. It calls a paid API,
so it is run by hand before and after surface changes, never in CI.

## Running it

The lab apps (`../fp_lab_shop`, `../fp_lab_notes`) must already be running; the
runner starts the *server*, not the app (`launch_app` cannot start `flutter` on
Windows — see finding #327 in `docs/field-test-findings.md`).

```powershell
cd ../fp_lab_shop && flutter run -d windows        # terminal 1
cd packages/flutterpilot_server                    # terminal 2
$env:ANTHROPIC_API_KEY = "<key>"                   # from your secret store
dart run tool/eval/run_evals.dart --repeat 3
```

Options:

```
--model <id>       Messages API model id (default claude-sonnet-5-5); pinned
                   into every result.
--tasks a,b        Run only these task ids.
--apps fp_lab_shop Run only these lab apps.
--repeat N         Runs per task (default 3).
--launch           Call launch_app first (broken on Windows; the app must be
                   started with `flutter run`).
--server-args "…"  Extra server arguments (task 08 uses "--tools core").
--compare path     Compare against a baseline summary.json; exits 1 on a
                   regression (a drop in the pass rate, or a task that passed
                   every baseline run now failing).
```

Without `ANTHROPIC_API_KEY` the runner exits 2 with a message; the unit tests do
not need it:

```
dart test test/eval_runner_test.dart
```

## Cost

The runner never prints, logs or writes the key; it goes only in the
`x-api-key` request header. It writes raw runs to `tool/eval/results/<UTC>/`
(gitignored) and a `summary.json` with a `cost_usd` computed from the API's own
`usage` (input, output, cache read, cache write) at published Sonnet prices.

**No baseline run has happened yet.** The paid Messages API call needs a key
that was not available when this landed, so `tool/eval/baseline.json` is not
committed and `--compare` has nothing to compare against. When a key is
available: run one task once, get the cost approved, then run `--repeat 3`, copy
`summary.json` to `tool/eval/baseline.json`, and record the cost and wall time
here. A single task is a few tens of thousands of input tokens (the tool list is
~30 KB, sent once per turn but cached across turns) and well under a cent to a
few cents.

## What a result means

- `pass N/M` — how many of the M runs got the task's answer right.
- `calls_median`, `error_calls_median` — the model's tool calls, and how many
  failed, per run.
- `input_tokens_median`, `output_tokens_median`, `cache_read_tokens_median` —
  what it paid. `cache_read` should be most of the input once caching warms up.
- `seconds_median` — wall time.
- `tools_used` — which tools it reached for.

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

## Design notes

- One server process per app, one MCP connection, shared by the runner's own
  reset calls and the model's calls, so the model always sees the app's real
  tool list (`tools/list_changed` is re-read each turn).
- The agent loop is the Messages API directly over `dart:io` `HttpClient`; each
  MCP tool becomes `{name, description, input_schema}`, MCP images become image
  blocks, and `isError` becomes `is_error`. `tool/eval/src/agent.dart` keeps the
  loop behind an interface so a CLI runner can be added later.
- Resets between runs: `scenario(load:)`, the app settings, the network and
  channel mocks, the logs/histories, then an assertion that the scenario's route
  is showing. A failed reset makes the run `error`, never `fail`.
- The baseline (once run) is `tool/eval/baseline.json`, committed with the model,
  device, server commit, lab-app commits and the tool-list sizes (see
  `summary.json`).
