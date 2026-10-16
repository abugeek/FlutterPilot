# MCP quality next: implementation roadmap
## Status and scope
Proposed on 2026-10-16. Planning only: no runtime code, dependencies, skills, CI configuration, sibling apps, or paid evaluations were changed or executed for this work.
Read this index, then the numbered task files. Approve execution separately. Numbering restarts for this new sprint; it does not reopen completed tasks 00–33 from earlier sprints.
## Why this sprint
The three suggested skill ideas are useful as engineering practices: research before design, independent protocol testing, realistic evaluations, and context-conscious tools. FlutterPilot already implements much of that advice. The next improvement should be stronger guarantees and measured usability, not a new server, a language rewrite, or another collection of overlapping tools.
The largest opportunities are:
- Trustworthy safety metadata and retry decisions, including tools with both observing and acting modes.
- Complete validation before a batch starts, not a refusal after earlier steps already changed the app.
- Independent official Inspector coverage in addition to the existing custom stdio tests.
- Reproducible, honestly scored evaluations with an actual baseline.
- Focused resource reads and tested machine-readable results.
- Tool and guidance changes justified by real task outcomes rather than tool-count targets alone.
- Measured AOT startup/readiness and a conditional analyzer-reuse investigation, not an assumed need for a new daemon.
## What already exists
- `packages/fp_server/lib/src/tool_profiles.dart`, `plugin_tools.dart`, and `zero_code.dart` curate tools by requested profile and app capabilities.
- `packages/fp_server/lib/src/arg_coercion.dart`, `param_aliases.dart`, and `test/tool_argument_fuzz_test.dart` cover normalization and many malformed inputs.
- `packages/fp_server/lib/src/tool_annotations.dart` supplies all four MCP annotations for every tool.
- Five fixed resources, two templates, subscriptions, and five prompts are implemented in `packages/fp_server/lib/src/resources.dart` and `prompts.dart`.
- Eight result families expose structured content through `packages/fp_server/lib/src/structured_results.dart`.
- `packages/fp_server/test/tool_registration_test.dart` guards descriptions, tool count, list size, and instruction size.
- `packages/fp_server/tool/eval/` has a 14-task Messages API evaluation runner, prompt caching, resets, usage reporting, and baseline comparison.
- Real-device e2e and Windows/Linux unit-test jobs already exist.
- `fp mcp install` already compiles the server by default. Reload diagnostics already prefer the supervised Flutter compiler log before one-shot analysis of changed files.
## Evidence collected
Research read source, tests, CI, current guidance, the roadmap, and the three sibling lab apps' `LAB.md` files. Those lab documents contain historical names and already-fixed findings; they are not current acceptance evidence.
Executed from the repository root: `dart run packages/fp_server/tool/tool_list_report.dart --json`.
The report returned:
- All registered tools: 63 tools; reported size 40,604; estimated tokens 10,151.
- SDK without plugins: 40 tools; reported size 28,848.
- SDK with Dio: 43 tools; reported size 30,488.
- Lab shop profile: 48 tools; reported size 33,601.
- Lab notes profile: 47 tools; reported size 32,387.
- Zero-code: 15 tools; reported size 9,681.
- Profile build: 45 tools; reported size 31,469.
These are static profile estimates, not observed live-client sessions. `tool_list_bytes.dart` currently measures `jsonEncode(...).length`, which is Dart string length, not UTF-8 bytes. The token figure is size divided by four, not billed token usage. Task 00 separates those units before comparisons.
`CLAUDE.md` currently says 67 tools; registration/report evidence says 63. Do not design against a remembered count.
No full test suite, application launch, real-device e2e, official Inspector session, or paid evaluation was run during planning. No paid baseline file was found; the evaluation README explicitly says its first paid run is pending.
## Source assessment
1. [Anthropic mcp-builder](https://github.com/anthropics/skills/tree/main/skills/mcp-builder): adopt research → design → implementation → review/evaluation. Its scaffolds target TypeScript/Python; retain FlutterPilot's Dart implementation. The current source balances workflow tools with API coverage rather than mandating merges.
2. [Anthropic evaluation guide](https://github.com/anthropics/skills/blob/main/skills/mcp-builder/reference/evaluation.md): adopt ten independent, read-only, stable, verified multi-step questions as a separate inspection suite. Keep the existing mutating workflow suite; it tests essential Flutter automation.
3. [Official MCP Inspector](https://github.com/modelcontextprotocol/inspector): adopt a pinned external CLI smoke gate. The `_Inspector` in the Dart protocol test is a custom client, not this package.
4. [Inspector CLI smoke guide](https://github.com/modelcontextprotocol/inspector/blob/main/docs/cli-smoke-testing.md) and [migration guide](https://github.com/modelcontextprotocol/inspector/blob/main/docs/v1-to-v2-migration.md): version-pin CLI syntax, argument encoding, exit-code expectations, and Node requirements. Upstream pages are mutable; record the exact package version and source revision when executing task 03.
5. [Published MCP tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools): annotations are advisory, output schemas are optional, and structured results need compatible client handling. Select protocol versions the installed Dart SDK actually supports.
The supplied names `mcp-inspector-tester` and `mcp-tool-curator` are treated as proposed practices, not verified installed skills or independently verified official packages. No skill installation is needed to execute this roadmap.
## Ordered implementation plans
1. [00 — Reproducible evidence and honest gates](00-reproducible-evidence-and-gates.md): portable fail-closed tests, reproducible fixture manifests, and clearly labeled baseline measurements. Priority P0; estimated 2–4 engineering days.
2. [01 — Truthful effects and retry safety](01-effects-and-retry-safety.md): conservative annotations, argument-aware effects, and explicit retry eligibility. Priority P0; estimated 2–4 days.
3. [02 — Nested argument contracts and preflight](02-nested-contracts-and-preflight.md): validate every step before execution and align fast/fallback paths. Priority P0; estimated 2–4 days.
4. [03 — Official Inspector interoperability](03-official-inspector-interoperability.md): pinned external client tests plus strict raw stdio validation. Priority P1; estimated 2–3 days.
5. [04 — Trustworthy evaluation runner](04-trustworthy-evaluation-runner.md): reliable resets, complete comparisons, bounded spend, and reproducible run identity. Priority P0; estimated 3–5 days.
6. [05 — Ten read-only evaluations](05-read-only-evaluation-suite.md): verified, independent, deterministic multi-step inspection cases and an approved baseline. Priority P1; estimated 3–5 days.
7. [06 — Focused and coherent resources](06-focused-resource-reads.md): eliminate unrelated VM reads and guard device/generation consistency. Priority P1; estimated 2–3 days.
8. [07 — Tested structured-result contracts](07-structured-result-contracts.md): local contract validation and carefully budgeted structured-output improvements. Priority P1; estimated 2–4 days.
9. [08 — Evidence-led curation and contributor workflow](08-measured-curation-and-contributor-workflow.md): measure selection and context cost, then improve descriptions/workflows and institutionalize the process. Priority P2; estimated 3–5 days.
10. [09 — Startup and MCP-readiness benchmarking](09-startup-readiness-benchmark.md): compare existing AOT/source launch paths, discovery, initialization, and first useful responses under controlled app states. Priority P1; estimated 2–3 days.
11. [10 — Conditional analyzer investigation](10-conditional-analyzer-investigation.md): measure the narrow reload-analysis fallback, inspect companion Dart tooling, and decide whether reuse is worthwhile. Priority P2; estimated 1–2 days for investigation; any daemon implementation requires separate approval/estimate.
Estimates are planning ranges, not commitments, and exclude external access delays and review. Each task is independently reviewable; approve only the next slice if a full sprint is too large.
## Dependencies and decision gates
The original workstream keeps order 00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08. Existing task numbers remain stable.
Task 09 follows 00 and 03 and supplies a startup baseline before task 08 performance experiments. Task 10 follows 09 and 01; it can investigate without waiting for paid model access and does not block unrelated correctness work.
One valid combined sequence is 00 → 01 → 02 → 03 → 09 → 10 → 04 → 05 → 06 → 07 → 08. Task 10 may be deferred if analyzer latency is not a current concern.
Task 00 captures the legacy static baseline. Tasks 00–05 establish a corrected pre-curation agent baseline. Safety/correctness changes do not wait for paid access.
Task 05 has a free deliverable first: fixtures, verified answers, policy tests, and deterministic checks. Its paid baseline is a separately approved milestone. Task 08 may prepare free reports and contributor guidance without a key, but must not claim model-usability improvements or ship evidence-dependent curation without the comparable paid runs.
Tasks 09–10 use local process/protocol measurements, not paid LLM runs. Their measured engineering-latency conclusions do not depend on the paid baseline. Neither a startup-order change nor a persistent analysis process is automatically authorized by an investigation result.
Take another controlled measurement after each later runtime change. Never compare different fixture contents, task definitions, models, device classes, or protocol policies as if the tool change were the only variable.
No child agents are proposed for this planning work. Sequential implementation minimizes overlap in server registration, protocol tests, evaluation code, and generated guidance.
## Shared implementation contract
- All future paths in the task files are proposals, not existing interfaces. Confirm them before coding.
- In grouped source lists, abbreviated companion filenames inherit the last explicit directory; `server` means `packages/fp_server`. Implementation steps refer to proposed future work, not work authorized by these documents.
- Use one focused branch/PR per approved task. Do not change sibling repositories or move their code without ownership/license review.
- Prefer targeted `dart analyze` and `dart test` in `packages/fp_server`; use `dart test` for `fp_cli` and `flutter test` for SDK/plugins. The current aggregate Melos test command is not trustworthy until task 00.
- Format only touched Dart files. Run generated guidance/tools freshness tests and relevant profile budgets on every tool-surface change.
- Runtime changes require `dart run tool/e2e_test.dart -d windows` from `packages/fp_server` on this workstation; existing CI covers other declared devices. Report unavailable platforms as untested, not passed.
- Retain zero-code, core/all, static/dynamic listing, debug/profile-build, plugin gating, and fleet behavior unless a separate compatibility decision says otherwise.
- Keep logs and evaluation artifacts free of credentials and private app contents. Use synthetic fixtures and metadata-only measurements by default.
- Paid calls require explicit spend approval and environment-provided credentials. Never commit keys or raw private traces.
- No new MCP tool, silent budget increase, automatic baseline acceptance, or success claim without evidence.
- Changes to agent text go in `packages/fp_server/guidance/`; regenerate outputs rather than editing generated files.
## Not proposed
No Dart-to-TypeScript/Python migration; no blanket ban on arrays/maps; no universal tool-count target; no premature tool renaming/removal; no HTTP transport merely to exercise Inspector HTTP; no new paid CI dependency; no three overlapping contributor skills by default; no unconditional persistent analyzer or promised near-zero startup.
## Existing command reference for later execution
These commands are implementation handoff instructions, not checks already run for this planning work, except the static report explicitly recorded above.
1. Repository root: `dart run packages/fp_server/tool/tool_list_report.dart --json` captures static profile measurements.
2. Working directory `packages/fp_server`: `dart analyze`, then targeted `dart test test/tool_registration_test.dart test/tool_argument_fuzz_test.dart test/mcp_protocol_compliance_test.dart`.
3. In the same directory: `dart test test/eval_runner_test.dart test/mcp_resources_test.dart test/structured_results_test.dart` covers the existing evaluation/resource/result foundations without paid API calls.
4. After authoritative guidance edits, in `packages/fp_server`: `dart run tool/generate_guidance.dart`. After tool-contract changes: `dart run tool/generate_tools_doc.dart`.
5. In `packages/fp_server`: `dart test test/guidance_generated_test.dart test/guidance_names_test.dart test/tools_doc_generated_test.dart` verifies generated content and referenced names.
6. In `packages/fp_server`: `dart test` runs the full server suite. Run directly until task 00 makes the aggregate runner trustworthy.
7. For approved runtime changes on this Windows workstation, in `packages/fp_server`: `dart run tool/e2e_test.dart -d windows`. This launches disposable apps; verify prerequisites/storage isolation first.
8. In each affected SDK/plugin directory: `flutter test`; in `packages/fp_cli`: `dart test`. Use the repaired aggregate gate from task 00 for the complete monorepo.
9. Repository root: `git --no-pager diff --check` checks tracked whitespace changes. Check newly created files separately before staging; do not stage/commit solely to run validation.
The Inspector wrapper, free evaluation preflight, suite selectors, and portable aggregate runner are proposed deliverables, so this document deliberately does not invent commands for them. Each implementing task must document its verified invocation.
## Completion evidence
Every implemented task should leave targeted test results, before/after measurements where relevant, compatibility notes, limitations, and rollback instructions in its PR. Update `ROADMAP.md` with verified outcomes only after implementation. These documents themselves are not evidence that the proposed improvements work.
