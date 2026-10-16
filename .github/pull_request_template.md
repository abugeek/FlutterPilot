## Description
Brief description of changes.

## Type
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation

## Checklist
- [ ] `dart format` applied to the touched files
- [ ] `dart analyze --fatal-infos` passes
- [ ] Tests added/updated
- [ ] Tests pass (`melos run test`)
- [ ] Documentation updated if needed

## MCP surface changes
Skip this section if nothing under `packages/fp_server/lib/src/tools/`,
`packages/fp_server/guidance/`, `packages/fp_server/tool/eval/` or the tool
profiles changed. The recipe is `docs/MCP_DEVELOPMENT.md`; automated gates live
in `packages/fp_server/test/` (registration, tool-list report, effect policy,
structured results, action-chain preflight, resources, generated-doc freshness)
and the official Inspector wrapper.

- [ ] No tool/resource/prompt/guidance/profile changed

If it did change, fill in each decision (a "yes" needs the test or evidence
named beside it):
- [ ] `TOOLS.generated.md` regenerated from the registration
      (`dart run packages/fp_server/tool/generate_tools_doc.dart`)
- [ ] **Effect/replay**: read / mutating / replay-safe decided; every new
      `ext.…` call added to the `effect_policy.dart` inventory
- [ ] **Argument contract**: schema and/or composite preflight updated; nested
      paths still reported (`steps[i].arguments.…`)
- [ ] **Result contract**: `structuredContracts` + a `validStructuredFixtures`
      entry; `status` separates refused/unavailable from a false predicate
- [ ] **Guidance**: regenerated (`dart run tool/generate_guidance.dart`) and the
      client-usage change that justified it is named:
- [ ] **Fixtures**: none changed, or the manifest revision/scenario hashes were
      updated in the same commit (note approval)
- [ ] **Migration/compatibility**: additive, or a retired-name translation +
      refusal guidance + regenerated references + version bump + client test
- [ ] **Budgets**: unchanged or lowered — never raised to fit this change
- [ ] **Evidence**: hypothesis, targeted metric, and comparable before/after —
      or an explicit `inconclusive` label when a paid run was not approved
- [ ] Outcome recorded in `ROADMAP.md`
