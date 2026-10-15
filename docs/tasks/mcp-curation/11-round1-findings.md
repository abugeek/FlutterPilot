# 11 · Fix what round 1's field test found

**Branch:** `fix/round1-findings` · **Base:** `integration/mcp-curation` until
it merges, then `main` · **Depends on:** 09

Each item below is a finding from round 1 (numbers from
`docs/field-test-findings.md` after task 09). For each one: **reproduce it
first** on a lab app through `fp_bridge.dart` and paste the reproduction. If it
doesn't reproduce, say so with the calls you made and skip it. Then fix it,
with a unit test, and paste the same calls after the fix. One commit per item.

## 1. `simulate_network(offline)` doesn't affect mocked requests

A test that mocks the API and then goes offline still gets mocked answers, so
"what does the app show offline?" can't be tested without clearing mocks
first. The tool's description says it affects every Dio request.

Decision (recommended in review; ask the maintainer if they haven't
confirmed it): **offline wins over a mock.**
A mock stands in for the server; offline means no request reaches any
server. So under `offline`, a mocked URL fails the same way an unmocked one
does. `slow_3g`/`fast_4g` add their delay to a mocked answer too. Mocks are
kept, not cleared: going back to `normal` brings the mocked answers back.

Where: the Dio plugin (`packages/plugins/flutterpilot_dio`), which applies
both mocks and conditions. Check the order inside its interceptor. This is a
plugin change, not an SDK protocol change (no extension name or parameter
changes); if it would need one, stop and ask.

Then rewrite task 01's `shop_offline` eval task back to the simple form (no
"clear the mocks first") and re-verify its answer by hand.

## 2. `get_network_logs(clear: true)` silently accepted (#330)

The tool has no `clear` parameter, yet the call was accepted and ignored.
`_tool()`'s unknown-argument check should refuse it (field test #280 fixed
exactly this once). Find why it didn't: the plugin-tool path
(`_registerAppTool`), the alias groups in `param_aliases.dart` (`clear`
might be in a group that is "known" because of another property), or the
report is wrong. Fix the cause; add a fuzz-test case if the task 02 fuzz test
missed it, and explain why it missed it.

Also decide whether `get_network_logs` *should* have `clear: true`, like
`get_debug_logs` and `get_http_profile`. The eval runner had to work around
its absence. If the Dio plugin's extension already supports clearing, add the
parameter (it's a list-bytes cost; measure it). If it would need a new
extension, don't; note it.

## 3. `get_debug_logs` misses output from before the connection (#329)

`get_app_summary`'s "Recent Console Logs" shows startup lines (it reads the
SDK's own buffer), `get_debug_logs` doesn't (it reads the server's buffer,
filled after connecting). Two tools disagreeing about the same logs makes an
agent distrust both. Make `get_debug_logs` include what the SDK buffered
before the connection (merge by time, dedupe against what the server
captured). If the app has no SDK (zero-code), say in the response that output
from before the connection is not available. Also check `clear: true` on
`get_debug_logs` returns a clear confirmation, not an empty result (#329's
second half).

## 4. Fixed error still listed in the summary (#334)

After a fix and `hot_reload`, `get_app_summary`'s "Uncaught Errors" still
lists the old error until a full restart, while `get_errors(report: true)`
already says there is none. Make the summary follow the same rule as
`get_errors`: errors from before the last reload or restart are marked as
"before the last reload" or dropped. Pick one, say why in the PR, and make
both tools use the same rule (one function).

## 5. `smoke` doesn't test larger text (#332)

`flutterpilot smoke` audits each route at the current text scale only. Add a
second pass at `textScale: 2` (via `set_app_settings`) by default, with
`--no-text-scale` to skip it. Restore the scale afterwards even if the run
fails. Report findings per pass ("at text scale 2: ..."). Field check:
`smoke -d windows` on `../fp_lab_shop` now reports the `/checkout` overflow
(planted defect 1).

## 6. A freshness test for `TOOLS.generated.md`

`main` had a stale `TOOLS.generated.md` for days (missing
`launch_app(waitSeconds)`). Add a test like task 05's guidance freshness
test: generate the doc in memory from the registered tools and compare with
the committed file; on mismatch, fail with the command to run. If generation
needs a server process (`generate_tools_doc.dart` starts one), factor the
markdown building into a function the test can call with
`toolListJson()` instead.

## 7. Two small ones

- `wait_for`'s structured `timedOut` (task 06) is computed by copying the
  SDK's default timeouts (3000 / 5000 ms) into the server. If the SDK's
  response carries its timeout or a timed-out flag, read that instead. If
  not, add a comment at the SDK's defaults pointing at the server's copy and
  vice versa, so a change to one is noticed. Don't change the SDK protocol.
- `tap_widget`/`hot_restart`-style wrong names at the top level (#328) can't
  be answered with a hint because mcp_dart answers unknown tools itself
  (task 04 confirmed). Nothing to do; mark #328 "won't fix (mcp_dart)" in
  the findings file.

## Done when

- [ ] Each item: reproduction, fix, unit test, after-fix calls (or "did not
      reproduce" with evidence).
- [ ] `shop_offline` eval task simplified and re-verified.
- [ ] README Definition of done items 1–5, 7; findings marked fixed.
