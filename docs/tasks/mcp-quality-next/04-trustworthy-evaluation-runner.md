# 04 — Trustworthy, bounded, comparable agent evaluations
## Status, priority, and dependencies
Proposed; P0; after tasks 00–03. Estimated 3–5 days. Branch suggestion: `fix/eval-runner-trust`.
## Problem and expected benefit
The runner already measures model tool selection, but weak resets, incomplete comparisons, and unbounded I/O can invalidate results or waste paid calls. Make the measuring instrument trustworthy before optimizing tools against it.
## Verified starting points
The following source paths are relative to `packages/fp_server/`:
- `tool/eval/run_evals.dart` ignores errors from several reset helpers and checks reset routes with `summary.text.contains(route)`. Route `/` can match unrelated text.
- The runner enables `--allow-destructive` for scenario resets and shares that session with the model.
- `tool/eval/src/report.dart` includes infrastructure-error runs in aggregate denominators and does not reject a missing baseline task.
- Comparison checks model/device/app commits, not exact task definitions, scenarios, profile, protocol, or dirty fixture contents.
- `tool/eval/src/mcp_session.dart` requests `2024-11-05`, ignores non-JSON stdout, and drops structured results.
- `max_calls` is soft; the runner otherwise uses a turn cap. API request phases lack an explicit end-to-end evaluation deadline.
- Pricing uses model-name substring matching with a Sonnet fallback, which cannot establish an unknown model's price.
- Prompt caching already exists in `anthropic_runner.dart`; preserve it.
## Scope and non-goals
Improve the existing runner rather than replace it with a framework. Keep its task suite and cached API integration. Do not guess model availability/prices, add paid PR CI, or introduce a second provider here.
## Step-by-step implementation
1. Define versioned outcomes: passed, failed answer, infrastructure error, budget exhausted, and unsupported/skipped with reasons. Report counts separately; zero successful executions or only skips must not produce a successful benchmark.
2. Validate repeats, task IDs, fixture roots, output paths, deadlines, and limits. Unknown selected task IDs must not silently disappear.
3. Check fixtures, scenarios, capabilities, protocol, and credential presence before paid calls. Never print credentials.
4. Check every required reset operation. Declare optional unsupported resets explicitly; failure is not a valid starting state.
5. Read exact routes from structured summary content, not prose. Verify task-relevant initial facts such as mocks, settings, seed fingerprints, and storage counts where reliable.
6. Use fresh sessions per independent case or prove comprehensive reset/teardown. Separate trusted fixture setup from model access; restoration must not give the model unrestricted destructive privileges.
7. Add a policy wrapper between agent and MCP calls. Reject forbidden names/modes even if the setup session has stronger permissions; reuse task 01 effects and task 02 nested validation.
8. Preserve structured content, negotiated protocol, server identity, and listed schemas in the MCP adapter. Fail malformed stdout, reject pending requests on process exit, and make refresh/close ordering deterministic.
9. Add run/request deadlines, maximum calls/turns/output, bounded response bodies, and a suite spend limit with conservative estimates. A spend guard cannot undo an in-flight charge; document that limitation.
10. Preserve cache breakpoints and usage fields; test cache accounting with fake responses. If provider request code changes, load the Claude API skill and check current provider guidance before editing it.
11. Replace substring/fallback pricing with versioned explicit price configuration. Unknown pricing reports unknown cost and refuses cost-bounded paid execution until supplied; raw token counts remain available.
12. Record task-suite hash/IDs, fixture revisions/content hashes, scenario hashes, Flutter/Dart/SDK versions, platform/device/build mode, protocol, model, runner policy, profile/server args, guidance/tool-schema hashes, and pricing configuration.
13. Define compatibility: fixture/task/model/device/policy identities must match; candidate server revision and tool/guidance hashes are expected to differ and must be reported, not rejected.
14. Require identical task sets and compatible repeat policies. Missing tasks, infrastructure errors, empty runs, unknown versions, or unapproved skips make comparison incomplete/non-successful.
15. Compare correctness first, then calls, errors, token/cache usage, response units, time, and cost. Show per-task distributions/sample sizes; small-repeat results are screening, not statistical proof.
16. Write bounded, redacted artifacts and deterministic nonzero exits for regressions, infrastructure errors, and invalid configuration. Do not persist private arguments or unrestricted response bodies.
17. Document free preflight, fake-API tests, approved paid canary, baseline review, reproducibility, and budget limitations.
## Proposed file boundaries
- Extend `packages/fp_server/tool/eval/run_evals.dart` and `src/{agent,mcp_session,report,tasks,anthropic_runner}.dart`.
- Add reset/policy/configuration modules only where they remove duplication.
- Extend `packages/fp_server/test/eval_runner_test.dart`; add real-subprocess adapter tests.
- Version reports explicitly; old summaries need a legacy/incomparable marker.
## Validation sequence
1. Fake APIs/MCP clients cover failed resets, wrong routes, process death, list changes, malformed responses, budgets, and deadlines.
2. Test missing/extra tasks, changed scenarios/model/device, empty suites, and unknown prices.
3. Re-run valid legacy scoring and cache-accounting fixtures.
4. Execute a free deterministic fixture reset twice and prove identical initial facts.
5. Only after separate approval, run one paid case once; review spend before repetitions or baseline acceptance.
## Acceptance criteria
- Failed resets or missing tasks cannot yield a passing comparison.
- Exact structured route and fixture facts establish initial state.
- Infrastructure failures differ from model mistakes but still block benchmark acceptance.
- Setup privileges do not leak into model permissions.
- Every run is bounded, identifiable, and comparable; expected code changes remain comparable.
- Caching is preserved; unknown prices are not invented.
- Automated regression tests require no credentials or paid calls.
## Risks and rollback
Fresh sessions cost setup time; report setup separately. Stricter comparison may invalidate old summaries; retain them as history, not equivalent evidence. Keep report migration separate from policy changes where possible.
## Handoff
Provide free-gate results, reset evidence, report version, policy API, and paid approval procedure. Task 05 reuses this runner rather than creating another engine.
