# FlutterPilot MCP Tools

Generated from the running server registration. Do not edit manually.

Tool count: 67

Size of the whole list as an agent receives it (names, descriptions, schemas): 42477 bytes. An app is shown only the tools that work for it.

`native_*` tools are listed to agents only when the connected app runs on an iOS simulator and `idb` (or `xcrun`, for `native_screenshot`) is installed, or on Android and `adb` is found (PATH, ANDROID_HOME or the SDK folder).

## `connect_app`

Connects to running app via VM service URI, or auto-discovers from workspace if omitted.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `uri` | string | no | Optional VM Service URI (e.g. "http://127.0.0.1:12345/abcdefg=/"). If omitted, auto-discovers. |

## `list_connected_devices`

Lists the Flutter apps FlutterPilot knows (one per device: iOS, Android, web, desktop): platform, app, whether it runs fp_sdk, and which one is active. Every tool targets the active device.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `register_device`

Registers a running app in the fleet by id and VM service URI from flutter run. Re-registering updates its URI after restart.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | A short name, e.g. "iphone", "pixel", "web". |
| `uri` | string | yes | The VM service URI (http://… as flutter run prints it, or ws://…/ws). |

## `run_on_devices`

Runs steps in parallel across registered devices, comparing step verdicts and final screen states.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `steps` | array | yes | Tool calls run in order on each device, e.g. [{"tool": "tap_widget", "arguments": {"key": "Log in"}}]. Tools: assert_widget, enter_text, execute_action_chain, fill_form, gesture_widget, mock_http_response, mock_platform_channel, navigate_to, press_key, scroll_into_view, simulate_network, tap_widget, toggle_checkbox, wait_for. |
| `devices` | array | no | Registered device names (list_connected_devices); default: all of them. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{devices: [{id: string, passedSteps: int, totalSteps: int, failedStep?: int, route?: string, errors: int, reached: bool}], same: bool, status?: "ok"|"partial"|"refused", reason?: string}`

## `switch_device`

Makes a registered device the active one: every tool call after this targets it. See list_connected_devices for the names.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | The name of a registered device. |

## `get_errors`

Recent uncaught exceptions with source file:line and layout culprits. report:true returns crash report; clear:true empties buffer; query filters errors.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `report` | boolean | no | Return the latest crash report instead of the list. |
| `query` | string | no | Substring filter for error message or stack frames. |
| `clear` | boolean | no | Clear the recorded error buffer. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{hasErrors: bool, count: int, errors: [{kind: "exception"|"overflow", message: string, location?: string, beforeReload: bool}], status?: "ok"|"unavailable", reason?: string}`

## `get_debug_logs`

Captured logs (print, debugPrint, log). Filter by query/level, or wait with waitFor; clear:true empties buffer.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `level` | string: debug \| info \| warning \| warn \| error | no | Minimum log severity filter. |
| `query` | string | no | Only messages containing this. |
| `waitFor` | string | no | Poll until a log message containing this appears. |
| `timeoutMs` | integer | no | Timeout in ms for waitFor (default 3000). |
| `sinceSeconds` | integer | no | Only the last N seconds. |
| `limit` | integer | no | Default 100. |
| `logger` | string | no | Only this logger (partial match), e.g. "debugPrint", "stdout". |
| `clear` | boolean | no | Clear captured debug logs after returning. |

## `profile_frame_budget`

Frame timings and jank diagnostics (p50/p90/p99, UI/raster). reset:true clears recorded frame window.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `reset` | boolean | no | Clear recorded frame timings buffer. |

## `get_rebuild_stats`

Rebuild counts of the app's widgets with source location. First call starts counting; second call reports counts.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `query` | string | no | Widget type or key substring filter. |
| `reset` | boolean | no | Reset rebuild counts and start a new observation window. |
| `minCount` | integer | no | Minimum rebuild count to report (default 1). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{started?: bool, sinceMs: int, totalRebuilds: int, widgetTypes: int, rebuilds: [{widget: string, rebuilds: int, createdAt?: string}], moreTypes?: int, hints: [string]}`

## `tap_widget`

Taps widget by key/text/selector (auto-scrolls) or x/y. Reports route, diff and tappable elements.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector, text or icon. |
| `mark` | integer | no | Set-of-Mark id. |
| `identifier` | string | no | Semantics id. |
| `semanticsId` | integer | no | SemanticsNode id. |
| `text` | string | no | Visible text. |
| `type` | string | no | Widget type. |
| `x` | number | no | X in logical px. |
| `y` | number | no | Y in logical px. |
| `gesture` | string: tap \| double \| long \| secondary | no | Default tap. |
| `durationMs` | integer | no | Long-press ms (600). |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |
| `quickSettle` | boolean | no | <=400ms settle. |
| `settleTimeoutMs` | integer | no | Settle timeout ms. |

## `enter_text`

Types text into field by key/selector/label or focused field. Pass submit:true for Enter.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | Text ("" clears). |
| `key` | string | no | Key/label (omit for focused). |
| `mark` | integer | no | Set-of-Mark id. |
| `identifier` | string | no | Semantics id. |
| `clearFirst` | boolean | no | Clear first (default true). |
| `submit` | boolean | no | Press Enter. |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |

## `press_key`

Presses key on focused widget (enter, tab, escape, arrows, or "back" to pop).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | Key name ("enter", "back", "tab", "escape", arrow, char). |
| `modifiers` | array | no | shift, ctrl, alt, meta. |
| `count` | integer | no | Repeat count (1–20). |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |

## `gesture_widget`

Drives widget with swipe, drag, pinch, focus or slide. Reports screen and route changes; supports waitFor, failureKey, and anyOf.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `gesture` | string: swipe \| drag \| pinch \| focus \| slide | yes | swipe, drag, pinch, focus, or slide. |
| `key` | string | no | Key or selector. Omit for focus to unfocus. |
| `direction` | string: up \| down \| left \| right | no | Direction for swipe. |
| `distance` | number | no | Distance in logical pixels. |
| `fromKey` | string | no | Drag source key/selector. |
| `toKey` | string | no | Drag target key/selector. |
| `scale` | number | no | Pinch scale (>1 zoom in, <1 zoom out). |
| `identifier` | string | no | Semantics id. |
| `x` | number | no | Center x for pinch, with y. |
| `y` | number | no | Center y for pinch, with x. |
| `value` | number | no | Slider value for slide. |
| `waitFor` | string | no | Widget key/selector to wait for. |
| `failureKey` | string | no | Fast-fail key (e.g. error banner). |
| `anyOf` | array | no | Candidate keys to await. |
| `timeoutMs` | integer | no | Timeout for waitFor (default 5000). |

## `scroll_into_view`

Scrolls until widget is visible; tap:true taps it. fraction (0-1) instead jumps a list there the way a scrollbar thumb drag does and times the frames (key: the list or a widget in it; default: the largest list on screen).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or text. |
| `fraction` | number | no | Jump to this share of the list: 0 top, 1 end. |
| `tap` | boolean | no | Tap once visible. |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |

## `toggle_checkbox`

Toggles Checkbox, Switch or Radio; value sets state idempotently.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or row label. |
| `value` | boolean | no | Target state (no-op if already set). |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |

## `fill_form`

Fills multiple form fields and optionally submits.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fields` | object | yes | Map of field key/selector to value (string or bool). |
| `submitWith` | string | no | Button key/selector to tap after filling. |
| `submit` | boolean | no | Tap primary button. |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{submitted: bool, filledCount: int, totalFields: int, failedField?: string, validationErrors?: [string], status?: "ok"|"unavailable"}`

## `wait_for`

Waits for widget key, anyOf, route, animations, state, or frames.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or text. |
| `anyOf` | array | no | Wait until any listed key appears. |
| `failureKey` | string | no | Fast-fail key that aborts wait if seen. |
| `gone` | boolean | no | Until key is gone. |
| `route` | string | no | Target route. |
| `animations` | boolean | no | Wait for animations. |
| `state` | string | no | Provider or bloc name. |
| `expectedValue` | string | no | Expected state substring. |
| `frames` | integer | no | Frames to pump (1–120). |
| `timeoutMs` | integer | no | Timeout ms (default 5000). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{met: bool, waitedMs: int, timedOut: bool, condition: "key"|"route"|"state"|"frames"|"animations"|"none", route?: string, status?: "ok"|"unavailable"|"refused"}`

## `audit_screen_health`

Audits layout overflows, tap targets, contrast, labels, tokens, keyboard, or viewports.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `routes` | array | no | Routes to sweep. |
| `category` | string: all \| overflow \| a11y \| contrast \| tokens | no | Category filter (default all). |
| `query` | string | no | Filter by widget, key, file, or text. |
| `designQuality` | boolean | no | Audit 4/8dp spacing, typography, and tokens. |
| `viewports` | array | no | Viewports (phone, tablet, desktop, WxH). |
| `keyboardInset` | number | no | Keyboard height in dp to test and restore. |
| `restore` | boolean | no | Restore initial state afterwards (default true). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{requested: int, visited: int, audited: int, failed: int, skipped: int, findings: {overflows: int, tapTargets: int, unlabeled: int, lowContrast: int, readingOrderJumps: int}, restored: bool, incomplete: bool, loading: bool, status?: "ok"|"partial"|"unavailable", reason?: string}`

## `execute_action_chain`

Runs steps in order, stopping on failure; returns step outcomes and final screen state.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `steps` | array | yes | Ordered list of {tool, arguments} steps. |
| `exportAsTest` | boolean | no | Write executed flow as an integration test. |
| `testName` | string | no | Generated test name. |
| `testFilePath` | string | no | Output test file path. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{passed: bool, completedSteps: int, totalSteps: int, failedStep?: int, failureReason?: string, status?: "ok"|"refused"|"unavailable"}`

## `native_screenshot`

Captures full simulator screen including native OS alerts, keyboard, and dialogs outside Flutter.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_tap`

Taps simulator/device screen at x/y points for native dialogs/alerts.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `x` | number | yes | X in points. |
| `y` | number | yes | Y in points. |
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_text`

Types text into focused native field on simulator/device (for alerts/dialogs).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | Text to type. |
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_button`

Presses a simulator hardware button (HOME, LOCK, SIDE_BUTTON, BACK, etc.).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `button` | string: APPLE_PAY \| HOME \| LOCK \| SIDE_BUTTON \| SIRI \| BACK \| WAKEUP | yes | Hardware button to press on simulator/device. |
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_describe_screen`

Describes native OS elements (system dialogs, permissions). Filter elements by query substring.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `query` | string | no | Filter native elements by label or role substring. |
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_open_app`

Brings app back to foreground on simulator/device, resuming state and execution.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `navigate_to`

Navigates to route or deep link (go_router or Navigator).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `route` | string | yes | Route or deep link URL. |
| `action` | string: go \| push \| replace | no | Default "go" (push/replace use go_router). |
| `deepLink` | boolean | no | Open as OS deep link. |
| `waitFor` | string | no | Key/text to await. |
| `failureKey` | string | no | Fast-fail key. |
| `anyOf` | array | no | Keys to await. |
| `timeoutMs` | integer | no | Wait timeout ms (5000). |
| `pathParams` | object | no | Path params map. |
| `queryParams` | object | no | Query params map. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{requested: string, resolvedUri?: string, current?: string, waitRequired: bool, waitStatus?: "found"|"missing", completed: bool, uncertain: bool, status?: "ok"|"refused"|"unavailable"}`

## `get_navigation_stack`

Navigation stack and route locations. waitForRoute polls until matching route appears; routes/history add router table.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `routes` | boolean | no | Include go_router's configured routes. |
| `history` | boolean | no | Include recent route changes (go_router). |
| `query` | string | no | Filter routes or history by substring. |
| `waitForRoute` | string | no | Poll until current route equals or contains this. |
| `timeoutMs` | integer | no | Timeout in ms for waitForRoute (default 3000). |

## `set_app_settings`

Sets theme, locale, text scale, orientation, window size, or debug overlays.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `reset` | boolean | no | Restore defaults and clear overlays. |
| `theme` | string: light \| dark | no | App brightness. |
| `locale` | string | no | BCP-47 tag or "system". |
| `textScale` | number | no | Text scale factor. |
| `keyboardInset` | number | no | Keyboard height in dp (0 clears). |
| `orientation` | string: portrait \| landscape \| all \| auto | no | Phones. |
| `windowSize` | string | no | WIDTHxHEIGHT. |
| `debugPaint` | boolean | no | Show layout bounds. |
| `repaintRainbow` | boolean | no | Show repaint rainbow. |
| `slowAnimations` | boolean | no | 5x slow animations. |

## `crawl_app`

Crawls reachable screens via list rows and tabs; reports route graph and health issues, then restores start route.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxScreens` | integer | no | Stop after this many taps (default 15). |
| `restore` | boolean | no | Go back to the starting route at the end (default true). |
| `audit` | boolean | no | Include detailed health findings for screens with issues. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{screens: [{route: string, overflows: int, a11y: int}], edges: [{from: string, to: string, via: string}], taps: int, restored: bool}`

## `capture_screenshot`

Screenshot of the app screen (or specific widget with key). Supports scale, format, and labeled Set-of-Mark.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Optional widget key to crop screenshot to. |
| `format` | string: png \| jpeg \| webp | no | Image encoding format (default: png). |
| `scale` | number | no | 0.2–1.0 (default 0.5). |
| `labeled` | boolean | no | Overlay numbered badges on interactive elements. |
| `quality` | integer | no | JPEG compression quality 10-100 (default: 80 for jpeg). |

## `compare_screenshot`

Visual diff vs baseline or previous frame. Supports key cropping and changed bounds.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | no | Baseline name. |
| `key` | string | no | Widget key to crop comparison to. |
| `comparePrevious` | boolean | no | Compare against previous frame. |
| `save` | boolean | no | Save current screen as baseline. |
| `threshold` | number | no | Allowed diff % before failing (default 1.0). |
| `scale` | number | no | 0.2–1.0 (default 0.5). |
| `ignoreStatusBar` | boolean | no | Ignore status bar. |
| `ignoreKeys` | array | no | Widget keys to mask out during diffing. |

## `get_widget_tree`

App widgets on screen with keys, text, selectors and bounds. diff:true returns changes since last call.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `diff` | boolean | no | Return structural tree diff since last call. |
| `rootKey` | string | no | Subtree key or selector. |
| `subtree` | string | no | Subtree root key. |
| `query` | string | no | Filter tree nodes matching key, type, or text. |
| `maxDepth` | integer | no | Default 50. |
| `compact` | boolean | no | false keeps unkeyed layout wrappers (default true). |
| `collapse` | boolean | no | Collapse repeated sibling widgets. |

## `get_interactive_elements`

Interactive controls currently on screen with type, label, key, and bounds. query filters by key/label.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `types` | array | no | Optional filter for widget types (e.g. ["ElevatedButton"]). |
| `query` | string | no | Optional filter matching key, label, or text. |
| `collapse` | boolean | no | Collapse repeated list items to save tokens (default true). |

## `get_app_summary`

Running app summary: route, viewport, focus, tappable elements, errors, health, and logs.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `setup` | boolean | no | Also server/app setup: connection, registered plugins, SDK capabilities. |
| `query` | string | no | Filter tappable elements and logs by substring. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{connected: bool, device?: string, platform?: string, route?: string, errorCount: int, buildMode?: string}`

## `get_widget_properties`

Widget state: type, text, isEnabled, isChecked, isFocused, bounds, slider values, and validation errors.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key or selector of the widget. |
| `keys` | array | no | Batch of keys or selectors to inspect together. |

## `inspect_widget`

Returns widget source file:line, AST, bounds, ancestors, layout, style, or properties.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or visible text. |
| `x` | number | no | X in logical px, with y. |
| `y` | number | no | Y in logical px. |
| `layout` | boolean | no | Include ancestor constraints/sizes and overflow cause. |
| `style` | boolean | no | Include text style, padding, fills, borders, and radii. |
| `properties` | boolean | no | Include semantic properties (isEnabled, text, etc.). |
| `ast` | boolean | no | Include constructor AST snippet and offsets. |
| `file` | string | no | Source file for AST lookup. |
| `line` | integer | no | 1-based line for AST lookup. |
| `column` | integer | no | 1-based column for AST lookup. |

## `get_semantics_tree`

Screen reader semantics tree (VoiceOver/TalkBack): label, value, hint, role flags, and rect. Supports query filter and maxDepth.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `query` | string | no | Substring filter for node label, hint, value, or identifier. |
| `maxDepth` | integer | no | Default 50. |

## `hot_reload`

Hot reloads edited .dart files into running app (keeping state). restart:true resets state; waitForSettled checks settle/errors; waitFor awaits widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `restart` | boolean | no | Hot restart instead of hot reload. |
| `waitForSettled` | boolean | no | Wait for frame settlement and verify 0 new errors (default true). |
| `waitFor` | string | no | Optional widget key/text to wait for after reload. |
| `settleTimeoutMs` | integer | no | Screen settle timeout in ms (default 2000). |

## `launch_app`

Builds and launches app on a device, awaits first frame, and connects. Pass relaunch:true to force rebuild.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `device` | string | no | flutter run -d: "macos", "chrome", an id. |
| `target` | string | no | Entrypoint (default lib/main.dart). |
| `mode` | string: debug \| profile | no | Default debug. |
| `project` | string | no | App folder, if several. |
| `relaunch` | boolean | no | Stop the running app and rebuild. |
| `waitSeconds` | integer | no | Return early if still building (default 600). |

## `get_state`

Values of Riverpod providers and Blocs/Cubits. Filter with name or query; history:true lists state and route changes with timestamps.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string: riverpod \| bloc | no | Only this kind. |
| `name` | string | no | Only names containing this. |
| `query` | string | no | Substring search across state values and names. |
| `history` | boolean | no | List the last 50 state and route changes with timestamps. |
| `clear` | boolean | no | Empty the history after returning it: do that before an action to see only its effects. |

## `set_state`

Sets Riverpod provider or Bloc/Cubit state in memory: name + value, or several via states. Names come from get_state; type is inferred for bool/number/String/List/Map.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | no | Provider or bloc name from get_state (e.g. "counterProvider", "CounterCubit#2"). |
| `value` | any | no | New value: plain (42, true, "text") or JSON. |
| `states` | object | no | Several at once: {"counterProvider": 10, "themeProvider": "dark"}. |
| `type` | string: riverpod \| bloc | no | Only needed if the name is not observed yet. |

## `get_network_logs`

Dio network requests (including mocks). Filter by query, method, errorsOnly.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `query` | string | no | URL or message filter. |
| `url` | string | no | Alias for query. |
| `method` | string | no | HTTP method (GET, POST). |
| `errorsOnly` | boolean | no | Only failed requests (status >= 400 or error). |
| `limit` | integer | no | Max entries to return (default 50). |

## `get_hive_contents`

Keys and values of registered Hive boxes. Supports box and substring query filter.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `box` | string | no | Optional Hive box name to filter. |
| `query` | string | no | Substring filter for keys and values. |

## `exec_sql_query`

Run read-only SQL (SELECT, PRAGMA, EXPLAIN) or inspect schema (omit sql). query filters tables or rows.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `sql` | string | no | SQL statement; omit for the schema. |
| `database` | string | no | Database name, only needed when the app registers several. |
| `query` | string | no | Substring filter for table names or row content. |
| `limit` | integer | no | Max rows or tables to return (default 50, max 200). |

## `get_shared_preferences`

Reads SharedPreferences. Filter with key or query; sensitive keys are redacted.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Specific key to read. |
| `query` | string | no | Key or value substring filter. |
| `showSensitive` | boolean | no | Reveal sensitive values. |

## `set_shared_preference`

Writes a SharedPreferences key (string, int, double, bool, stringList). remove:true deletes key; confirm "CLEAR_ALL" clears all.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The key. Omit only to clear all (with confirm). |
| `remove` | boolean | no | Delete the key. |
| `confirm` | string | no | "CLEAR_ALL" to clear every preference (no key). |
| `value` | string | no | "true"/"false", "42", or for a stringList a JSON array of strings. |
| `type` | string: string \| bool \| int \| double \| stringList | no | Default "string". |

## `simulate_network`

Simulates network conditions (slow_3g, offline, chaos errorRate/statusCode, delayMs) across http, dart:io and Dio; restore:true clears.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `condition` | string: normal \| slow_3g \| fast_4g \| offline | no | Network profile preset (default: normal). |
| `delayMs` | integer | no | Up to 60000. |
| `errorRate` | number | no | Chaos failure rate 0.0-1.0 (e.g. 0.5 for 50% drops). |
| `statusCode` | integer | no | HTTP status code on failure, e.g. 500, 503, 404. |
| `restore` | boolean | no | Restore normal network conditions. |

## `mock_http_response`

Mocks Dio responses/errors, batch mocks, or exports recorded traffic.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `urlPattern` | string | no | URL substring to match. |
| `clear` | boolean | no | Clear mock for urlPattern (or all). |
| `statusCode` | integer | no | HTTP status (default 200). |
| `body` | string | no | JSON response body string. |
| `delayMs` | integer | no | Response delay in ms. |
| `error` | string: timeout \| connection | no | Simulate timeout or connection failure. |
| `mocks` | array | no | Batch of mock definitions. |
| `fromRecorded` | boolean | no | Export mocks from recorded Dio logs. |
| `apply` | boolean | no | Install exported mocks immediately. |

## `call_custom_tool`

Runs a tool the app registered with FlutterPilot.registerCustomTool(). Without name, lists them.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | no | The custom tool name. Omit to list the tools. |
| `params` | object | no | The custom tool's parameters. |

## `mock_platform_channel`

Mocks native platform MethodChannels (method + result/error) or EventChannels (event). clear:true resets; omit lists.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `channel` | string | no | Channel name, e.g. "plus/battery". |
| `method` | string | no | Method name, e.g. "getBatteryLevel". |
| `result` | any | no | Result JSON (null for void; {"$bytes": "<b64>"}). |
| `error` | string | no | Fail with PlatformException code. |
| `errorMessage` | string | no | With error. |
| `event` | any | no | Event to deliver on EventChannel: any JSON. |
| `clear` | boolean | no | Remove mocks of channel or all. |

## `assert_widget`

Checks screen in milliseconds; error is a failed assertion. Single check (text, key, enabled, or type+count) or batch via asserts:[...].

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | no | Expected text. |
| `exact` | boolean | no | Exact text match. |
| `key` | string | no | Key, selector or label. |
| `enabled` | boolean | no | Expect enabled/disabled. |
| `type` | string | no | Widget type (e.g. ListTile). |
| `count` | integer | no | Expected count of type. |
| `asserts` | array | no | Batch of checks: [{text, exact, key, enabled, type, count}]. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{passed: bool, check: "text"|"key"|"enabled"|"disabled"|"count"|"none"|"batch", expected?: string, found?: int, reason?: string, total?: int, passedCount?: int}`

## `get_memory_details`

Heap usage and allocation profiles. classes:true lists top classes; diffBaseline:true isolates growth; route/cycle checks leaks.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `classes` | boolean | no | List top classes by heap usage. |
| `diffBaseline` | boolean | no | Show instance/byte growth since baseline. |
| `resetBaseline` | boolean | no | Capture fresh baseline for diffBaseline. |
| `limit` | integer | no | Number of classes (default 30). |
| `route` | string | no | Canary route for leak checks. |
| `cycle` | array | no | Steps returning to start. |
| `times` | integer | no | Leak check rounds (default 5). |

## `profile_action`

CPU and frame profiler for an action or duration: reports hot functions, timings, and janky frame widget rebuilds.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `tool` | string | no | The action tool to run, e.g. "tap_widget" or "execute_action_chain". |
| `arguments` | object | no | Its arguments, e.g. {"key": "Load more"}. |
| `durationMs` | integer | no | Keep sampling this long after the action returns, for work that lands later (a network response, an animation). Without tool: how long to sample (default 1000, max 10000). |

## `get_http_profile`

dart:io HTTP requests (HttpClient, package:http, Dio). Filter by query, method, errorsOnly, or inspect id in full.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `clear` | boolean | no | Clear recorded list. |
| `limit` | integer | no | Default 50. |
| `query` | string | no | URL substring filter. |
| `url` | string | no | Alias for query. |
| `errorsOnly` | boolean | no | Only failed requests (status >= 400). |
| `method` | string | no | HTTP method (GET, POST). |
| `statusFilter` | integer | no | Only this status code. |
| `id` | integer | no | Request #number for full details. |

## `apply_patch_and_verify`

Surgically patches widget in source (wrap, unwrap, replaceCall), hot-reloads, audits health, and auto-rolls back if reload fails.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or visible text of the widget. |
| `file` | string | no | File in the app, e.g. "lib/main.dart". |
| `line` | integer | no | 1-based line of the widget. |
| `column` | integer | no | 1-based column where the call starts. |
| `wrapWith` | string | no | Widget to wrap target in (e.g. "Expanded", "SingleChildScrollView", "SafeArea", "Padding"). |
| `unwrap` | boolean | no | Remove this widget, replacing it with its child argument. |
| `replaceCall` | string | no | Direct replacement snippet for the constructor call. |
| `waitFor` | string | no | Optional widget key to wait for on screen after reload. |
| `timeoutMs` | integer | no | Timeout for waitFor in ms (default 3000). |
| `patches` | array | no | Batch of patch objects to apply atomically in 1 reload. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{patchCount: int, fileCount: int, reloaded: bool, rolledBack: bool, overflowCount: int, accessibilityIssueCount: int}`

## `generate_test`

Records/replays user interactions and writes executable integration_test files (start:true begins, replay:true runs live, name writes and runs test).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `start` | boolean | no | Start fresh test recording from app restart. |
| `fromCrash` | boolean | no | Write repro test from recent crash. |
| `name` | string | no | Letters, digits and _. |
| `run` | boolean | no | Run the written test (default true). |
| `replay` | boolean | no | Replay recorded interactions live on connected app. |
| `delayMs` | integer | no | Delay between replayed steps in ms (default: 300). |
| `assertRoute` | string | no | Assert that replayed flow ends on this route. |
| `assertWidget` | string | no | Assert this widget key/text is visible after replay. |
| `exportAsTest` | boolean | no | Write replayed flow as integration_test file. |
| `testName` | string | no | Test file name in snake_case (with exportAsTest). |

## `synthesize_golden_test`

Writes and runs golden widget tests across phone, tablet, and desktop viewports.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `screen` | string | yes | Class ("FeedScreen") or call ("StoryScreen(id: 1)"). |
| `name` | string | no | lower_snake_case (default from screen). |
| `viewports` | array | no | Default all three. |
| `run` | boolean | no | Default true. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{file: string, images: [string]}`

## `scenario`

Named app states (route, preferences, state, mocks) saved in flutterpilot/scenarios/. save writes, load restores, omit lists.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `save` | string | no | Name to write. |
| `load` | string | no | Name to apply. |
| `description` | string | no | With save: what the scenario is for. |

## `verify_feature`

Verifies a feature against criteria and writes report.md. Pass feature + criteria (with optional asserts), or select criterion N then finish: true.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `feature` | string | no | What is verified. |
| `criteria` | array | no | Acceptance criteria, one sentence each. |
| `scenario` | string | no | With criteria: load this scenario first. |
| `criterion` | integer | no | The criterion (1-based) the next calls are evidence for; picking one again starts its evidence over. |
| `assert` | object | no | Assertion map for the selected criterion. |
| `asserts` | array | no | List of assertion maps matching criteria. |
| `finish` | boolean | no | Close the last criterion and write the report. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{feature?: string, criteria: [{index: int, text: string, verdict: "passed"|"failed"|"not_verified", warnings: int}], report?: string, status?: "ok"|"refused"|"unavailable", reason?: string} (finish, or a refusal)`

## `get_supabase_auth`

Supabase session and user state; realtime:true adds channels, showSensitive:true reveals email/phone.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | boolean | no | Reveal email/phone/user_id. |
| `realtime` | boolean | no | Include Realtime channel subscriptions. |

## `query_supabase_table`

Rows of a Supabase table read with the app's own client and session, so row-level security applies.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `table` | string | yes | Supabase table name. |
| `limit` | integer | no | 1–200, default 20. |
| `filter` | string | no | One equality filter, "column=value". |
| `query` | string | no | Case-insensitive substring filter across row data. |

## `supabase_session`

Performs Supabase Auth action ("refresh" or "sign_out"). Needs --allow-destructive.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `action` | string: refresh \| sign_out | yes | Auth session action ("refresh" or "sign_out"). |
| `scope` | string: local \| global \| others | no | For sign_out. |

## `get_connectivity`

Network connectivity (wifi, mobile, none) and online status. waitForStatus polls until state matches.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `waitForStatus` | string: online \| offline \| wifi \| mobile \| none | no | Poll until network status matches this condition. |
| `timeoutMs` | integer | no | Timeout in ms for waitForStatus (default 3000). |
| `history` | boolean | no | Include the connectivity changes. |
| `limit` | integer | no | Max history entries (default 100). |

## `get_firebase_auth`

Firebase Auth user, token, claims, and project id; showSensitive:true reveals email/name/phone.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | boolean | no | Reveal email, display name and phone number. |

## `query_firestore`

Reads Firestore through the app's own connection and signed-in user, so security rules apply as in the app.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `path` | string | yes | A collection ("users/UID/notes") or a document ("users/UID"). |
| `where` | string | no | One filter, "field op value" with == != < <= > >= or array-contains, e.g. "done == false". |
| `orderBy` | string | no | A field, optionally followed by "desc". |
| `limit` | integer | no | 1–100, default 20. |
| `query` | string | no | Case-insensitive substring filter in document data/id. |
| `source` | string: server \| cache | no | cache: what the app has locally instead of the server. |

## `get_secure_storage`

FlutterSecureStorage keys (redacted). Filter with key or query; showValues reveals non-sensitive values.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Read only this key. |
| `query` | string | no | Key or value substring filter. |
| `showValues` | boolean | no | Reveal values (except always-redacted keys). |

## `set_secure_storage_key`

Writes a FlutterSecureStorage key (test data). delete:true removes it; no key with delete:true and confirm "DELETE_ALL" wipes all keys. Needs --allow-destructive.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The key. |
| `value` | string | no | The value to store. |
| `delete` | boolean | no | Delete instead of write. |
| `confirm` | string | no | "DELETE_ALL" to wipe every key (no key given). |

