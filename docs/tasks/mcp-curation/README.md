# MCP curation: smaller, sturdier, measurable

Task group written 2026-10-14. Read this file fully before you open any task file.

## Why this exists

FlutterPilot has 67 MCP tools. An app sees only the ones that work for it (a
Dio-only app 45, zero-code 15), and the full list costs about 41 KB of names,
descriptions and schemas before the agent calls anything. A lot of curation is
already done (ROADMAP §4): plugin-gated listing, families merged into one tool
with a parameter (125 → 62), description rules enforced by
`tool_registration_test`, annotations on every tool (`tool_annotations.dart`,
including `openWorldHint`), argument aliases (`param_aliases.dart`), unknown
arguments refused (`_tool()` in `lib/flutterpilot_server.dart`), batching
(`execute_action_chain`, `fill_form`, `tap_widget(waitFor)`).

What is missing:

1. **No measurement of agent success.** `tool/e2e_test.dart` proves the tools
   *work*. Nothing measures whether an agent *picks the right tool* and how
   many calls and tokens a task costs. Every later change in this group
   (merging tools, rewording descriptions) needs a before/after number.
2. **Arguments of the wrong JSON type crash into a misleading error.** For
   example `execute_action_chain(steps: "[{...}]")` (a JSON *string*, which
   some clients send) hits `p['steps'] as List?` and throws a `TypeError`.
   The catch in `_registerTool` then says "If the app was busy or reloading,
   retry", which is wrong and makes the agent retry the same bad call.
3. **Tool list could be smaller** for the common case (an app with the SDK and
   one or two plugins), but merges must be driven by data, not taste.
4. **The agent guidance is written in several places** that drift apart.
5. **Pass/fail tools return only prose**, so CI and fleet comparisons parse
   text.

## Tasks and order

| # | File | What | Depends on | Size | Status |
|---|---|---|---|---|---|
| 00 | [00-lab-apps.md](00-lab-apps.md) | Three test apps **outside the repo** (`../fp_lab_shop`, `../fp_lab_notes`, `../fp_lab_plain`) with planted defects and known answers | — | M | ✅ Complete |
| 01 | [01-agent-evals.md](01-agent-evals.md) | Eval runner (Messages API agent loop) + 14 tasks against the lab apps; baseline numbers | 00 | L | ✅ Complete (runner in `tool/eval`) |
| 02 | [02-argument-robustness.md](02-argument-robustness.md) | Schema-driven argument coercion + a fuzz test over every tool | 00 | M | ✅ Merged (#124) |
| 03 | [03-measure-surface.md](03-measure-surface.md) | Per-tool list-cost report per app profile; `stats` shows never-called tools | 00 | S | ✅ Merged (#124) |
| 04 | [04-tool-consolidation.md](04-tool-consolidation.md) | Merge rarely-used tools, retired-name redirects, lower the budgets | 01, 03 | L | ✅ Merged (#124) (`gesture_widget`) |
| 05 | [05-single-source-guidance.md](05-single-source-guidance.md) | Generate server instructions, guide prompt and SKILL.md from one source | 04 | M | ✅ Merged (#124) |
| 06 | [06-structured-results.md](06-structured-results.md) | `structuredContent` for assert/wait/verify/run_on_devices | 02 | M | ✅ Merged (#124) |
| 07 | [07-truncation-hints.md](07-truncation-hints.md) | Every capped list says how much was cut and how to see the rest | — | S | ✅ Merged (#124) |
| 08 | [08-core-tool-profile.md](08-core-tool-profile.md) | `--tools core` for clients with a tool limit (Cursor) | 04 | S | ✅ Merged (#124) |

### Round 2 (Integration & Field-Test Fixes)

| # | File | What | Depends on | Status |
|---|---|---|---|---|
| 09 | [09-integration.md](09-integration.md) | One branch with all nine PRs merged in order, conflicts and cross-PR mismatches fixed, verified together | — | ✅ Merged (#124) |
| 10 | [10-windows-fixes.md](10-windows-fixes.md) | `launch_app` on Windows, `init --local` paths, the 2 always-failing tests | 09 | ✅ Merged (#124) |
| 11 | [11-round1-findings.md](11-round1-findings.md) | Offline vs mocks, `get_network_logs(clear)`, pre-connect logs, stale errors in the summary, `smoke` at text scale 2, `TOOLS.generated.md` freshness test | 09 | ✅ Merged (#124) |
| 12 | [12-core-profile-recheck.md](12-core-profile-recheck.md) | Re-check the 29-tool core set against measured client limits | 09 | ✅ Merged (#124) |

### Round 3 (Changelogs, Leftover Bugs & Relaunch Safety)

| # | File | What | Status |
|---|---|---|---|
| 13 | [13-finish.md](13-finish.md) | Fold #125–#127 into #124, write the missing changelogs, fix #344 (`smoke` on a parameterized route) and #340 (`--zero-code` e2e cleanup on Windows), verify the final branch | ✅ Merged (#124 into `main`) |
| 14 | [14-relaunch-safety.md](14-relaunch-safety.md) | After #124 merges: `launch_app(relaunch: true)` without `device` must not stop the app it can't restart (#346) | ✅ Complete (PR #128 open & reviewed) |

Each FlutterPilot task is one branch and one PR (`feat/agent-evals`,
`fix/arg-coercion`, …), branched from an up-to-date `main`. Do not stack
tasks in one PR. Do not push to `main`, do not merge your own PRs. Task 00
produces no PR (the lab apps are separate local git repos); report it in
writing instead.

**Stop points.** After each task, write the report (see "Definition of done")
and wait for the maintainer before starting the next one. Also stop and ask
when: a task file is wrong about the code (a file, function or flag doesn't
exist as described), a paid eval run needs approval (task 01), the data in
task 04's step 0 says a planned merge is a bad idea, or anything would need
an SDK protocol change.

## Test apps

All manual checks, eval tasks and field tests use the lab apps from task 00,
which live **outside** this repo as siblings of it (`D:\projects\flutter\`):

| App | Use it for |
|---|---|
| `../fp_lab_shop` | most checks: Riverpod, go_router, Dio, sqflite, shared_preferences, planted defects |
| `../fp_lab_notes` | Bloc, Drift, Hive, secure storage, connectivity; big tables and long logs |
| `../fp_lab_plain` | zero-code (no SDK) |
| `../pos_lab` | an existing real app on this machine; read-only use for task 03's data, don't modify it |

Never add apps, build output or test data to this repo. `examples/` is not
used by this task group; leave it alone.

## This machine

Windows 11. Installed: Flutter 3.47 / Dart, git, `gh`, Node (`npx`), Python
3.13. **Not installed:** `melos`, `adb` (no Android), any agent CLI
(`claude`, `gemini`, `codex`). Device for every run: Windows desktop
(`-d windows`; `pos_lab` already builds for it). Shell: PowerShell or Git
Bash; `dart`/`flutter` are `.bat` launchers, so `Process.start` needs
`runInShell: true`.

## Rules for every task

### Do

- Read `CLAUDE.md`, `ROADMAP.md` §0 and §4, and the files the task names
  before writing code. Match the surrounding code: its naming, comment density
  and doc-comment style (comments say *why*, often citing a field-test finding
  number like `(field test #280)`).
- Keep each change server-side unless the task says otherwise.
- Write unit tests next to the existing ones in
  `packages/flutterpilot_server/test/` (or `packages/flutterpilot_cli/test/`).
  A test file per new source file, named `<file>_test.dart`.
- After changing tool names, descriptions or schemas, regenerate the reference:
  `dart run packages/flutterpilot_server/tool/generate_tools_doc.dart` (from the
  repo root) and commit `TOOLS.generated.md`.
- Update every doc that mentions what you changed. Search for the tool or
  flag name across the repo (`CLAUDE.md`, `README.md`, `ROADMAP.md`, `docs/`,
  `skills/flutterpilot/SKILL.md`, `site/`, `serverInstructions` and the
  `flutterpilot_guide` prompt in `lib/flutterpilot_server.dart`).
- Add a short entry to `ROADMAP.md` (§0 state line and the relevant section)
  saying what was done and the measured effect. If you field-test on a real
  app, add findings to `docs/field-test-findings.md` continuing the numbering
  (highest so far is #675; check before you add).
- Error messages an agent reads must say what to do next, in one or two plain
  sentences. No emoji, no "CALL THIS", no selling words
  (`tool_registration_test` rejects them).

### Don't

- **Don't change the SDK ↔ server protocol** (`ext.flutterpilot.*` extension
  names or their parameters in `packages/flutterpilot_sdk`). Apps in the field
  run older SDKs; the server must keep talking to them. If a task seems to
  need an SDK change, stop and write down why in the PR instead.
- Don't raise any budget in `tool_registration_test` (tool count, description
  length, list bytes). Tasks here only lower them.
- Don't add a tool. Every task in this group either keeps the count or lowers
  it. A new capability goes in as a parameter of an existing tool.
- Don't add a `response_format`, `verbose` or similar knob to every tool, and
  don't prefix tool names with `flutterpilot_` (clients already namespace by
  server name; the prefix only costs bytes).
- Don't weaken redaction (`lib/src/redaction.dart`, `docs/security-review.md`).
  Anything new that returns app data goes through the same masking.
- Don't change behaviour that the e2e test or unit tests rely on to make them
  pass. If a test encodes behaviour the task changes on purpose, update the
  test and say so in the PR.
- Don't commit generated or local files: `tool/.fp/`, `.dart_tool/`, eval
  run outputs (task 01 says where those go), API keys.
- Don't read, print or store `ANTHROPIC_API_KEY` anywhere except passing it
  to the API in a request header (task 01).
- Don't run the eval suite (task 01) in CI. It calls a paid model.

## Definition of done (every task)

All of these, pasted into the PR description with their output:

1. Format, analyze and tests. melos is not installed here, so per changed
   package (`packages/flutterpilot_server`, `packages/flutterpilot_cli`, …):
   `dart format --set-exit-if-changed .`, `dart analyze`, `dart test`. Also run
   `dart test` in `packages/flutterpilot_server` even if you only changed the
   CLI (they share behaviour through the call log and tool names). Don't
   install melos globally without asking.
2. The task's own new tests pass, and you show one that **fails without your
   change** (run it on the base commit or describe the failing assertion).
3. End-to-end run on at least one real device:
   `cd packages/flutterpilot_server && dart run tool/e2e_test.dart -d <device>`.
   Use `-d windows` on this machine. The e2e test creates its own temporary
   app; it doesn't use the lab apps. Paste the final pass/fail line. For tasks
   that change what zero-code apps see, also run with `--zero-code`. If a
   check fails on `main` too (before your change), say so with the output;
   don't fix unrelated failures in your PR.
4. Field check on the lab apps (task 00) through the shell bridge, for each
   behaviour the task adds. Start the app, then the bridge (from the repo
   root), then call tools:
   ```bash
   cd ../fp_lab_shop && flutter run -d windows
   ```
   ```bash
   dart run packages/flutterpilot_server/tool/fp_bridge.dart -p ../fp_lab_shop --allow-destructive
   ```
   ```bash
   curl -s localhost:8765 -d '{"name":"get_app_summary","arguments":{}}'
   ```
   Paste the calls you made and the relevant part of each response. Anything
   surprising you see along the way (a wrong message, a slow call, a tool
   that misled you) is a field-test finding: add it to
   `docs/field-test-findings.md` in a new round section, even if you don't
   fix it.
5. `TOOLS.generated.md` regenerated if the tool list changed; docs updated.
6. Task 01's eval suite re-run for tasks 02, 04, 05 and 08 (02 changes how
   arguments are read, so it can change agent behaviour too), with the numbers
   compared to the baseline (task 01 defines how). A drop in task success is
   a blocker, not a footnote.
7. A "What I did not do" section in the PR: anything from the task file you
   skipped or changed, and why.

## Repo map (what you will touch)

- `packages/flutterpilot_server/lib/flutterpilot_server.dart`: server class,
  `_tool()` (argument check), `_registerTool()` (error wrapping, call log),
  `updateToolVisibility()`, `serverInstructions`, `_registerPrompts()`,
  `toolListJson()`.
- `packages/flutterpilot_server/lib/src/tools/*.dart`: tool definitions by area.
- `lib/src/tool_annotations.dart`: effect/idempotent/open-world per tool.
- `lib/src/plugin_tools.dart` (`pluginToolExtensions`), `lib/src/zero_code.dart`
  (`zeroCodeTools`), `debugOnlyTools`, `webUnsupportedTools`, `rasterTools`:
  the visibility sets. Every tool rename touches these.
- `lib/src/param_aliases.dart`: argument aliases and former names.
- `lib/src/action_chain.dart`, `lib/src/fleet_compare.dart`: steps run by
  `execute_action_chain`, `run_on_devices`, `profile_action`, leak `cycle`.
- `lib/src/test_writer.dart`, `lib/src/verification.dart`,
  `lib/src/batch_nudge.dart`, `lib/src/scenario.dart`: record tool calls by
  name.
- `lib/src/call_log.dart` + `packages/flutterpilot_cli/lib/src/call_stats.dart`:
  per-call log and `flutterpilot stats`.
- `test/tool_registration_test.dart`: tool count, description and list-size
  budgets.
- `tool/e2e_test.dart`, `tool/fp_bridge.dart`, `tool/generate_tools_doc.dart`.
- `packages/flutterpilot_cli/bin/flutterpilot.dart`: the CLI (`init --local
  <repo>`, `doctor`, `stats`, `smoke`, `mcp install`); run it with `dart run`
  from this checkout.
