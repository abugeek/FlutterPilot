# Sprint 6: Client Ergonomics & Advanced MCP Protocol

Sprint started: 2026-10-15.
Orchestrator: Antigravity | Implementer: DeepSeek 4.1 Flash (OpenCode)

## Core Mission
Act on live lab findings to eliminate agent papercuts, expand MCP resource accessibility with dynamic URI templates, and enable live state notifications via resource subscriptions.

## Tasks and Execution Order

| # | Task | Description | Depends on | Branch |
|---|---|---|---|---|
| 25 | [25-field-findings-remediation.md](25-field-findings-remediation.md) | Merge PR #135, fix bridge call-logging (Finding 351) & `fill_form` Key matching in `Type['key']` selectors (Finding 352) | — | ✅ Merged in 5452753 |
| 26 | [26-dynamic-resource-templates.md](26-dynamic-resource-templates.md) | Dynamic MCP Resource Templates (`flutterpilot://app/widgets/{key}`, `flutterpilot://app/routes`) | 25 | ✅ Merged in 4682ae5 |
| 27 | [27-resource-subscriptions.md](27-resource-subscriptions.md) | Live Resource Subscriptions (`resources/subscribe` & push updates on reload/error/route) | 26 | ✅ Complete (PR #138 open & verified) |
