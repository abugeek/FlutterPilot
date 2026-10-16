# 08 — Evidence-led curation and a repeatable contributor workflow
## Status, priority, and dependencies
Proposed; P2; after tasks 00–07. Estimated 3–5 days. Branch suggestion: `perf/evidence-led-mcp-curation`.
Free reports/guidance can proceed without paid access. Model-usability claims and evidence-dependent changes require comparable approved runs from tasks 04–05.
Use task 09's startup baseline to separate launch/discovery latency from model/session costs. Task 10's analyzer decision is optional evidence, not a prerequisite for unrelated curation.
## Problem and expected benefit
Batching, concise descriptions, profiles, capability gating, resources, and budgets already exist. Improve task success and total session cost rather than maximizing merges or chasing a universal tool count. Give contributors one lightweight Dart-specific process.
## Verified starting points
- `packages/fp_server/lib/src/tool_profiles.dart` selects 29 core names partly from existing eval expectations.
- `tool_list_report.dart` models profiles but does not prove live-client visibility.
- `tool_registration_test.dart` already guards count, size, descriptions, annotations, and instructions.
- `packages/fp_server/guidance/` generates instructions, prompt guidance, and `skills/flutterpilot/SKILL.md`.
- `docs/ARCHITECTURE.md` shows obsolete architecture and tap responses advising redundant re-queries.
- `docs/INDEX.md` links to nonexistent `TOOLS.md` and has obsolete categories/counts.
- `CLAUDE.md` says 67 tools; current registration/report says 63.
- Metadata-only `CallLog` sequences do not prove what context each client sends to its model.
## Scope and non-goals
Run controlled curation experiments and establish the contributor recipe. Do not remove useful primitives for lower counts, merge distinct permission classes, install redundant skills, or expand telemetry into private payload collection.
## Step-by-step implementation
1. Freeze accepted task/fixture/model/device/protocol/profile identities. Repeat an unchanged-server control if environment/API drift is plausible.
2. Compare static reports and actual connected listings for SDK/no-plugin, shop, notes, zero-code, debug/profile, core/all, and static/dynamic modes.
3. Separate wire discovery, actual model tool definitions, instructions, requested prompts, attached resources, results/images, cache usage, billed tokens, calls, and time. Resources/prompts avoid tool definitions but are not globally free context.
4. Use synthetic-fixture traces and metadata-only stats to find redundant follow-ups, wrong-tool choices, unavailable selections, repeated refusals, and large responses.
5. Rank at most three concrete hypotheses by benefit/risk: clearer tool distinctions, compact missing examples, or guidance avoiding redundant post-action reads.
6. Prefer description/example changes, existing batching, or scoped resources over new tools. Preserve meaningful structured values and useful primitives.
7. Change one hypothesis at a time. Run free schema/protocol/effect/contract/guidance/budget gates before paid comparisons.
8. Run inspection and workflow suites with identical identities/repeat policies. Report per-task correctness, calls/errors, token/cache distributions, response sizes, latency, and cost.
9. Predeclare adoption criteria: no safety regression, no newly failing reliable task, no aggregate correctness regression, target-metric gains beyond ordinary run noise, and no unreviewed budget growth. If sample size is inadequate, collect approved repetitions or label inconclusive.
10. Reject cosmetic count reductions harming discovery/recovery. Core changes require documented unsupported tasks and restart/profile guidance.
11. Keep renames/removals outside default scope. If evidence demands one, separately approve migration, compatibility/refusal guidance, generated refs, versioning, and client tests.
12. Change authoritative guidance sources and regenerate. Keep instructions, prompts, and existing skill consistent without stuffing all detail into always-loaded instructions.
13. Add `docs/MCP_DEVELOPMENT.md` as a proposed contributor recipe: research, tool/resource/prompt selection, argument/effect/result contracts, test commands, Inspector, eval authoring, budgets, security, compatibility, and required evidence.
14. Add minimal PR review integration linking existing checks and recording effect/schema/fixture/migration decisions. Prose is not a substitute for automated gates.
15. Correct relevant stale architecture/tool references in `docs/ARCHITECTURE.md`, `docs/INDEX.md`, and `CLAUDE.md`; reference generated inventory instead of scattered fragile counts.
16. An installable contributor skill is a separate later decision. Use the create-skill skill if approved, refer to the recipe, and keep it distinct from the generated end-user skill. Avoid three competing maintenance procedures.
17. Record accepted/rejected experiments in the durable roadmap. Refresh baselines only through review; retain unfavorable old evidence.
## Proposed file boundaries
- Limit candidate changes to evidence-selected descriptions/schemas/profiles and `packages/fp_server/guidance/`.
- Extend existing profile/registration/guidance tests rather than competing inventories.
- Add contributor recipe and minimal review integration; correct directly relevant docs.
- Any telemetry change preserves metadata-only privacy and opt-out.
## Validation sequence
1. Establish control report and connected-profile evidence.
2. Run free gates for each isolated candidate.
3. Obtain spend approval, run matching before/after suites, and review task-level results.
4. Regenerate guidance/tools docs and test stale/retired references.
5. Run runtime e2e when behavior changes; verify a real-client task.
## Acceptance criteria
- Every accepted change has a hypothesis and comparable evidence.
- Lower context cost never excuses correctness/safety/recovery regression.
- Profiles/capability gating are tested live, not only inferred.
- Guidance, inventory, architecture, and contributor docs agree.
- New contributors can follow one Dart-specific recipe using existing tools.
- Blocked/inconclusive paid evidence is labeled; no percentage gains are invented.
## Risks and rollback
Model variability, cache warmth, fixture changes, and API versions can masquerade as design gains. Record identities/repeat controls. Retain field checks and both suites against benchmark overfitting.
Revert individual experiments without reverting safety fixes, contracts, or the recipe.
## Handoff
Leave accepted/rejected findings, comparable reports, limitations, and the updated contributor process. Use it for future tool work instead of reopening completed sprints.
Keep startup and analyzer latency conclusions separate from paid agent-task outcomes: faster local diagnostics do not by themselves prove better tool selection or fewer model tokens.
