# 04 · Tool consolidation: fewer tools for the common app, decided by data

**Branch:** `feat/consolidate-tools` · **Depends on:** 01 (baseline), 03 (report)
· **Blocks:** 05, 08

## Goal

Cut what the common app's agent sees (`sdk_lab_shop` profile from task 03)
from about 35–41 tools to **about 25–30**, and its list bytes by at least
**15 %**, **without** lowering the eval pass rate from task 01. The tool
count is a means; the measure is list bytes and eval results.

The `mcp-tool-curator` skill says ≤15–20 tools per server. Don't chase that:
FlutterPilot covers too much (driving, inspection, state, network, perf,
regression), and the per-app gating already does most of the work. Merge only
where a merged tool is as easy for a model to use as the separate ones.

## Step 0: decide with data (write this up before coding)

Produce a table in the PR, one row per candidate below, with:

- list bytes of each tool involved (task 03 report, `sdk_lab_shop`),
- calls in the collected logs (task 03 `stats`), and which eval tasks used it,
- estimated bytes of the merged tool (write the merged description and schema
  first, measure it with the shared `listBytes` function),
- annotations of each tool involved (see the rule below),
- verdict: merge / keep / drop, and one sentence why.

**Rules for a merge:**

1. **Same annotation class only.** A merged tool gets one set of annotations.
   Merging a read-only tool into an acting one makes clients ask approval for
   what used to be a free read, and stops parallel reads. Never merge a
   `ToolEffect.reads` tool into an `acts` one, or `acts` into `destructive`.
2. **One mode argument, an enum,** named for what the agent wants
   (`action`, `gesture`, `kind`), with the most common mode as default when
   that is natural. No nested objects added.
3. **The merged description is shorter than the sum** of the old ones by a
   real margin (≥ 25 %). If it isn't, keep them separate.
4. **No mode's arguments silently ignored in another mode.** An argument that
   only applies to one mode, passed in another, is refused with a message
   (same idea as `unknownToolArguments`).
5. **Rarely-called tools are the best candidates.** A tool called often and
   alone (`tap_widget`, `enter_text`, `get_app_summary`) stays as it is.

## Candidates (verify each; the data may say no)

| # | Today | Proposal | Annotation check | Notes |
|---|---|---|---|---|
| C1 | `register_device`, `switch_device` | `use_device(id, uri?)`: with `uri` registers (or updates) then switches, without switches; `activate: false` to register only | both `acts`, idempotent: OK | `list_connected_devices` (reads) stays separate. Every SDK app pays for these two today. |
| C2 | `connect_app` | fold into `launch_app(uri: ...)`: with `uri`, attach to that running app instead of building | both `acts`; `launch_app` is not idempotent, `connect_app` is: the merged one is not. Acceptable? decide and say | `connect_app` without `uri` auto-discovers; keep that as `launch_app(attach: true)`? Pick the form that is clearest; don't make `launch_app` ambiguous about whether it builds. |
| C3 | `swipe_widget`, `drag_widget`, `pinch_zoom`, `focus_widget`, `set_slider_value` | one `gesture_widget(key, gesture: swipe\|drag\|pinch\|focus\|slide, ...)`, or add some to `tap_widget(gesture:)` which already has double/long/secondary | all `acts` | Check calls: if `swipe_widget` is common, keep it and merge the rest. `set_slider_value` is idempotent, the others not. |
| C4 | `get_semantics_tree` | `get_widget_tree(semantics: true)` | both reads: OK | Check that zero-code lists both today (`zeroCodeTools`); the merged one must keep working in zero-code. |
| C5 | `get_interactive_elements` | `get_app_summary(elements: "all")` | both reads: OK | The summary already lists tappable elements; this is the full list. Check the CLAUDE.md wording that points at it. |
| C6 | `native_tap`, `native_text`, `native_button`, `native_open_app` | `native_input(action: tap\|text\|button\|open_app, ...)` | all `acts` | `native_screenshot`, `native_describe_screen` (reads) stay separate. Only listed on iOS sim / Android, so this doesn't help `sdk_lab_shop`; do it only if cheap. |
| C7 | `get_network_logs` (Dio) vs `get_http_profile` (dart:io) | keep both unless the data shows agents confuse them; if they do, fix the descriptions first (one sentence each on when to use which) | both reads | Merging would need both data sources in one tool; likely not worth it. |
| C8 | `set_shared_preference`, `set_secure_storage_key` vs their getters | **keep**: setters are `destructive`, getters `reads` | rule 1 | Listed here so nobody merges them. |

Expected outcome if all of C1–C5 pass the rules: −6 tools for every SDK app.
Measure; don't promise the number.

## Implementation (for each accepted merge)

A merge touches many places. For every old name, search the whole repo
(`grep -rn "'old_name'\|old_name(" --include=*.dart --include=*.md .`) and
update:

1. **Definition:** the new tool in the right `lib/src/tools/*.dart`; the old
   ones removed. Reuse the old implementations as private functions; don't
   rewrite their logic.
2. **Annotations:** `toolEffects`, `idempotentTools`, `openWorldTools` in
   `tool_annotations.dart`.
3. **Visibility sets:** `pluginToolExtensions` (`plugin_tools.dart`),
   `zeroCodeTools` (`zero_code.dart`), `debugOnlyTools`,
   `webUnsupportedTools`, `rasterTools`, `_nativeTools`. A merged tool is
   listed when **any** of its modes works; a mode that doesn't work for this
   app refuses with the reason (e.g. zero-code: "needs flutterpilot_sdk").
4. **Step runners:** the allowed-tool lists in `action_chain.dart`,
   `run_on_devices` (description lists the tools), `profile_action`, the leak
   `cycle` in `get_memory_details`. Grep the string lists near
   `ui_automation_tools.dart:130`, `:548`, `app_inspection_tools.dart:12`,
   `devtools_tools.dart:11`.
5. **Recorders:** `test_writer.dart` (generate_test turns recorded calls into
   Flutter test code: the new tool + mode must produce the same test code the
   old tool did; add a test), `verification.dart` (the list at line ~27),
   `batch_nudge.dart`, `scenario.dart`.
6. **Retired names inside steps:** steps arrays in `execute_action_chain`,
   `run_on_devices`, `profile_action` and `cycle` may come from an agent's
   memory or old docs. Translate retired names there to the new tool + mode
   (a `retiredTools` map in one place, e.g. `lib/src/retired_tools.dart`:
   `'swipe_widget': (tool: 'gesture_widget', set: {'gesture': 'swipe'})`).
7. **Retired names at the top level:** calling a removed tool today gets
   mcp_dart's unknown-tool error. Find out whether the server can answer it
   instead (custom `tools/call` handling in mcp_dart 2.4.x, or a fallback
   hook) with: `"swipe_widget was merged into gesture_widget: call
   gesture_widget(gesture: "swipe", ...)."` If mcp_dart offers no clean way,
   don't fork or monkey-patch it; write in the PR what it does today and
   leave it.
8. **Text the agent reads:** `serverInstructions`, the `flutterpilot_guide`
   prompt, descriptions of other tools that mention the old name (e.g. "use
   get_interactive_elements for the full list"), `CLAUDE.md`, `README.md`,
   `docs/*.md`, `skills/flutterpilot/SKILL.md`, `site/`.
9. **CLI:** `packages/flutterpilot_cli` (smoke, doctor, test commands) if
   they call tools by name.
10. **e2e:** `tool/e2e_test.dart` calls tools by name (164 checks). Update
    calls to the new names; don't delete checks. If the e2e test covered a
    behaviour of an old tool, the same check must exist for the new mode.
11. **Budgets:** lower the limits in `tool_registration_test.dart` to the new
    measured values plus a small margin (≤ 300 bytes), with a dated comment
    like the existing ones. Lower the tool-count limit (80) to the new count
    + 5.
12. **Docs:** regenerate `TOOLS.generated.md`; update ROADMAP §0's tool-count
    line and §4 with before/after bytes per profile.

Do one merge per commit, each passing `dart test`, so a bad one can be
reverted alone.

## Tests

- For each merged tool: a unit test per mode that the arguments reach the old
  implementation unchanged (follow existing tests for the old tools, e.g.
  `native_tools_test.dart`, `fleet_manager_test.dart`, `run_on_devices_test.dart`).
- Mode-only arguments in the wrong mode are refused (rule 4).
- `retiredTools` translation in steps: an `execute_action_chain` step with an
  old name runs the new tool.
- `test_writer_test.dart`: recorded new-tool calls generate the same Flutter
  test code as the old tool did (compare against a fixture of the old
  output).
- `tool_registration_test.dart` with lowered budgets passes.
- The fuzz test from task 02 covers the new tools automatically; it must
  pass.
- e2e on a device (README item 3), and `--zero-code` if C4/C5 merged; plus a field check on `../fp_lab_plain` that `get_widget_tree(semantics: true)` / the merged summary work without the SDK.

## Evals (blocking)

Run task 01's suite with `--repeat 3` and `--compare tool/eval/baseline.json`.

- Pass rate must not drop. A task that passed 3/3 at baseline must still pass
  3/3. If one regresses, look at the transcript: usually a description issue.
  Fix and re-run; if it can't be fixed, revert that merge.
- Report deltas: tool-list bytes (should drop), median calls per task,
  median input tokens per task.
- If the numbers improve, update `baseline.json` in this PR (same model) and
  say so.

## Don't

- Don't merge across annotation classes (rule 1), don't touch the SDK, don't
  rename tools that aren't being merged (renames alone cost every user's
  docs and memory, and buy nothing).
- Don't delete a capability. Every old call has an equivalent new call;
  list the mapping in the PR.
- Don't add new behaviour while merging.

## Done when

- [ ] Step-0 table in the PR with a verdict per candidate.
- [ ] Accepted merges implemented across all 12 places above.
- [ ] Old → new mapping table in the PR and in ROADMAP §4.
- [ ] Budgets lowered; `TOOLS.generated.md` regenerated; docs updated.
- [ ] e2e passes; evals not worse than baseline (numbers pasted).
