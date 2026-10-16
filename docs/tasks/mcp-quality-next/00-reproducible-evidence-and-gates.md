# 00 — Reproducible evidence and honest validation gates
## Status, priority, and dependencies
Proposed; P0; first task. Estimated 2–4 engineering days. Branch suggestion: `chore/mcp-quality-evidence`.
## Problem and expected benefit
Quality claims need trustworthy test exits, reproducible apps, and consistent units. A clean checkout currently cannot reproduce the agent suite without separate sibling repositories. Fixing these foundations prevents false-green validation and misleading context-budget comparisons.
## Verified starting points
- `melos.yaml` runs tests through `test -d test && (flutter test || dart test) || echo 'No tests'`. In a POSIX shell, test failure can reach the final successful echo; it also relies on shell syntax that is not portable to PowerShell.
- `.github/workflows/ci.yml` and `unit.yml` both run that aggregate command. Windows server/CLI jobs use direct `dart test`, which is a stronger gate.
- `packages/fp_server/tool/eval/run_evals.dart` locates lab apps only as siblings of the repository.
- The sibling lab `LAB.md` files still mention old package names and historical findings. Their presence does not prove their current builds or answers.
- `packages/fp_server/lib/src/tool_list_bytes.dart` and the eval `McpTool.listBytes` count string length. Existing tests call that measure bytes.
## Scope and non-goals
Repair validation infrastructure and record reproducible fixture identities. Do not launch apps against user data, import sibling repositories automatically, rewrite all CI workflows, or run paid evaluations.
## Step-by-step implementation
1. Record the current commit, Dart/Flutter versions, OS, and static profile report. Preserve the legacy size metric under an explicit name so an encoding correction cannot be misreported as tool growth.
2. Add a portable Dart package-test runner under `tool/`, using package metadata to select Dart versus Flutter exactly once. Discover test-bearing packages deterministically; skip only genuinely missing test directories and report why.
3. Use argument-vector subprocesses with explicit working directories. Handle Windows `.bat` launchers deliberately. Propagate nonzero exits; do not fall back from a failed Flutter test to Dart and then call it a pass.
4. Test the runner against disposable packages with a passing test, failing test, no test directory, nonexistent executable, and paths containing spaces. A deliberately failing package must make the aggregate command and CI step fail.
5. Wire the runner into the Melos test script. Preserve useful existing job names and required-check behavior. Run all package suites directly once to establish whether previously hidden failures exist; fix or track failures, never relabel them as skipped.
6. Add separate serialized-character and UTF-8-byte measurements, with fixtures containing Arabic text, emoji, and non-ASCII widget labels. Preserve the current model-facing projection without annotations as one metric and add full wire size as another; neither is a universal measure of what every client sends to its model.
7. Make reports and tests share measurement helpers where practical. Label estimated tokens as estimates. Introduce versioned baseline units rather than silently replacing existing numeric limits.
8. Define a fixture manifest, proposed at `packages/fp_server/tool/eval/fixtures/manifest.json`: app ID, repository/source location, exact revision, license, required plugins, build mode, supported devices, scenario checksum, seed version, and expected capabilities.
9. Choose the lightest reproducible fixture delivery after ownership review: pinned external public revisions with a verified bootstrap, or small repository-owned fixtures. Do not depend on `D:\projects\flutter\fp_lab_*` being present on another machine.
10. Add explicit fixture-root configuration and a read-only preflight that reports all missing/revision-mismatched inputs before launch. Reject dirty fixtures for baseline generation unless their content identity is recorded and the run is marked non-baseline.
11. Specify disposable storage and teardown for each fixture, including Drift/sqflite, Hive, preferences, and secure-storage test namespaces. Never clear global OS storage or the user's normal app data.
12. Reproduce setup in a temporary checkout on Windows and Linux. Update the eval README with exact prerequisites, bootstrap steps, supported targets, limitations, and measured units.
## Proposed file boundaries
- Modify `melos.yaml`, the two validation workflows only as needed, `packages/fp_server/lib/src/tool_list_bytes.dart`, `lib/src/tool_list_report.dart`, and evaluation measurement/configuration code.
- Extend `packages/fp_server/test/tool_list_report_test.dart`, `tool_registration_test.dart`, and `eval_runner_test.dart`.
- Add the portable runner, runner regression tests, and fixture manifest/bootstrap documentation.
- Do not change product tool names, schemas, or runtime semantics in this task.
## Validation sequence
1. Test the portable runner with intentionally failing disposable inputs; preserve the failure exit as evidence.
2. Run targeted measurement/eval tests, then direct package suites with the repaired aggregate command.
3. Run analysis and touched-file formatting; verify Windows process behavior and Linux CI.
4. Generate both legacy and new-unit profile reports, explaining every delta.
5. Run fixture preflight from a clean temporary checkout without local sibling-path assumptions.
## Acceptance criteria
- A failing test, missing required executable, or malformed fixture manifest cannot produce a green aggregate gate.
- No legitimate test suite is hidden behind a fallback invocation.
- New contributors can resolve fixture revisions and supported targets from committed metadata.
- Measurements distinguish characters, UTF-8 bytes, full-wire size, model-facing estimates, and billed usage.
- Existing budgets are preserved or explicitly migrated with reviewed evidence; no arbitrary relaxation.
- No paid API calls or mutation of existing sibling apps is necessary.
## Risks, decisions, and rollback
The repaired gate may expose old failures; report them before using the suite as a baseline. External fixtures may require access or licensing decisions; preflight must make that blockage explicit. If redistribution is not permitted, retain pinned external references and document access requirements.
Rollback the runner/report integration independently of fixture metadata. Preserve the original baseline record so later reports remain interpretable.
## Handoff
Leave runner exit evidence, fixture acquisition decisions, clean-checkout results, versioned measurements, and unresolved environment constraints. Task 01 may proceed on safety fixes even if external fixture access is blocked.
Task 09 reuses these fixture identities and measurement conventions for AOT/source startup trials. Do not combine process startup timing with task 00's static tool-list size measurements.
