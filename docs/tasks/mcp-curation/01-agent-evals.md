# 01 · Agent evals: measure whether agents pick the right tools

**Branch:** `feat/agent-evals` · **Depends on:** 00 (lab apps) · **Blocks:**
02's eval check, 04, 05, 08

## Goal

A repeatable way to answer: *given only FlutterPilot's tools, does a model
finish realistic Flutter tasks, and how many calls, tokens and seconds does it
cost?* Record a baseline now so later tasks can prove they did not make agents
worse.

This is the evaluation method from the `mcp-builder` skill, adapted: that
guide assumes read-only questions about stored data. FlutterPilot's job is
driving a live app, so tasks here may drive the app, and the runner resets the
app between tasks to keep them independent.

## Non-goals

- Not a replacement for `tool/e2e_test.dart` (that checks tools work; this
  checks models use them well).
- Not run in CI, not on every commit. It calls a paid API. Run by hand before
  and after surface changes.
- No new MCP tool and no server change for the runner's sake.

## Cost and approval (read before running anything paid)

The runner calls the Anthropic Messages API with the maintainer's key from
the `ANTHROPIC_API_KEY` environment variable.

- Never print, log or write the key. Never put it in a file, a command line
  argument or a URL.
- If the variable is not set: build everything, run the unit tests on
  recorded fixtures, then **stop and ask the maintainer** to set it. Don't
  look for a key elsewhere on the disk.
- Before the first full run: run **one** task once, report its token usage
  and cost (from the API's `usage`), extrapolate to the full suite × repeats,
  and **wait for the maintainer's OK** on that amount. Same before any later
  full run whose estimate is more than 1.5× the approved one.

## Deliverables

In the FlutterPilot repo:

```
packages/flutterpilot_server/tool/eval/
  run_evals.dart      # entry point
  src/                # runner library (agent loop, MCP client, scoring, compare)
  tasks.yaml          # the eval tasks
  baseline.json       # committed: summary of the baseline run
  README.md           # how to run, cost of a run, how to add a task
  results/            # gitignored: full per-run outputs
packages/flutterpilot_server/test/eval_runner_test.dart (+ fixtures/)
```

Add `packages/flutterpilot_server/tool/eval/results/` to `.gitignore`.
Scenarios used by the tasks live in the lab apps (task 00), not here.

## Design

### 1. One server process per app, one MCP connection

The runner starts the FlutterPilot server over stdio for the app under test:

```
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart -p ../fp_lab_shop --allow-destructive [--server-args ...]
```

and speaks MCP to it itself (copy the client code from `tool/fp_bridge.dart`;
don't import that file, it's a script). Use the same connection for:

- **resets** between tasks (runner calls tools directly, not through the
  model),
- **the model's tool calls** during a task.

The app is already running (`flutter run -d windows` in the lab app folder),
or the runner starts it with `launch_app` when given `--launch`.

Handle `notifications/tools/list_changed`: re-fetch `tools/list` and give the
model the new list from the next turn on. The list changes after the server
finds the app and reads its plugins; wait for the first `get_app_summary` to
succeed before starting any task, so the model sees the app's real list.

### 2. Agent loop: Messages API, in Dart, no SDK dependency

No agent CLI is installed on the maintainer's machine, so the runner contains
a small agent loop. Check the current Messages API docs
(https://docs.anthropic.com) for request shape, tool use and prompt caching
before writing it; don't rely on memory.

- HTTP with `dart:io` `HttpClient` (or `package:http` if the server package
  already depends on it; don't add dependencies otherwise).
- `tools`: each MCP tool as `{name, description, input_schema}` (the MCP
  `inputSchema` unchanged).
- `system`: the server's `instructions` from the `initialize` result, then one
  line: *"You can only act through these tools. When done, write your final
  answer on the last line as `ANSWER: <value>`."* Nothing else; we are
  measuring FlutterPilot's own guidance.
- Prompt caching on the tools and system blocks (they are identical across
  turns and tasks) to cut cost; record cache read/write tokens.
- Loop: send → for each `tool_use` block call the MCP tool → send
  `tool_result` blocks (text content as text; MCP `ImageContent` as image
  blocks, because screenshots matter to these tasks; `isError` → `is_error:
  true`) → until `stop_reason` is `end_turn` or 40 turns (fail: "turn limit").
- Model: `--model`, default `claude-sonnet-5-5`; pinned and written into
  every result.
- Retries: on HTTP 429/5xx, back off and retry up to 5 times; a task that
  still fails is reported as `error` (infrastructure), not `fail`.
- Keep the loop behind an interface (`abstract class AgentRunner { Future<AgentRun> run(Task, McpSession); }`)
  so a CLI-based runner (Claude Code, Gemini CLI) can be added later. Only
  the API runner now.

Record per run: each tool call (name, ms, isError, result chars), turns,
input/output/cache tokens, wall time, final text, answer, verdict.

### 3. Resets

Before each task (and after it, so a crash in one task doesn't poison the
next):

1. `scenario(load: <task.scenario>)` (default per app: `eval_base` for
   `fp_lab_shop`, `notes_base` for `fp_lab_notes`).
2. `set_app_settings` back to defaults (theme, textScale, locale,
   keyboardInset, windowSize: check which of these a scenario restores and
   only reset the others), `simulate_network(condition: "normal")`,
   `mock_platform_channel(clear: true)`.
3. `get_debug_logs(clear: true)`, `get_state(history: true, clear: true)`
   where available, `get_http_profile(clear: true)`.
4. `get_app_summary`: assert the scenario's route is showing. If not, the
   task is `error` (reset failed), not `fail`.

Plugin-dependent reset calls only where the tool is listed for that app.

### 4. Task format

```yaml
- id: shop_overflow_scale
  app: fp_lab_shop                 # lab app folder name (sibling of the repo)
  scenario: eval_base              # optional, default per app
  prompt: >
    In the running shop app, which of the screens /, /cart, /checkout and
    /settings has a layout overflow when the text scale is 2.0? Answer with
    the route, or "none".
  answer: "/checkout"
  match: exact                     # exact | regex | number
  tags: [layout, settings]
  expected_tools: [set_app_settings, audit_screen_health]   # reported, not enforced
  max_calls: 8                     # soft budget, reported
```

The runner groups tasks by app and starts one server per app. Scoring: text
after the last `ANSWER:`; `exact` = case-insensitive, whitespace-collapsed;
`regex` = full match; `number` = numeric equality.

### 5. The task set (14 tasks)

Answers come from the planted defects in the lab apps' `LAB.md` (task 00).
**Solve every task yourself through `fp_bridge.dart` before trusting its
answer**, and run each one twice with the model before the baseline: a task
whose answer you or the model get two different ways is ambiguous. Rewrite
it.

| id | app | Prompt (short) | Answer source | Exercises |
|---|---|---|---|---|
| `shop_fav_source` | shop | file:line that creates the favourite button on product cards, as `lib/…:LINE` | LAB.md defect 2 | `inspect_widget` |
| `shop_overflow_scale` | shop | which route overflows at text scale 2 | defect 1 | `set_app_settings`, `audit_screen_health(routes)` |
| `shop_unnamed_controls` | shop | how many controls on `/` a screen reader can't name | defect 2 (count on first screen) | `audit_screen_health` |
| `shop_detail_requests` | shop | how many HTTP requests opening the first product makes | defect 9: `2` | `tap_widget`, `get_network_logs` |
| `shop_server_down` | shop | if `/products` returns 500, what button text does the list offer | defect 5: `Retry` | `mock_http_response`, refresh/restart |
| `shop_offline` | shop | with no network, quote the main message on `/` | verify | `simulate_network` |
| `shop_checkout_disabled` | shop | fill name and email only, why is "Place order" disabled? answer the field label that blocks it first | verify (phone or terms) | `fill_form`, disabled-control refusal |
| `shop_crash` | shop | open product id 0: what exception type is thrown? | defect 4: `RangeError` | `navigate_to`, `get_errors` |
| `shop_dark_pref` | shop | turn on dark mode: which SharedPreferences key changes, to what (`key=value`) | verify | `toggle_checkbox`, `get_shared_preferences` |
| `shop_cart_total_hotspot` | shop | which app function takes the most self time when opening `/cart` with items | defect 8 | `profile_action` (scenario `cart_with_items`) |
| `shop_leak` | shop | which app class keeps instances after opening and leaving a product 5 times | defect 7 | `get_memory_details(cycle)` |
| `notes_count` | notes | how many rows does the notes table hold | `250` (+ any seeded) | `exec_sql_query` |
| `notes_bloc_history` | notes | change the settings theme twice; what was the settings state value before the last change | verify | `get_state(history: true)` |
| `notes_locked_key` | notes | which secure storage key holds the lock PIN (key name only) | verify | `get_secure_storage` |

Keep at least one task the current server handles badly; mark it
`known_hard: true` rather than deleting it. A failing task is a finding.

### 6. Runs, repeats, summary

```
dart run tool/eval/run_evals.dart [--model id] [--tasks a,b] [--apps fp_lab_shop] [--repeat 3] [--launch] [--server-args "..."] [--compare tool/eval/baseline.json]
```

(`--server-args` is appended to the server command; task 08 uses it for
`--tools core`.)

- Per task: pass count (`2/3`) and medians of calls, error calls, input
  tokens, output tokens, seconds; tools used with counts.
- Raw transcripts and parsed runs to `tool/eval/results/<UTC timestamp>/`.
  Mask nothing extra (the server already masks credentials), but never write
  request headers.
- `summary.json`:

```json
{
  "model": "claude-sonnet-5-5", "device": "windows",
  "server_commit": "<git rev of FlutterPilot>",
  "apps": {"fp_lab_shop": {"commit": "<lab app git rev>", "tools_listed": 41, "tool_list_bytes": 33000}},
  "tasks": {"shop_overflow_scale": {"pass": 3, "runs": 3, "calls_median": 3,
    "error_calls_median": 0, "input_tokens_median": 21000, "output_tokens_median": 900,
    "cache_read_tokens_median": 15000, "seconds_median": 41,
    "tools_used": {"audit_screen_health": 3, "set_app_settings": 3}}},
  "totals": {"pass_rate": 0.83, "calls_median_sum": 51, "input_tokens_median_sum": 310000, "cost_usd": 4.2}
}
```

`tool_list_bytes`: same measure as `tool_registration_test.listBytes`
(each listed tool's JSON without `annotations`), from the live `tools/list`.

- `--compare`: per-task and total deltas; exit 1 when the pass rate drops or
  a task that passed every baseline run now fails any run. Refuses to compare
  different models, devices or lab-app commits (a changed app changes the
  answers).

### 7. Baseline

After approval of the cost: full suite, `--repeat 3`, on current `main`. Copy
`summary.json` to `tool/eval/baseline.json`, commit. Write the cost and wall
time in `tool/eval/README.md`.

## Tests

`test/eval_runner_test.dart` with recorded fixtures (hand-made or from a real
run with nothing secret in them):

- agent loop against a fake API server (local `HttpServer` returning scripted
  responses) and a fake MCP session: tool_use → MCP call → tool_result,
  images passed as image blocks, `isError` mapped, turn limit, 429 retry,
  `tools/list_changed` refresh.
- answer extraction (last `ANSWER:` wins, missing = fail) and the three match
  modes.
- aggregation (medians, pass counts) and compare (pass-rate drop → exit 1,
  lost always-pass task → exit 1, model/device/app-commit mismatch refused).
- the key never appears in any written file or printed line (run the fake
  loop with a sentinel key and grep the outputs).

## Done when

- [ ] Unit tests pass without a key.
- [ ] Every task's answer verified by hand via `fp_bridge.dart`; calls listed
      in the PR.
- [ ] One-task cost measured; full-run estimate approved by the maintainer.
- [ ] Baseline committed with model, device, commits, tool-list sizes.
- [ ] README Definition of done items 1, 2, 4 (no server change → no e2e).

## Pitfalls

- Windows paths and `Process.start`: use `runInShell: true` for `dart`/`flutter`
  (`.bat` launchers) and test it.
- A model that asks a question instead of answering: fail; make the prompt
  self-contained.
- A model that calls `launch_app(relaunch: true)`: allowed; the next reset
  restores the scenario. Count it in the report.
- Prompts must not contain the answer's keywords (no widget keys or texts
  that turn the task into a lookup), and must have exactly one right answer.
