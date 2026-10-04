## Unreleased

- The tool list is 66 tools and about 9% smaller on the wire (a test holds
  it to a size budget). Breaking:
  - `get_capabilities` is `get_app_summary(setup: true)`.
  - `execute_action_chain` takes `steps` — tool calls, as in
    `run_on_devices`: `[{"tool": "tap_widget", "arguments": {"key": ...}}]` —
    and runs keys, scrolls, navigation and `wait_for` / `assert_widget`
    checks too, not only taps and text. Steps in the former
    `{"action", "target"}` shape are still read.
- Every tool has MCP annotations (read-only, destructive, idempotent), so
  clients can run reads without asking and ask before the tools that need
  `--allow-destructive`.
- The server sends `instructions` on connect: where to start and what not to
  repeat, for clients that load tool schemas on demand.
- Parameters have one name each, in camelCase: `clearFirst`, `sinceSeconds`,
  `statusFilter` (the former names still work), and schemas list `key` only
  (`target` still works). `get_shared_preferences(showSensitive)` is a
  boolean, `query_supabase_table(limit)` an integer; `table` and
  `query_firestore`'s `path` are required.

- `get_state(history: true)`: the last 50 Riverpod/Bloc changes, oldest
  first with times — old → new value, created, disposed — and the route
  changes between them; `clear: true` empties it.
- Tapping a disabled control names the form fields on screen that do not
  validate. `get_widget_properties` has `fieldError` / `invalid` for a form
  field; `get_interactive_elements` and `get_app_summary` mark fields that
  show an error.

- `inspect_widget(style: true)`: what a widget is drawn with — text size,
  weight, color, font and line height, paddings, fills, borders, corner
  radii, elevation — and the padding and fill around it.
- `set_app_settings(keyboardInset: 340)` lays the app out as with an open
  on-screen keyboard that tall (0 removes it), so a form that overflows above
  the keyboard is caught on desktop and web.
- `set_app_settings(windowSize:)` works on Windows: the app's viewport gets
  the size asked for. A window that stops at its minimum or the screen is
  reported as partly applied, not as done.
- `mock_http_response(error: "timeout" | "connection")` fails one URL with no
  response.

- `scenario` saves and loads local data too: the rows of the Drift and
  sqflite databases the app registered (one row per line in the file; each
  database replaced in one transaction) and Hive boxes of plain values.
  Tables over 1000 rows, tables with a credential-named column and virtual
  tables are left out and named. Loading them needs `--allow-destructive`.
- New `mock_platform_channel`: answers a plugin's method calls with a value
  or a PlatformException, delivers EventChannel events, and lists the calls
  the app made (and whether a plugin answered). A scenario carries the mocks
  across its hot restart.
- `scenario`, `generate_test` and `verify_feature` work on Windows: the
  app's folder was taken as `/D:/app`, which is not a path there.

- `get_app_summary` no longer prints a jank warning in a debug build, where
  most frames are over budget by nature and the line read as a defect on every
  call. It still does in a profile build, and `profile_frame_budget` answers
  in both.
- `set_app_settings(windowSize: "390x844")` resizes a macOS desktop app's
  window (its standard window, not a dialog in front) and reports the
  viewport the app then has; other platforms are refused with the reason.
- `navigate_to` waits (up to 1.5 s) for the page transition, so the next call
  sees the new page and not the one underneath.
- `hot_reload` on a sandboxed macOS app explains the permission the Flutter
  tool is missing instead of a bare failure.

## 0.1.0

- Initial release
- Core SDK with 20+ service extensions for AI-native Flutter introspection
- Widget tree capture with layout positions and source locations
- Screenshot capture as PNG
- Error interception and buffering
- Navigation stack tracking
- UI automation: tap, scroll, text entry
- Locale and theme override at runtime
- Performance metrics (FPS)
- Test recording and generation
- State inspection and injection via plugin system
