# 07 · Truncation hints: every capped list says what was cut

**Branch:** `fix/truncation-hints` · **Depends on:** nothing

## Goal

When a tool returns fewer items than exist, the response says so, with the
total and the exact argument to see more or narrow it. From the
`mcp-tool-curator` skill (response shaping): *"Showing 20 of 142 orders. Call
`search_orders(page=2)` for more."*

Without it, an agent reads a capped list as complete ("there are no errors
after 14:02") or re-calls with no change.

## Scope

Find every place a list is capped. Start with:

```bash
grep -rnE "sublist|take\(|\.clamp\(|limit|max[A-Z][a-zA-Z]*(Items|Lines|Entries|Chars)" packages/flutterpilot_server/lib
```

Known ones (verify each):

| Tool | Cap | Narrowing args it already has |
|---|---|---|
| `get_debug_logs` | `limit` default 100 (`app_inspection_tools.dart:554`, keeps the last N) | `level`, `query`, `sinceSeconds`, `logger`, `limit` |
| `get_network_logs` | check | `clear`, check others |
| `get_http_profile` | check | `url`, `id` |
| `get_errors` | deduplicated, check for a cap | `report` |
| `get_state(history: true)` | last 50 changes | `name`, `clear` |
| `get_widget_tree` | depth / node caps, check | `rootKey`, `diff` |
| `get_interactive_elements` / summary's element list | check | — |
| `exec_sql_query` | row cap, check | the SQL itself (`LIMIT`/`OFFSET`) |
| `get_hive_contents`, `get_shared_preferences`, `query_firestore`, `query_supabase_table` | check | check |
| action responses' widget-tree diff ("capped") | check | `get_widget_tree(diff: true)` |
| `get_http_profile(id)` bodies | 3000 chars | — (say the full size) |

For each, the response gets one line at the end (or start, if the tool's
format puts counts first) of this form:

```
Showing the last 100 of 342 log lines. Narrow with level, query, sinceSeconds or logger, or raise limit (max 500).
```

Rules:

- Only when something was actually cut. No line when the list is complete.
- Give the real total when known. When it isn't (e.g. a SQL query capped by
  the server), say "at least N+1" and how to page (`LIMIT/OFFSET`).
- Name only arguments the tool really has. Read its schema; don't invent
  `page`/`offset` arguments. If a tool has no way to see more and it matters,
  write it down in the PR as a candidate; don't add parameters in this task.
- Say which end was kept (last/first/newest) when it isn't obvious.
- One sentence, no emoji. Same wording pattern everywhere; put the formatter
  in one helper (`lib/src/truncation.dart`: `String? truncationNote({required
  int shown, int? total, required String what, required String how})`).

Also check that each cap's default/max is stated somewhere the agent sees it:
in the parameter description (`'Default 100.'`) is enough. Don't lengthen
descriptions beyond that.

## Tests

- `test/truncation_test.dart`: the helper (exact total, unknown total, no
  note when not cut).
- For each tool changed, a unit test where the source has more items than the
  cap (most tools read buffers you can fill in a test; follow existing tests
  for that tool, e.g. `state_history_test.dart`), asserting the note and the
  argument names in it. Where a tool can only be tested with an app, cover it
  in the manual check instead and say so.

Manual via `fp_bridge.dart` on `../fp_lab_notes`, which prints 150+ log
lines at startup and has a 250-row notes table (task 00):

```bash
curl -s localhost:8765 -d '{"name":"get_debug_logs","arguments":{"limit":5}}'
```

Paste the response showing the note. Do the same for `exec_sql_query`
(`SELECT * FROM notes`), `get_hive_contents`, and `get_state(history: true)`
after 60+ state changes (toggle a setting repeatedly with
`execute_action_chain`).

## Don't

- Don't change caps or defaults.
- Don't add pagination parameters.
- Don't add the note to responses that weren't capped.

## Done when

- [ ] Every capped list found is listed in the PR with: tool, cap, note added
      (or why not).
- [ ] Helper + tests; manual checks pasted; README Definition of done 1–4.
