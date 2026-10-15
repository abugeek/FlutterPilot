# 13 · Finish: fold round 2 into the integration PR, changelogs, two leftover bugs

**Branch:** `integration/mcp-curation` (add to it; PR #124) · **Depends on:**
PRs #125, #126, #127 as they are now

Written 2026-10-14 after reviewing round 2. Rounds 1–2 are good work; this is
what stands between them and `main`.

## Review results (for context)

- Tasks 10, 11, 12 (#125–#127) each branched from `integration/mcp-curation`
  separately. Merged together on top of it (10 → 11 → 12) they conflict only
  in docs: `docs/field-test-findings.md` (both 10 and 11 edit the #326–#330
  rows and add a section after #340) and `ROADMAP.md`.
- On that combined tree: server `dart test` 683 pass / 0 fail, format and
  analyze clean (checked by the reviewer). So the code fits together; only the
  docs need a careful hand merge.

## 1. Merge #125, #126, #127 into `integration/mcp-curation`

So the maintainer merges **one** PR (#124) and nothing else.

- `git merge --no-ff origin/fix/windows`, then `origin/fix/round1-findings`,
  then `origin/fix/core-profile`, into `integration/mcp-curation`.
- `docs/field-test-findings.md`: keep **both** sides' information in each
  row. #326/#327 are "fixed (task 10)", #328 "won't fix (mcp_dart, task 11)",
  #329/#330/#332/#334/#335/#338 as task 11 wrote them. Keep task 10's
  "round 2" section (#341–#343) and add task 11's #344 to it, in number
  order. No row may lose its notes.
- `ROADMAP.md`: keep every bullet from both sides; §0 stays one accurate
  state line; §4 numbering stays consecutive.
- After the merges: no conflict markers anywhere
  (`git grep -nE "^(<<<<<<<|=======|>>>>>>>)"` returns nothing outside
  code that legitimately contains them).
- Comment on #125, #126, #127: "Merged into #124". Don't close them; the
  maintainer will.

## 2. Changelogs (missing for both rounds)

The repo keeps an `## Unreleased` section at the top of each package's
`CHANGELOG.md` (see `packages/plugins/flutterpilot_dio/CHANGELOG.md`,
`packages/flutterpilot_cli/CHANGELOG.md`). Rounds 1–2 changed what users see
and added almost nothing there. Add, in the existing style (one bullet per
change, what the user notices, the tool or flag name first):

`packages/flutterpilot_server/CHANGELOG.md`:
- **Breaking:** `swipe_widget`, `drag_widget`, `pinch_zoom`, `focus_widget`,
  `set_slider_value` are now `gesture_widget(gesture: swipe|drag|pinch|focus|slide)`.
  Old names still work as steps inside `execute_action_chain`,
  `run_on_devices`, `profile_action` and a leak `cycle`; called directly they
  are unknown tools. Put this bullet first.
- `--tools core|all`.
- `structuredContent` on `assert_widget`, `wait_for`,
  `verify_feature(finish: true)`, `run_on_devices`.
- Arguments of steps run by other tools are brought to their schema types
  (`"5"` → 5, a JSON-string array → the array), or refused with an example.
- Capped lists say how much was cut and how to see the rest.
- `get_debug_logs` includes output from before FlutterPilot connected.
- `get_app_summary` / `get_errors` mark errors from before the last reload.
- Windows: `launch_app` starts `flutter` (and `.bat`/`.cmd` launch commands),
  stops the whole process tree on relaunch; app file paths printed with `/`.
- The call log records which tools were listed.

`packages/flutterpilot_cli/CHANGELOG.md` (check what is already there):
`stats` (several logs, never-called tools, p50/p90, `--json`),
`mcp install --tools core`, `doctor` shows the profile, `init --local` writes
POSIX paths, `smoke` text-scale pass (already there: keep).

`packages/plugins/flutterpilot_dio/CHANGELOG.md`: `simulate_network`
conditions now apply to mocked requests too (offline fails a mocked URL;
slow conditions delay a mocked answer); mocks are kept.

Don't bump any `version:` (RELEASING.md: versions move together at release
time).

## 3. Two leftover bugs from the findings file

### #344 — `smoke` crashes on a route with path params

`routePaths` (CLI, `smoke`) reads the JSON from the first `{` of the
`get_navigation_stack(routes: true)` answer; on a parameterized route the
answer has `Path params: {id: 0}` first, so decoding fails, `routePaths`
returns a `const []`, and `routes.insert(0, start)` throws `Cannot add to an
unmodifiable list`.

Fix both halves: parse the `Routes:` part specifically (or ask for a form
that is unambiguous, if the tool already offers one), and never return an
unmodifiable list that a caller mutates. Test with the exact answer text from
a parameterized route. Field check: `smoke -d windows --no-launch` on
`../fp_lab_shop` while it sits on `/product/1` completes and reports.

### #340 — `e2e_test.dart --zero-code` fails in cleanup on Windows

Every check passes, then deleting a scratch folder throws because a just
killed server process still holds it (`errno = 32`). Fix in
`tool/e2e_test.dart`: wait for the killed process to exit (`await
process.exitCode` with a timeout) before deleting its working folder, and
make the deletes retry briefly on Windows (a small helper: up to ~5 s, then
report but don't crash; the run's result is the checks', not the cleanup's).
Then `dart run tool/e2e_test.dart --zero-code -d windows` must end with
`E2E passed` and exit 0.

### Flaky text entry on Windows (new finding, from the review)

The reviewer ran `e2e_test.dart -d windows` twice on the combined tree
(integration + #125–#127). Run 1: 5 checks failed. Run 2, same code: all 179
passed. The 5 failures all lost typed text:

- `enter_text(TextField['Name'], "Pilot")` passed, then `press_key(backspace)`
  answered `Field: "" (cursor at 0)` instead of `"Pilo"`; the next three key
  checks failed the same way (the field had started empty).
- `generate_test`'s generated integration test failed at step 4 ("expect
  text", the greeting built from the entered name).

The likeliest cause is the app window losing OS focus during the run (the
desktop was in use); not confirmed. Do this:

1. Try to reproduce: run the e2e and, while the key-editing checks run, click
   another window. Also try `enter_text` + `press_key` through the bridge on
   `../fp_lab_shop` with the app window in the background.
2. If it reproduces, find where the text goes (focus lost → field
   unfocused → editing value reset?) and make `enter_text` / `press_key`
   either work with the window in the background (CLAUDE.md promises
   "Background window is fine") or say in the response that the field lost
   focus, instead of reporting success.
3. Either way, add finding #345 to `docs/field-test-findings.md` with what you
   found. If it doesn't reproduce in 3 tries, record it as "seen once, not
   reproduced" with the failing output above.

## 4. Verify the final branch

On `integration/mcp-curation` after 1–3, paste in #124's description (replace
its verification section, keep the merge table and extend it with rows for
#125–#127):

1. format / analyze / test for `flutterpilot_server`, `flutterpilot_cli`,
   `flutterpilot_sdk` (`flutter test`), `flutterpilot_dio` (`flutter test`):
   zero failures expected (the SDK's 2 pre-existing `hasFlag` deprecation
   infos are fine; say so).
2. Generators produce no diff (`generate_guidance.dart`,
   `generate_tools_doc.dart`).
3. `e2e_test.dart -d windows` and `--zero-code -d windows`: both `E2E passed`,
   exit 0.
4. Bridge checks, one line of output each: `launch_app(relaunch: true)` on
   `../fp_lab_shop`; `tools/list` counts default and `--tools core` for shop
   and notes; offline-over-mock on shop; `smoke` on a parameterized route.
5. Evals: run only if `ANTHROPIC_API_KEY` is set **and** the maintainer
   approved the cost; otherwise "evals not run (no key)".

Update #124's title to say it now carries rounds 1 and 2.

## Don't

- No new features, no refactors beyond the two bug fixes.
- Don't force-push. Don't merge #124 or close any PR.
