# FlutterPilot Development Tasks

This directory organizes all engineering tasks and sprints for FlutterPilot.

## Sprint Roadmap & Directory Structure

```
docs/tasks/
├── mcp-curation/           # Sprints 1–3: Curation, Robustness & Safety (Tasks 00–14) [COMPLETED]
└── mcp-excellence/         # Sprint 4: Protocol Excellence & Agent Superpowers (Tasks 15–20) [CURRENT / ACTIVE]
```

---

## 1. Completed Sprints: MCP Curation (Tasks 00–14)

See [mcp-curation/README.md](mcp-curation/README.md) for full context and details.

| # | Task | Summary | Result |
|---|---|---|---|
| 00 | Lab Apps | Multi-app test fixtures (`fp_lab_shop`, `fp_lab_notes`, `fp_lab_plain`) | ✅ Verified on Windows |
| 01 | Agent Evals | Runner in `tool/eval` for measuring agent task efficiency | ✅ Built & tested |
| 02 | Argument Robustness | Schema-driven coercion & fuzz testing | ✅ Merged (#124) |
| 03 | Surface Measurement | Tool list report & session call statistics | ✅ Merged (#124) |
| 04 | Tool Consolidation | 5 gesture tools into `gesture_widget` | ✅ Merged (#124) |
| 05 | Guidance Single Source | Unified `guidance.g.dart` & `SKILL.md` generator | ✅ Merged (#124) |
| 06 | Structured Results | `structuredContent` on verdict tools | ✅ Merged (#124) |
| 07 | Truncation Hints | Standardized cut-off reporting & hints | ✅ Merged (#124) |
| 08 | Core Tool Profile | `--tools core` (29 tools) for constrained LLM clients | ✅ Merged (#124) |
| 09 | Integration | Merged PRs #115–#123 into one branch | ✅ Merged (#124) |
| 10 | Windows Fixes | `launch_app`, POSIX paths in `init`, clean Windows tests | ✅ Merged (#124) |
| 11 | Round 1 Findings | Offline-over-mock, pre-connect log buffer, freshness test | ✅ Merged (#124) |
| 12 | Profile Re-check | Core set measured against real client limits | ✅ Merged (#124) |
| 13 | Round 2 Polish | Changelogs, parameterized route fix (#344), e2e delete retry (#340) | ✅ Merged (#124 into `main`) |
| 14 | Relaunch Safety | `prepareLaunch` order fix & build-wait recovery (#346) | ✅ Ready (PR #128 open & reviewed) |

---

## 2. Completed Sprint: MCP Excellence & Agent Superpowers (Tasks 15–20)

See [mcp-excellence/README.md](mcp-excellence/README.md) for full instructions and reports.

| # | Task File | Scope | Target | Status |
|---|---|---|---|---|
| 15 | [15-merge-and-sync.md](mcp-excellence/15-merge-and-sync.md) | Merge PR #128 and sync baseline | Ensure `main` is current, all 1000+ tests pass | ✅ Merged (#128) |
| 16 | [16-mcp-resources.md](mcp-excellence/16-mcp-resources.md) | Standard MCP Resources (`resources/list`, `resources/read`) | Expose `flutterpilot://app/*` and `flutterpilot://devices` for zero-token state checks | ✅ Merged (#129) |
| 17 | [17-curated-prompts.md](mcp-excellence/17-curated-prompts.md) | Curated MCP Prompts (`prompts/list`, `prompts/get`) | High-signal agent workflows (`debug_layout_overflow`, `verify_user_flow`, `create_integration_test`) | ✅ Merged (#130) |
| 18 | [18-structured-results-action-tools.md](mcp-excellence/18-structured-results-action-tools.md) | Machine-readable `structuredContent` expansion | Add `structuredContent` to `get_errors`, `get_app_summary`, `execute_action_chain`, `fill_form` | ✅ Merged (#131) |
| 19 | [19-mcp-protocol-inspector.md](mcp-excellence/19-mcp-protocol-inspector.md) | Automated MCP Protocol & Compliance Harness | Headless protocol adherence check across all endpoints & schema validity | ✅ Merged (#132) |
| 20 | [20-desktop-ci-parity.md](mcp-excellence/20-desktop-ci-parity.md) | CI Matrix Parity for Windows | Enable Windows unit/integration runs in GitHub Actions | ✅ Complete (PR #133 open & verified) |

---

## 3. Completed Sprint: Release Verification & Polish (Tasks 21–24)

See [release-prep/README.md](release-prep/README.md) for full instructions and reports.

| # | Task File | Scope | Target | Status |
|---|---|---|---|---|
| 21 | [21-merge-and-sync-ci.md](release-prep/21-merge-and-sync-ci.md) | Merge PR #133 and sync baseline | Ensure `main` is current, all 737+ tests pass | ✅ Merged in cabf803 |
| 22 | [22-publish-check-windows.md](release-prep/22-publish-check-windows.md) | Windows support for `tool/publish_check.dart` | `runInShell: true` for `Process.run('flutter', ...)`; all 15 packages publish dry-run clean | ✅ Merged in cd49a1e |
| 23 | [23-e2e-real-device-windows.md](release-prep/23-e2e-real-device-windows.md) | Real-device e2e tests on Windows | `e2e_test.dart -d windows` and `--zero-code -d windows` | ✅ Complete |
| 24 | [24-lab-apps-field-verification.md](release-prep/24-lab-apps-field-verification.md) | Lab app field verification (`../fp_lab_shop`) | Drive resources, prompts, and structured results against real app | ✅ Complete (PR #135 open & verified) |

---

## 4. Completed Sprint: Client Ergonomics & Advanced MCP Protocol (Tasks 25–27)

See [client-ergonomics/README.md](client-ergonomics/README.md) for full instructions and reports.

| # | Task File | Scope | Target | Status |
|---|---|---|---|---|
| 25 | [25-field-findings-remediation.md](client-ergonomics/25-field-findings-remediation.md) | Field findings remediation | Bridge call-logging (351) & `Type['key']` selector matching (352) | ✅ Merged in 5452753 |
| 26 | [26-dynamic-resource-templates.md](client-ergonomics/26-dynamic-resource-templates.md) | Dynamic Resource Templates | RFC 6570 templates for granular widget & route queries | ✅ Merged in 4682ae5 |
| 27 | [27-resource-subscriptions.md](client-ergonomics/27-resource-subscriptions.md) | Live Resource Subscriptions | Push updates (`notifications/resources/updated`) on state changes | ✅ Merged (#138) |

---

## 5. Completed Sprint: Release Readiness & Final Verification (Tasks 28–30)

See [release-final/README.md](release-final/README.md) for full instructions and reports.

| # | Task File | Scope | Target | Status |
|---|---|---|---|---|
| 28 | [28-merge-and-verify-subscriptions.md](release-final/28-merge-and-verify-subscriptions.md) | Merge PR #138 and sync baseline | Ensure `main` is current, all 1000+ tests pass | ✅ Merged in bffb9e2 |
| 29 | [29-full-publish-check.md](release-final/29-full-publish-check.md) | Workspace-wide pub publish dry-run | All 15 packages validate with 0 warnings | ✅ Complete (All 15 packages clean) |
| 30 | [30-release-changelog-audit.md](release-final/30-release-changelog-audit.md) | Changelog audit & release tagging | Version parity and changelog entries | ✅ Merged in e2c5984 |

---

## 6. Completed Sprint: Package Rebranding & Ergonomics (`fp_*`) (Tasks 31–33)

See [package-renaming/README.md](package-renaming/README.md) for full instructions and reports.

| # | Task File | Scope | Target | Status |
|---|---|---|---|---|
| 31 | [31-sdk-and-plugins-renaming.md](package-renaming/31-sdk-and-plugins-renaming.md) | Rename SDK (`packages/fp_sdk`) & 12 plugins (`packages/plugins/fp_*`) | `refactor/rename-sdk-plugins` | ✅ Merged (#140) |
| 32 | [32-server-renaming.md](package-renaming/32-server-renaming.md) | Rename MCP Server (`packages/fp_server`) & internal server imports | `refactor/rename-server` | ✅ Merged (#141) |
| 33 | [33-cli-and-workspace-tooling.md](package-renaming/33-cli-and-workspace-tooling.md) | Rename CLI (`packages/fp_cli`, dual `fp`/`flutterpilot` binary), update `publish_check.dart` & `melos.yaml` | `refactor/rename-cli-tooling` | ✅ Merged (#142) |

---

## Delegation & Review Workflow

- **Orchestration**: Managed by Antigravity (planning, review, prompt formulation).
- **Implementation**: Delegated to DeepSeek 4.1 Flash via OpenCode using copy-paste prompts.
- **Rules**: One task per branch/PR, format/analyze/test before PR, zero budget regressions.
