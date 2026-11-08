# FlutterPilot MCP Tools

Generated from the running server registration. Do not edit manually.

Tool count: 74

Size of the whole list as an agent receives it (names, descriptions, schemas): 44975 bytes. An app is shown only the tools that work for it.

`native_*` tools are listed to agents only when the connected app runs on an iOS simulator and `idb` (or `xcrun`, for `native_screenshot`) is installed, or on Android and `adb` is found (PATH, ANDROID_HOME or the SDK folder).

## `connect_app`

Connects to a running Flutter app: the VM service URI flutter run prints, or without uri the one found in the project or the client's workspace folders. Needed only when the app was not found automatically or was restarted.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `uri` | string | no | Optional VM Service URI (e.g. "http://127.0.0.1:12345/abcdefg=/"). If omitted, auto-discovers. |

## `list_connected_devices`

Lists the Flutter apps FlutterPilot knows (one per device: iOS, Android, web, desktop): platform, app, whether it runs fp_sdk, and which one is active. Every tool targets the active device.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `register_device`

Adds a running Flutter app to the fleet under a name, e.g. the same app on an iPhone simulator next to the one on Android. Pass the VM service URI that flutter run prints ("A Dart VM Service on ... is available at: http://127.0.0.1:PORT/TOKEN=/"). Registering an existing name again updates its URI after the app restarted.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | A short name, e.g. "iphone", "pixel", "web". |
| `uri` | string | yes | The VM service URI (http://… as flutter run prints it, or ws://…/ws). |

## `run_on_devices`

Runs the same steps on several registered devices at once (e.g. iPhone, Android and web) and compares them: which steps passed where, and how the final screens differ (route, tappable elements, errors). Each device stops at its first failed step. Use it to check a flow works on every platform in one call.

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

Recent uncaught exceptions with source file:line and layout culprits. report:true returns crash report; clear:true empties buffer.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `report` | boolean | no | Return the latest crash report instead of the list. |
| `clear` | boolean | no | Clear the recorded error buffer. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{hasErrors: bool, count: int, errors: [{kind: "exception"|"overflow", message: string, location?: string, beforeReload: bool}], status?: "ok"|"unavailable", reason?: string}`

## `get_debug_logs`

Captured logs (print, debugPrint, log). Filter by query/level, or wait with waitFor; clear:true empties buffer.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `level` | string: debug \| info \| warning \| warn \| error | no |  |
| `query` | string | no | Only messages containing this. |
| `waitFor` | string | no | Poll until a log message containing this appears. |
| `timeoutMs` | integer | no | Timeout in ms for waitFor (default 3000). |
| `sinceSeconds` | integer | no | Only the last N seconds. |
| `limit` | integer | no | Default 100. |
| `logger` | string | no | Only this logger (partial match), e.g. "debugPrint", "stdout". |
| `clear` | boolean | no |  |

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
| `filter` | string | no | Widget type or key substring to filter results. |
| `reset` | boolean | no | Reset rebuild counts and start a new observation window. |
| `minCount` | integer | no | Minimum rebuild count to report (default 1). |

## `tap_widget`

Taps a widget by key, selector or text (scrolling first) or at x/y. Reports route change, widget diff and tappable elements now.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector, visible text or icon name. |
| `mark` | integer | no | Mark number from capture_screenshot. |
| `identifier` | string | no | Semantics identifier. |
| `semanticsId` | integer | no | SemanticsNode id. |
| `text` | string | no | Visible text inside the widget. |
| `type` | string | no | Widget type, e.g. "IconButton". |
| `x` | number | no | X in logical pixels, with y. |
| `y` | number | no | Y in logical pixels. |
| `gesture` | string: tap \| double \| long \| secondary | no | Default tap (or double/long/secondary). |
| `durationMs` | integer | no | Long-press duration (default 600). |
| `waitFor` | string | no | Widget to wait for after tap. |
| `timeoutMs` | integer | no | Timeout for waitFor (default 5000). |
| `quickSettle` | boolean | no | Settle in <=400ms. |
| `settleTimeoutMs` | integer | no | Screen settle timeout in ms. |

## `enter_text`

Types text into a field by key, selector or label (or focused field). Fires onChanged; pass submit:true to press Enter, or waitFor to poll for a resulting widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | Text to enter ("" clears the field). |
| `key` | string | no | Key, selector or label. Omit for focused field. |
| `mark` | integer | no | Mark number from capture_screenshot. |
| `identifier` | string | no | Semantics id. |
| `clearFirst` | boolean | no | Clear existing text first (default true). |
| `submit` | boolean | no | Press Enter to submit. |
| `waitFor` | string | no | Widget or text to wait for. |
| `timeoutMs` | integer | no | Timeout in ms (default 5000). |

## `press_key`

Presses a key on focused widget (enter, tab, escape, arrows, or "back" to pop). Use count to repeat; pass waitFor to await a widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | E.g. "enter", "tab", "escape", "back", "arrowDown", "space", "backspace", or a single character. |
| `modifiers` | array | no | Optional modifier keys: "shift", "ctrl", "alt", "meta". |
| `count` | integer | no | Number of times to press the key (1–20, default 1). |
| `waitFor` | string | no | Optional widget key/selector to wait for. |
| `timeoutMs` | integer | no | Timeout for waitFor in ms (default 5000). |

## `gesture_widget`

Drives a widget with swipe, drag, pinch, focus or slide. Reports what changed in route and tree.

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
| `y` | number | no |  |
| `value` | number | no | Slider value for slide. |
| `waitFor` | string | no | Optional widget key to wait for after gesture. |
| `timeoutMs` | integer | no | Timeout for waitFor in ms (default 5000). |

## `scroll_into_view`

Scrolls until widget (key, selector, or text) is visible. Pass tap: true to tap once visible.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or text of the widget. |
| `tap` | boolean | no | Whether to tap the widget once scrolled into view. |
| `waitFor` | string | no | Optional widget to wait for after tapping. |
| `timeoutMs` | integer | no | Timeout for waitFor in ms (default 5000). |

## `toggle_checkbox`

Toggles Checkbox, Switch or Radio. Pass value to set idempotently or waitFor to await next widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or label of the toggle, or of the row that holds it. |
| `value` | boolean | no | Target state (true/false). If already set, does not toggle. |
| `waitFor` | string | no | Optional widget key to wait for. |
| `timeoutMs` | integer | no | Timeout for waitFor in ms (default 5000). |

## `fill_form`

Fills several fields in one call and optionally taps a submit button: text for text fields, true/false for checkboxes and switches. Reports the route change and widget-tree diff.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fields` | object | yes | Map of field key/selector to value, e.g. {"TextField['Email']": "a@b.dev", "Checkbox['Terms']": true}. |
| `submitWith` | string | no | Optional button to tap after filling (e.g. "ElevatedButton['Log In']"). |
| `submit` | boolean | no | Tap the one primary button. |
| `waitFor` | string | no | Widget or text to wait for after submitting. |
| `timeoutMs` | integer | no | Timeout for waitFor (default 5000). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{submitted: bool, filledCount: int, totalFields: int, failedField?: string, validationErrors?: [string], status?: "ok"|"unavailable"}`

## `wait_for`

Waits for condition: widget key, anyOf targets, route, animations, state, or frames. Supports failureKey for fast error abort.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or text on screen. |
| `anyOf` | array | no | Wait until any one of these keys/selectors appears. |
| `failureKey` | string | no | Immediate failure key (e.g. error banner). Aborts wait immediately if seen. |
| `gone` | boolean | no | Until key is gone. |
| `route` | string | no | Target route (e.g. "/dashboard"). |
| `animations` | boolean | no | Until animations have settled. |
| `state` | string | no | Provider or bloc name from get_state. |
| `expectedValue` | string | no | Substring expected in state value. |
| `frames` | integer | no | Pump this many frames (1–120). |
| `timeoutMs` | integer | no | Default 5000 (3000 for key). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{met: bool, waitedMs: int, timedOut: bool, condition: "key"|"route"|"state"|"frames"|"animations"|"none", route?: string, status?: "ok"|"unavailable"|"refused"}`

## `audit_screen_health`

Audits screen health: layout overflows, tap target sizes, contrast, unlabeled controls. viewports sweeps breakpoints.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `routes` | array | no | Go to each route and check it. |
| `category` | string: all \| overflow \| a11y \| contrast | no | Filter findings by category (default: all). |
| `designQuality` | boolean | no | Audit 4/8dp spacing grid and typography hierarchy. |
| `viewports` | array | no | Audit viewports (e.g. ["mobile_portrait", "tablet"]). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{requested: int, visited: int, audited: int, failed: int, skipped: int, findings: {overflows: int, tapTargets: int, unlabeled: int, lowContrast: int, readingOrderJumps: int}, restored: bool, incomplete: bool, loading: bool, status?: "ok"|"partial"|"unavailable", reason?: string}`

## `audit_design_tokens`

Audits hard-coded colors and off-grid corner radii in app widgets with source location and closest theme token.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string: all \| colors \| radii | no | Filter findings by colors or radii (default: all). |

## `execute_action_chain`

Runs a known sequence of steps in one call, stopping at the first that fails. Returns each step's outcome and post-chain screen state (route, visual diff, elements).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `steps` | array | yes | Sequence of steps, e.g. [{"tool": "tap_widget", "arguments": {"key": "Save"}}]. |
| `exportAsTest` | boolean | no | Export the executed journey as a runnable integration test file. |
| `testName` | string | no | Name of the generated test. |
| `testFilePath` | string | no | Target test file path. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{passed: bool, completedSteps: int, totalSteps: int, failedStep?: int, failureReason?: string, status?: "ok"|"refused"|"unavailable"}`

## `native_screenshot`

Screenshot of the whole simulator screen, in points: unlike capture_screenshot it includes system alerts, the keyboard and other apps. Use when the Flutter screenshot does not show what is on top.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_tap`

Taps the simulator screen at x/y in points, e.g. a permission alert's "Allow", which is not in the Flutter tree. Take the point from native_describe_screen. For the app's own widgets use tap_widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `x` | number | yes | X in points. |
| `y` | number | yes | Y in points. |
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_text`

Types text into whatever has focus on the simulator, through the real iOS keyboard path: native alert fields, other apps. For the app's own text fields use enter_text.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | Text to type. |
| `serial` | string | no | Android adb serial. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_button`

Presses a simulator hardware button. HOME backgrounds the app (iOS then suspends it; native_open_app brings it back).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `button` | string: APPLE_PAY \| HOME \| LOCK \| SIDE_BUTTON \| SIRI \| BACK \| WAKEUP | yes |  |
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

Goes to a route or deep link directly (go_router: router.go; otherwise Navigator.pushNamed). Back: press_key("back").

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `route` | string | yes | Route or deep link URL (e.g. "/home", "/story/:id"). |
| `action` | string: go \| push \| replace | no | Default "go". push/replace need the go_router plugin. |
| `deepLink` | boolean | no | Open route as an OS deep link (myapp://product/1). |
| `waitFor` | string | no | Key or text to wait for on the new page. |
| `pathParams` | object | no | Dynamic params (e.g. {"id": "123"}). |
| `queryParams` | object | no | Query params (e.g. {"tab": "all"}). |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{requested: string, resolvedUri?: string, current?: string, waitRequired: bool, waitStatus?: "found"|"missing", completed: bool, uncertain: bool, status?: "ok"|"refused"|"unavailable"}`

## `get_navigation_stack`

Navigation stack and route locations. waitForRoute polls until matching route appears; routes/history add router table.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `routes` | boolean | no | Include go_router's configured routes. |
| `history` | boolean | no | Include recent route changes (go_router). |
| `waitForRoute` | string | no | Poll until current route equals or contains this. |
| `timeoutMs` | integer | no | Timeout in ms for waitForRoute (default 3000). |

## `set_app_settings`

Configure theme, locale, text scale, orientation, window size, or overlays without code edits; reset:true restores defaults.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `reset` | boolean | no | Restore system theme, locale, text scale, and clear debug overlays. |
| `theme` | string: light \| dark | no |  |
| `locale` | string | no | BCP-47 tag (e.g. "fr", "ar", "zh") or "system". |
| `textScale` | number | no | Scale factor (1.0 default, 0 restores system). |
| `keyboardInset` | number | no | Height in logical pixels (e.g. 300; 0 removes). |
| `orientation` | string: portrait \| landscape \| all \| auto | no | Phones. |
| `windowSize` | string | no | "WIDTHxHEIGHT" in logical pixels (e.g. "390x844"). |
| `debugPaint` | boolean | no |  |
| `repaintRainbow` | boolean | no |  |
| `slowAnimations` | boolean | no |  |

## `simulate_viewport_matrix`

Sweeps app window across phone, tablet, or desktop breakpoints to detect layout overflows.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `viewports` | array | no | Optional subset of breakpoints to sweep. |
| `restore` | boolean | no | Restore initial window size afterwards (default true). |

## `simulate_keyboard`

Simulates on-screen keyboard inset, checks for layout overflows or obscured inputs, and restores inset.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `height` | number | no | Keyboard height in logical pixels (default: 320; 0 closes). |
| `restore` | boolean | no | Remove the simulated keyboard afterwards (default true). |

## `crawl_app`

Finds reachable screens by tapping list rows, cards, tabs and navigation destinations (never buttons, toggles or rows named like actions), one row per list; returns the route graph and each screen's overflow/tap-target counts, then goes back.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxScreens` | integer | no | Stop after this many taps (default 15). |
| `restore` | boolean | no | Go back to the starting route at the end (default true). |

## `capture_screenshot`

Screenshot of the app screen (or specific widget with key). Supports scale, format, and labeled Set-of-Mark.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Optional widget key to crop screenshot to. |
| `format` | string: png \| jpeg \| webp | no |  |
| `scale` | number | no | 0.2–1.0 (default 0.5). |
| `labeled` | boolean | no | Overlay numbered badges on interactive elements. |
| `quality` | integer | no | JPEG compression quality 10-100 (default: 80 for jpeg). |

## `compare_screenshot`

Visual diff against baseline or previous frame. Supports key cropping, diff %, changed bounds, and diff image.

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
| `diff` | boolean | no |  |
| `rootKey` | string | no | Subtree key or selector. |
| `subtree` | string | no | Subtree root key. |
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

Start here. The running app in a few lines: route, viewport, focus, tappable elements, errors, health, logs, jank, and window visibility.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `setup` | boolean | no | Also the server and app setup: connection, plugins the app registered, SDK capabilities, VM, buffer limits. For when a tool is missing or refused. |

**Structured result** (`structuredContent`, a machine-readable twin of the text; no `outputSchema` is declared): `{connected: bool, device?: string, platform?: string, route?: string, errorCount: int, buildMode?: string}`

## `get_widget_properties`

Widget state: type, text, isEnabled, isChecked, isFocused, bounds, slider values, and validation errors.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key or selector of the widget. |
| `keys` | array | no | Batch of keys or selectors to inspect together. |

## `inspect_widget`

Where a widget is in source code (file:line), bounds, ancestors, layout constraints, styling, and semantic properties.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or visible text. |
| `x` | number | no | X in logical pixels (top-left origin), with y. |
| `y` | number | no | Y in logical pixels. |
| `layout` | boolean | no | Also each box's constraints and size up the ancestors, and why it overflows or is 0 wide. |
| `style` | boolean | no | Also text size, weight and color, paddings, fills, borders, radii and elevation of the widget. |
| `properties` | boolean | no | Also include semantic properties (isEnabled, text, isChecked, etc.). |

## `get_semantics_tree`

Screen reader semantics tree (VoiceOver/TalkBack): label, value, hint, role flags, and rect. Supports query filter and maxDepth.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `query` | string | no | Substring filter for node label, hint, value, or identifier. |
| `maxDepth` | integer | no | Default 50. |

## `hot_reload`

Hot reloads edited .dart files into running app (keeping state). restart:true resets state (for main, initState, providers). waitForSettled:true waits for frame settlement (default true).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `restart` | boolean | no | Hot restart instead of hot reload. |
| `waitForSettled` | boolean | no | Wait for frame settlement (default true). |

## `launch_app`

Builds and starts the app (flutter run, or flutterpilot/launch.json's command) on a device, waits for its first frame and connects; it outlives this session. Takes minutes: with the app running there it refuses unless relaunch:true (pubspec.yaml, assets or native code changed); hot_reload loads Dart changes in a second. A failed build returns its output's end.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `device` | string | no | flutter run -d: "macos", "chrome", an id. |
| `target` | string | no | Entrypoint (default lib/main.dart). |
| `mode` | string: debug \| profile | no | Default debug. |
| `project` | string | no | App folder, if several. |
| `relaunch` | boolean | no | Stop the running app and rebuild. |
| `waitSeconds` | integer | no | Return early if still building (default 600). |

## `apply_and_verify`

Hot-reloads/restarts app, awaits frame settle, verifies zero errors, and optionally polls waitFor widget in 1 turn.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `restart` | boolean | no | Hot restart instead of reload. |
| `waitFor` | string | no | Optional widget key or text to wait for after reload. |
| `quickSettle` | boolean | no | Settle in <=400ms. |
| `settleTimeoutMs` | integer | no | Screen settle timeout in ms (default 2000). |

## `get_state`

Current values of the app's Riverpod providers and Blocs/Cubits (name: value (type)). history:true lists the recent changes instead, oldest first with times: each value with the one it replaced, providers created and disposed, and the route changes between them — how the state got to where it is.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string: riverpod \| bloc | no | Only this kind. |
| `name` | string | no | Only names containing this. |
| `history` | boolean | no |  |
| `clear` | boolean | no | Empty the history after returning it: do that before an action to see only its effects. |

## `set_state`

Sets a Riverpod provider or Bloc/Cubit state in memory: name + value, or several at once with states. Names come from get_state; type is inferred. Works for bool/number/String/List/Map states; for enum or class states it explains why not — drive the UI instead.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | no | Provider or bloc name from get_state (e.g. "counterProvider", "CounterCubit#2"). |
| `value` | any | no | New value: plain (42, true, "text") or JSON. |
| `states` | object | no | Several at once: {"counterProvider": 10, "themeProvider": "dark"}. |
| `type` | string: riverpod \| bloc | no | Only needed if the name is not observed yet. |

## `get_network_logs`

Dio network requests (including mocks). Filter by query or errorsOnly, with limit.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `query` | string | no | URL or message filter. |
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
| `query` | string | no | Key substring filter. |
| `showSensitive` | boolean | no | Reveal sensitive values. |

## `set_shared_preference`

Writes a SharedPreferences key (type: string (default), int, double, bool, stringList as a JSON array). remove:true deletes the key; no key with confirm "CLEAR_ALL" clears every preference. Needs --allow-destructive.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The key. Omit only to clear all (with confirm). |
| `remove` | boolean | no | Delete the key. |
| `confirm` | string | no | "CLEAR_ALL" to clear every preference (no key). |
| `value` | string | no | "true"/"false", "42", or for a stringList a JSON array of strings. |
| `type` | string: string \| bool \| int \| double \| stringList | no | Default "string". |

## `simulate_network`

Makes every HTTP request (http, dart:io, Dio) slow, fail (offline/chaos) or normal again. errorRate (0.0-1.0) and statusCode (e.g. 500) inject network chaos; delayMs holds each one that long. restore:true clears.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `condition` | string: normal \| slow_3g \| fast_4g \| offline | no |  |
| `delayMs` | integer | no | Up to 60000. |
| `errorRate` | number | no | Chaos failure rate 0.0-1.0 (e.g. 0.5 for 50% drops). |
| `statusCode` | integer | no | HTTP status code on failure, e.g. 500, 503, 404. |
| `restore` | boolean | no | Restore normal network conditions. |

## `mock_http_response`

Canned Dio responses or errors (timeout/connection). Single endpoint or batch via mocks:[...]; clear:true resets.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `urlPattern` | string | no | Part of the URL, e.g. "/api/users". |
| `clear` | boolean | no | Remove the mock for urlPattern, or every mock without one. |
| `statusCode` | integer | no |  |
| `body` | string | no | Response body as a JSON string, e.g. '{"error":"not found"}'. |
| `delayMs` | integer | no | Delay before the response or failure (default 0). |
| `error` | string: timeout \| connection | no | In place of statusCode: the server never answers (timeout) or can't be reached (connection). |
| `mocks` | array | no | Batch of mocks: [{urlPattern, statusCode, body, delayMs, error}]. |

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

## `export_network_mocks`

Exports recorded Dio HTTP responses as mock_http_response steps; apply:true installs mocks for offline replay.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `filter` | string | no | Only URLs containing this. |
| `statusCode` | integer | no | Use this status instead of the recorded one. |
| `apply` | boolean | no | Install the mocks now instead of only listing them. |

## `get_memory_details`

Heap used/capacity and external memory. classes:true lists top classes. diffBaseline:true isolates memory growth since baseline. route/cycle runs automated leak checks.

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

## `locate_source_ast`

Locates widget constructor call in source code (file:line, code snippet, named arguments, start/end file offsets).

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, selector or visible text of the widget. |
| `file` | string | no | File in the app, e.g. "lib/ui/tile.dart". |
| `line` | integer | no | 1-based line, with file. |
| `column` | integer | no | 1-based column where the call starts, with file. |

## `apply_patch_and_verify`

Surgically patches widget in source (wrap, unwrap, replaceCall), hot-reloads, audits health, and auto-rolls back if reload fails.

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
| `patches` | array | no | Batch of patch objects to apply atomically in 1 reload. |

## `replay_flow`

Replays recorded user interactions live on the connected app without writing a test binary.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `delayMs` | integer | no | Delay between steps in ms (default: 300). |
| `assertRoute` | string | no | Assert that the flow ends on this route. |
| `assertWidget` | string | no | Assert that this widget key/text is visible after replay. |

## `generate_test`

Records user interactions and writes executable integration_test files (start:true begins recording; name writes and runs test).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `start` | boolean | no |  |
| `fromCrash` | boolean | no | Write repro test from recent crash. |
| `name` | string | no | Letters, digits and _. |
| `run` | boolean | no | Run the written test (default true). |

## `synthesize_golden_test`

Writes and runs golden widget tests for a screen across phone, tablet, and desktop viewports.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `screen` | string | yes | Class ("FeedScreen") or call ("StoryScreen(id: 1)"). |
| `name` | string | no | lower_snake_case (default from screen). |
| `viewports` | array | no | Default all three. |
| `run` | boolean | no | Default true. |

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

## `supabase_session`

Real Supabase Auth API call on the app's session (dev/test projects only): action "refresh" force-refreshes the token (test expiry flows); "sign_out" signs out with scope local (default), global or others. Needs --allow-destructive.

_Destructive: replaces stored data (needs `--allow-destructive`) or runs app code._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `action` | string: refresh \| sign_out | yes |  |
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
| `source` | string: server \| cache | no | cache: what the app has locally instead of the server. |

## `get_secure_storage`

FlutterSecureStorage keys (redacted). Filter with key or query; showValues reveals non-sensitive values.

_Read-only._

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Read only this key. |
| `query` | string | no | Key substring filter. |
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

