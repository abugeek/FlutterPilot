# FlutterPilot Development Tasks
## Proposed work: MCP quality next
Read [MCP quality next](mcp-quality-next/README.md) for research findings,
priorities, dependencies, and eleven step-by-step implementation plans.
These are proposals only; implementation has not started.

## Completed work

The sprint task files that used to live here are done, merged and removed.

They were 8 sprints of work — 33 tasks in all, from an empty plan to a
released tool:

| Sprint | Tasks | Outcome |
|---|---|---|
| 1–3 | 00–14 | MCP curation: smaller tool surface, schema coercion, truncation hints, core profile, Windows fixes |
| 4 | 15–20 | MCP excellence: resources, prompts, structured results, protocol inspector, Windows CI parity |
| 5 | 21–24 | Release prep: publish-check on Windows, real-device e2e, lab-app field verification |
| 6 | 25–27 | Client ergonomics: field findings, dynamic resource templates, live subscriptions |
| 7 | 28–30 | Release final: publish dry-run across all 15 packages, changelog audit |
| 8 | 31–33 | Package rebranding to `fp_*` (`fp_sdk`, `fp_server`, `fp_cli`, 12 plugins) |

Every task's merge is in `main`'s history (PRs #115–#142).

## Where the history lives now

- **`ROADMAP.md`** — the durable record. Each section says what a task
  changed and why, and is the document to read before changing the surface.
- **Git history** — the task files themselves, their plans, measurements and
  field-test defect lists are recoverable from any commit before the cleanup:

  ```bash
  git log --oneline -- docs/tasks
  git show <commit>:docs/tasks/mcp-curation/03-measure-surface.md
  ```

## Adding new work

New tasks start as a fresh sprint folder here, one file per task, one
branch and PR per task. The rules the old sprints followed: format, analyze
and test before a PR, and no budget regressions (the tool count, the
guidance sizes and the per-session token cost are all guarded by tests).
