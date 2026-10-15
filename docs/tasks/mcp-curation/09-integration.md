# 09 · Integration: one branch with all nine PRs, conflicts resolved, verified together

**Branch:** `integration/mcp-curation` · **Depends on:** PRs #115–#123 as they
are now · **Blocks:** merging anything from this task group

Written 2026-10-14, after reviewing round 1.

## Why

Tasks 00–08 were each branched from `main` (`bc63a4a`) and each PR passes on
its own. They have **not** been checked together. A trial merge in the order
below gives textual conflicts in five of them, and there are semantic
conflicts that git will not show (one PR adds a tool name that another PR
removes):

| Merge order | Branch (PR) | Trial merge onto the ones above |
|---|---|---|
| 1 | `docs/mcp-curation-lab-app-findings` (#115) | clean |
| 2 | `feat/agent-evals` (#116) | clean |
| 3 | `fix/arg-coercion` (#117) | clean |
| 4 | `feat/surface-report` (#118) | `ROADMAP.md` |
| 5 | `fix/truncation-hints` (#119) | `ROADMAP.md` |
| 6 | `feat/consolidate-tools` (#120) | clean (textually) |
| 7 | `feat/tools-core` (#121) | `ROADMAP.md`, `TOOLS.generated.md`, `tools/app_inspection_tools.dart`, `tools/devtools_tools.dart` |
| 8 | `feat/guidance-source` (#122) | `lib/flutterpilot_server.dart` |
| 9 | `feat/structured-results` (#123) | `TOOLS.generated.md` |

(Rows 5–9 were tried with the earlier conflicting branch skipped, so expect
more once every earlier one is really in.)

## What to do

1. Branch `integration/mcp-curation` from current `origin/main`.
2. Merge the nine branches **in the order above** with `git merge --no-ff
   origin/<branch>` (keep each as a merge commit so the history shows which
   PR brought what). Resolve each conflict in its own merge commit. Never
   resolve by dropping one side's behaviour; when unsure which side wins,
   stop and ask.
3. After **each** merge: `dart analyze` and `dart test` in
   `packages/flutterpilot_server` (and `packages/flutterpilot_cli` when the
   CLI changed). Don't move on with a red tree; a failure introduced by a
   merge is fixed in that merge or in a commit right after it.
4. Fix the semantic conflicts listed below, each in its own commit.
5. Run the full verification (end of this file).
6. Open **one** PR `integration/mcp-curation` → `main`. In its description,
   list which PR each merge commit came from, every conflict and how you
   resolved it, and the verification output. In each of #115–#123, add a
   comment "Superseded by #<integration PR>" but **do not close them**: the
   maintainer closes them when the integration PR merges.

## Semantic conflicts to fix (not shown by git)

### A. Retired gesture names (#120) vs the docs and guidance (#122)

- #122 rewrote `docs/AI_AGENTS.md`'s tool list using `swipe_widget` /
  `drag_widget`, which #120 removes. Replace with `gesture_widget(gesture:
  swipe|drag|…)`.
- #120 edited the server instructions and the `flutterpilot_guide` prompt
  inside `lib/flutterpilot_server.dart`; #122 moved those texts to
  `packages/flutterpilot_server/guidance/*.md` and generates them. Re-apply
  #120's wording in `guidance/` (instructions, guide, skill, partials), then
  run `dart run tool/generate_guidance.dart` and commit the generated files.
  The generated `serverInstructions` must contain no retired name.
- #122's `guidance_names_test.dart` treats an unknown name as "not a
  registered tool". Now that `lib/src/retired_tools.dart` exists, make a
  retired name fail with "X was merged into Y; update the text" (task 05 §A),
  as #122's PR description says.
- `site/index.html` lines ~105 and ~162 still show `swipe_widget(...)`.
  Rewrite as `gesture_widget(key: "todo_1", gesture: "swipe", direction:
  "down")`. Consider adding `site/` to the name check (it is user-facing),
  stripping HTML tags first; if that's noisy, say so and skip.
- Grep the whole tree for the five retired names afterwards; only
  `retired_tools.dart`, its test, `gesture.dart`'s doc comment,
  `ROADMAP.md`, `docs/field-test-findings.md` and `docs/tasks/` may still
  mention them.

### B. Core profile (#121) vs gesture_widget (#120)

- #121's four step-runner refusal blocks and #120's retired-name translation
  touch the same code. The order must be: **translate retired name → check
  profile → validate arguments**, so `execute_action_chain` with a
  `swipe_widget` step under `--tools core` says "gesture_widget is not
  listed in the core profile …", not "swipe_widget is not …". Add a test.
- Decide with task 12 whether `gesture_widget` belongs in `coreTools`; until
  then leave it out, and make sure the core budget test still matches.

### C. Budgets and the tool list

- `tool_registration_test.dart`: #120 lowered the budgets and #121 added a
  core budget. After all merges, measure (task 03's
  `tool_list_report.dart`) and set each limit to the measured value plus at
  most 300 bytes, with one dated comment. Tool-count limit: count + 5.
- Regenerate `TOOLS.generated.md` **once, at the end** (it carries #120's
  tool change and #123's structured-result shapes); don't hand-merge it.
  #123's `structured_results_test` fails if the doc is stale; it must pass.

### D. `ROADMAP.md`

Several PRs each added "§4 item 4" and a line to §0. Renumber §4 so each item
has its own number in merge order, and make the §0 state line one accurate
sentence: tool count after #120 (62 + `gesture_widget` = check), what landed.

### E. Findings that were deferred because #115 was open

#116, #118, #121, #122 and #123 each say they left a finding out of
`docs/field-test-findings.md` to avoid conflicting with #115. Add them now,
continuing #115's numbering (after #334), in one new section
"MCP curation round 1 (Windows, 2026-10-14)":

- `simulate_network(offline)` does not affect a mocked request (#116);
- the call log's startup `listed` line is the pre-connection set (all plugin
  tools), and two identical lines were written at startup before the dedupe
  (#118);
- the 13 stale tool mentions the name check found in docs (#122);
- the stale `TOOLS.generated.md` on `main` (missing `launch_app(waitSeconds)`)
  (#121/#123);
- mcp_dart validates top-level `tools/call` arguments itself (`-32602`), so
  argument coercion only applies to steps run by other tools (#117).

### F. Small leftovers from round 1

- `../fp_lab_plain` has no `LAB.md` (task 00 asked for one in every app):
  add one (what it covers: zero-code listing; how to run; no planted
  defects, or list any). Commit in that app's own repo.

## Verification of the integrated branch (all required, output in the PR)

1. `dart format --set-exit-if-changed .`, `dart analyze`, `dart test` in
   `packages/flutterpilot_server` and `packages/flutterpilot_cli`. Expected:
   everything passes except the 2 known Windows-separator failures in
   `code_freshness_test.dart` (fixed by task 10; if task 10 is already
   merged, zero failures).
2. `dart run tool/generate_guidance.dart` and `generate_tools_doc.dart`
   produce no diff (generated files are fresh).
3. `dart run tool/e2e_test.dart -d windows` → `E2E passed`; and with
   `--zero-code`.
4. Field check on `../fp_lab_shop` and `../fp_lab_notes` via `fp_bridge.dart`,
   pasted:
   - `tools/list` count for each app with default and with `--tools core`;
   - `execute_action_chain` with a stringified `steps` value containing a
     retired `swipe_widget` step → runs as `gesture_widget`;
   - the same under `--tools core` → refused naming `gesture_widget`;
   - `assert_widget` pass and fail show `structuredContent`;
   - `get_debug_logs(limit: 5)` on fp_lab_notes shows the truncation note;
   - `initialize` instructions equal the generated const and mention no
     retired tool.
5. `dart run packages/flutterpilot_server/tool/tool_list_report.dart`: paste
   all profiles, with the before (`main`) numbers next to them.
6. Evals: only if the maintainer has set `ANTHROPIC_API_KEY` and approved the
   cost (task 01). Run the baseline on `main` **before** this branch is
   merged, then the same suite on this branch with `--compare`. Without a
   key, write "evals not run (no key)" and nothing else; don't estimate
   results.

## Don't

- Don't add features or refactors here. Only merges, conflict resolution, the
  fixes listed above and the commits needed to keep the tree green.
- Don't force-push any of the nine original branches.
- Don't merge the integration PR yourself.
