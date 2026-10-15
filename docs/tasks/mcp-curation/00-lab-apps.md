# 00 · Lab apps: test apps outside the repo, with known answers

**Where:** outside the FlutterPilot repo, as siblings:
`D:\projects\flutter\fp_lab_shop`, `D:\projects\flutter\fp_lab_notes`,
`D:\projects\flutter\fp_lab_plain` (paths below are relative to the
FlutterPilot repo root: `../fp_lab_shop` etc.). **Depends on:** nothing ·
**Blocks:** everything else.

## Why

Every other task tests against real apps, the way earlier field tests used
`../hn_reader`, `../notes_app`, `../pos_lab`. The examples folder in this repo
is not used for this work (don't modify `examples/`). Purpose-built apps give:

- **known answers**: defects planted on purpose, so an eval task like "which
  screen overflows at text scale 2" has exactly one right answer;
- **coverage of every tool family**: plugin-gated tools only appear when the
  app uses that plugin;
- **stability**: no dependence on a public API's data (network is mocked by
  scenarios or fails deterministically).

## Rules for all three apps

- Each is its own git repository (`git init`, commit as you build), never
  inside the FlutterPilot repo, never pushed anywhere unless the maintainer
  asks.
- Created with `flutter create --platforms=windows,web,android,ios,macos <name>`
  (all platforms so they work on the maintainer's other machines too).
  Primary device on this machine: **Windows desktop** (`-d windows`; adb is not
  installed here).
- Wired to **this checkout** of FlutterPilot (not pub.dev) with the CLI, the
  way the e2e test does it:
  `dart run <repo>/packages/flutterpilot_cli/bin/flutterpilot.dart init --local <repo>`
  run inside the app (check the CLI's actual entry point and `--local`
  semantics in `packages/flutterpilot_cli/lib/src/commands/init_command.dart`
  first). `fp_lab_plain` is **not** wired (zero-code).
- Keep each app small: a few hundred lines per app, plain code, no
  generated-code packages beyond what Drift needs.
- Each app has a `LAB.md` with: what it covers, how to run it, every planted
  defect with its exact location and the answer an agent should find. This
  file is for humans and for writing eval tasks. The eval agent can't read
  files (task 01 gives it only MCP tools), so it doesn't leak answers.
- Network: base URL `https://api.fp-lab.invalid` (the `.invalid` TLD never
  resolves). Without mocks every request fails with a connection error,
  always the same way. Scenarios (`flutterpilot/scenarios/*.json` in the app)
  carry the HTTP mocks that make screens show data.

## App 1: `fp_lab_shop` (main eval app)

Riverpod 3, go_router, Dio, sqflite, shared_preferences (latest stable
versions that `flutterpilot init` supports; check `packages/plugins/*/pubspec.yaml`
ranges).

Screens and routes:

| Route | Screen | Data |
|---|---|---|
| `/` | Product list (GET `/products`) with search field (GET `/products?q=`) | Dio |
| `/product/:id` | Detail, "Add to cart" | Dio GET `/products/:id` |
| `/cart` | Cart lines, quantity +/- , total | sqflite table `cart_items` |
| `/checkout` | Form: name, email, phone (≥ 9 digits), "I accept the terms" checkbox, "Place order" disabled until valid | POST `/orders` |
| `/orders` | Past orders | sqflite `orders` |
| `/settings` | Dark mode switch, text size slider, currency dropdown | shared_preferences |

Planted defects (each documented in `LAB.md` with file:line):

1. `/checkout` overflows horizontally at text scale 2 (a `Row` with two
   fixed-width children + text).
2. The favourite `IconButton` on product cards has no tooltip or label
   (screen reader can't name it).
3. A promo banner text on `/` below WCAG contrast (light grey on white).
4. GET `/products/0` handling throws an uncaught `RangeError` in app code.
5. Server error path: a 500 on `/products` shows the text "Could not load
   products" and a "Retry" button.
6. Search race: responses can arrive out of order; the list shows the stale
   result (for the `mock_http_response` `delayMs` race).
7. A listener added in the detail screen's `initState` and never removed
   (memory leak check finds it after open/back cycles).
8. A deliberately expensive build in the cart total (e.g. sorting a large
   list on every build) so `profile_action` shows an app function on top.
9. Opening detail makes exactly **2** requests (product + related products),
   a stable number for an eval question.

Scenarios to commit in the app: `eval_base` (route `/`, 8 products mocked
with fixed ids/names/prices, empty cart, default settings),
`cart_with_items` (3 cart rows), `server_down` (500 on `/products`). Make
them with the tools (`mock_http_response`, then `scenario(save: ...)`) and
check the files by eye.

## App 2: `fp_lab_notes` (plugin coverage, big data)

Bloc (`flutter_bloc`), Drift, Hive CE, flutter_secure_storage, connectivity
plugin (whatever `flutterpilot init` supports for each; check the plugin
packages).

- Notes list (Drift table `notes`, **seeded with 250 rows** on first run, so
  list caps and truncation notes trigger), note editor, tags (Hive box with
  plain values), "lock" PIN stored in secure storage, an offline banner
  driven by connectivity.
- A settings bloc with a few states for `get_state(history: true)`.
- Planted: one Drift table with > 1000 rows (`events`, for scenario's
  "tables over 1000 rows are not saved" message); a log line printed 150+
  times on startup (for `get_debug_logs` truncation).

Scenario: `notes_base`.

## App 3: `fp_lab_plain` (zero-code)

Plain `flutter create` counter app plus one small form and a second route
(Navigator 1.0). **No flutterpilot_sdk.** Used to check zero-code listing
(task 04 C4/C5 merges, task 08 core ∩ zero-code) and the fuzz/robustness
behaviour without the SDK.

## Verification (this task's "done")

For each app, paste in the task report:

1. `flutter analyze` clean, `flutter run -d windows` reaches the first screen.
2. `dart run <repo>/packages/flutterpilot_cli/bin/flutterpilot.dart doctor`
   inside the app: no errors (for `fp_lab_plain`: says zero-code).
3. Through the bridge (from the FlutterPilot repo root, app running):

   ```bash
   dart run packages/flutterpilot_server/tool/fp_bridge.dart -p ../fp_lab_shop --allow-destructive
   ```

   ```bash
   curl -s localhost:8765 -d '{"name":"get_app_summary","arguments":{"setup":true}}'
   ```

   The plugins you added are registered; the tool count matches what task
   03's profiles predict.
4. Every planted defect found once with the tool meant to find it (call +
   relevant response lines in `LAB.md`'s "Verified" column).
5. `flutterpilot smoke -d windows` in `fp_lab_shop`: exits 1, and its report
   lists defects 1–3. Paste the report summary.
6. Each scenario loads (`scenario(load: ...)`) and the screen shows the
   mocked data.

## Don't

- Don't put these apps (or any build output) in the FlutterPilot repo.
- Don't change FlutterPilot code in this task. If wiring an app exposes a
  FlutterPilot bug, write it down (it becomes a field-test finding in a later
  PR) and work around it in the app if you can.
- Don't use real credentials or real backends anywhere.
