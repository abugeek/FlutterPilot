# FlutterPilot MCP Tools

Generated from the running server registration. Do not edit manually.

Tool count: 67

`native_*` tools are listed to agents only when the connected app runs on iOS and `idb` (or `xcrun`, for `native_screenshot`) is installed.

## `connect_app`

Connects to a running Flutter app: the VM service URI flutter run prints, or without uri the one found in the project or the client's workspace folders. Needed only when the app was not found automatically or was restarted.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `uri` | string | no | Optional VM Service URI (e.g. "http://127.0.0.1:12345/abcdefg=/"). If omitted, auto-discovers. |

## `list_connected_devices`

Lists the Flutter apps FlutterPilot knows (one per device: iOS, Android, web, desktop): platform, app, whether it runs flutterpilot_sdk, and which one is active. Every tool targets the active device.

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
| `steps` | array | yes | Tool calls run in order on each device, e.g. [{"tool": "tap_widget", "arguments": {"key": "Log in"}}, {"tool": "assert_widget", "arguments": {"text": "Welcome"}}]. Tools: assert_widget, drag_widget, enter_text, execute_action_chain, fill_form, mock_http_response, mock_platform_channel, navigate_to, press_key, scroll_into_view, set_slider_value, simulate_network, swipe_widget, tap_widget, toggle_checkbox, wait_for. |
| `devices` | array | no | Registered device names (list_connected_devices); default: all of them. |

## `switch_device`

Makes a registered device the active one: every tool call after this targets it. See list_connected_devices for the names.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | The name of a registered device. |

## `get_errors`

Recent uncaught exceptions, deduplicated, with your source frame (file:line) and, for layout errors, the culprit widget. report:true returns the structured report of the latest crash instead: exception, stack, route, recent actions and state.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `report` | boolean | no | Return the latest crash report instead of the list. |

## `get_debug_logs`

Returns console output the running app printed since FlutterPilot connected — print(), debugPrint(), and dart:developer log() calls. Supports search query, level filter ("debug", "info", "warning", "error"), since_seconds, and limit. clear:true empties the server and in-app buffers instead (a clean baseline before a test).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `level` | string | no | Filter by log level: "debug", "info", "warning", or "error". Omit to return all levels. |
| `query` | string | no | Search string to filter log messages. |
| `since_seconds` | integer | no | Only return logs captured within the last N seconds. |
| `limit` | integer | no | Maximum number of log entries to return (default: 100). |
| `logger` | string | no | Filter by logger name (partial match). E.g. "debugPrint", "stdout", "print". |
| `clear` | boolean | no | Clear the captured logs instead of reading them. |

## `get_capabilities`

Server and app setup: connection, which FlutterPilot plugins the app registered, SDK capabilities, Dart VM version, pid and isolates, buffer limits. Use when a tool is missing or refused.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `profile_frame_budget`

Frame timings of the last 120 frames: p50/p90/p99 build, raster and total, jank count, and whether the UI thread (build/layout) or the raster thread causes dropped frames. profile_action explains the slow frames of one interaction (phases, rebuilt widgets).

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `tap_widget`

Taps a widget found by key, selector (e.g. "ElevatedButton['Log In']"), semantics identifier or visible text — or at x/y. Exact text wins; text several widgets merely contain is refused with the candidates. gesture: "double", "long" (durationMs) or "secondary" (right-click, context menus). waitFor: a widget to wait for after the tap (replaces a separate wait_for call). The response reports the route change, a widget-tree diff and what is tappable now.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | ValueKey string, semantic selector (e.g. "ElevatedButton['Sign In']"), visible button text, or icon name (e.g. "IconButton['settings']"). |
| `identifier` | string | no | Semantics identifier (Flutter 3.19+). |
| `semanticsId` | integer | no | SemanticsNode id from get_semantics_tree. |
| `text` | string | no | Visible text content within the widget to tap. |
| `type` | string | no | Widget runtime type, e.g. "ElevatedButton", "TextButton", "IconButton". |
| `x` | number | no | X in logical pixels (top-left origin), with y. |
| `y` | number | no | Y in logical pixels. |
| `gesture` | string | no | Default "tap". |
| `durationMs` | integer | no | Long-press duration (default 600). |
| `waitFor` | string | no | Key, selector or text of a widget expected to appear after the tap. |
| `timeoutMs` | integer | no | How long to wait for waitFor (default 5000). |

## `enter_text`

Types text into a TextField/TextFormField found by key, selector (e.g. "TextField['Email']") or label, or into the focused field when no key is given. Replaces the existing text unless clear_first is false; text "" clears the field. Fires onChanged; press_key("enter") afterwards submits.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | The text to enter ("" clears the field). |
| `key` | string | no | ValueKey string, selector (e.g. "TextField['Email']"), or label of the field. Omit for the focused field. |
| `identifier` | string | no | Semantics identifier of the text field. |
| `clear_first` | boolean | no | Whether to clear existing text before typing (default: true). |

## `press_key`

Presses a key on the focused widget: "enter" (submits a text field), "tab", "escape" (closes menus/dialogs), arrow keys, and shortcuts with modifiers (shift, ctrl, alt, meta). "back" is the system back button: pops the current route, never quits the app from the root. In a focused text field, characters, backspace, delete, arrows, home/end and meta/ctrl+a edit it as typing would, and the response shows the field's text and cursor; to set a whole value, enter_text is simpler.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | Key name, e.g. "enter", "tab", "escape", "back", "arrowDown", "space", or a single character. |
| `modifiers` | array | no | Optional modifier keys: "shift", "ctrl", "alt", "meta". |

## `pinch_zoom`

Two-finger pinch on a widget or at x/y: scale > 1 zooms in, < 1 zooms out. Reports what changed.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `scale` | number | yes | Zoom scale factor (e.g. 1.5 to zoom in, 0.75 to zoom out). |
| `key` | string | no | The ValueKey or selector of the target widget. |
| `identifier` | string | no | Semantics identifier of the target widget. |
| `x` | number | no | Optional center X coordinate for pinch gesture. |
| `y` | number | no | Optional center Y coordinate for pinch gesture. |

## `scroll_into_view`

Scrolls the lists on screen until the widget (key, selector or text) is on screen, including items a lazy list has not built yet and cards in a horizontal list inside a vertical one. tap_widget already does this before tapping.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string, semantic selector, or label of the widget to scroll into view. |
| `target` | string | no | Same as key (either name works). |

## `swipe_widget`

Swipes on a widget up/down/left/right: scroll a list, dismiss a card, open a drawer, pull to refresh (down on a list at its top). Reports what changed.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to swipe. |
| `target` | string | no | Same as key (either name works). |
| `direction` | string | yes |  |
| `distance` | number | no | Scroll distance in logical pixels. Positive = down/right, negative = up/left. |

## `drag_widget`

Drags one widget onto another (drag-and-drop, reordering). Reports what changed.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fromKey` | string | yes | The ValueKey string of the widget to drag from (drag source). |
| `toKey` | string | yes | The ValueKey string of the target widget to drag to (drop target). |

## `focus_widget`

Focuses the widget found by key (opens the software keyboard for a TextField). Without a key, removes focus from everything and dismisses the keyboard.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string or selector of the widget. Omit to unfocus all. |

## `set_slider_value`

Moves a Slider to a value (clamped to its min/max) the way a user would, so onChanged fires.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the Slider widget. |
| `target` | string | no | Same as key (either name works). |
| `value` | number | yes | The new slider value. Must be within the slider min/max range. |

## `toggle_checkbox`

Toggles the Checkbox, Switch or Radio under the key; the response shows its new value (= true/false).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the Checkbox, Switch, or Radio widget to toggle. |
| `target` | string | no | Same as key (either name works). |

## `fill_form`

Fills several fields in one call and optionally taps a submit button: text for text fields, true/false for checkboxes and switches. Reports the route change and widget-tree diff.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fields` | object | yes | Map of field key/selector to value, e.g. {"TextField['Email']": "a@b.dev", "Checkbox['Terms']": true}. |
| `submitWith` | string | no | Optional key/selector of the button to tap after filling (e.g. "ElevatedButton['Log In']"). |

## `wait_for`

Waits (polling, never a blind sleep) for one condition: key — a widget/selector/text is on screen; route — the current route is this one; animations: true — animations and frame callbacks settled; state — a Riverpod provider or Bloc whose value contains expectedValue (needs the plugin); frames — pump N frames (1–120). Fails with the reason on timeout.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Selector or key to wait for (e.g. "Text['Dashboard']"). |
| `route` | string | no | Route to wait for (e.g. "/dashboard"). |
| `animations` | boolean | no | Wait until animations have settled. |
| `state` | string | no | Provider/bloc name from get_state (e.g. "CounterCubit"); needs expectedValue. |
| `expectedValue` | string | no | Substring expected in the state's value. |
| `frames` | integer | no | Number of frames to pump (1–120). |
| `timeoutMs` | integer | no | Default 5000 (3000 for key). |

## `audit_screen_health`

Layout and accessibility check of the current screen: layout overflows, tap targets under the platform minimum (48dp phones, 24px desktop/web), controls a screen reader can't name (no label/tooltip), text below WCAG contrast (4.5:1, large 3:1, from the rendered pixels), and where the screen reader order jumps back up. Each with position and source file:line. Use after set_app_settings(textScale/locale/theme) or a UI change.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `execute_action_chain`

Runs a known sequence of taps and text entries in one call, stopping at the first step that fails. Returns how many steps ran, the failure if any, and the screen afterwards (route, diff, tappable elements).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `actions` | array | yes | Steps run in order; the chain stops at the first step that fails. Actions: "tap" (target) and "enter_text" (target, text). Targets work like tap_widget's, e.g. [{"action": "tap", "target": "New note"}, {"action": "enter_text", "target": "Title", "text": "Groceries"}]. |

## `native_screenshot`

Screenshot of the whole simulator screen, in points: unlike capture_screenshot it includes system alerts, the keyboard and other apps. Use when the Flutter screenshot does not show what is on top.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_tap`

Taps the simulator screen at x/y in points, e.g. a permission alert's "Allow", which is not in the Flutter tree. Take the point from native_describe_screen. For the app's own widgets use tap_widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `x` | number | yes | X in points. |
| `y` | number | yes | Y in points. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_text`

Types text into whatever has focus on the simulator, through the real iOS keyboard path: native alert fields, other apps. For the app's own text fields use enter_text.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | Text to type. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_button`

Presses a simulator hardware button. HOME backgrounds the app (iOS then suspends it; native_open_app brings it back).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `button` | string | yes |  |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_describe_screen`

What iOS shows on the simulator right now, one line per element with its role, label and tap point (points), including system alerts the Flutter tree does not have. Use before native_tap.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_open_app`

Brings the connected app back to the foreground on the iOS simulator (after native_button HOME, or when another app is in front), keeping its state. iOS suspends a backgrounded app, so every other tool fails until then.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `navigate_to`

Goes to a route directly, e.g. "/profile/123" (go_router: router.go; otherwise Navigator.pushNamed). action "push"/"replace" use go_router's push/replace. deepLink:true opens the URL the way an OS deep link does (e.g. "myapp://product/123"). Back: press_key("back").

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `route` | string | yes | Route or deep-link URL (e.g. "/home", "/profile/123"). |
| `action` | string | no | Default "go". push/replace need the go_router plugin. |
| `deepLink` | boolean | no | Open route as an OS deep link. |

## `get_navigation_stack`

The route stack, bottom to top. With go_router also the location, path/query parameters and matched routes; routes:true adds the router's route table, history:true the recent route changes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `routes` | boolean | no | Include go_router's configured routes. |
| `history` | boolean | no | Include recent route changes (go_router). |

## `set_app_settings`

Changes how the app renders, one or more at once: theme (light/dark), locale ("fr", "ar", "system"), textScale (2.0 to test large text; 0 resets), orientation (portrait/landscape/all, phones), windowSize ("390x844", macOS desktop window), and the debug overlays debugPaint (layout bounds), repaintRainbow (what repaints) and slowAnimations (5x slower). Locale and textScale act like the device setting, with no app code: the response says what the app shows, e.g. when it does not support the locale or clamps text scaling. Pair with audit_screen_health to catch overflows.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `theme` | string | no |  |
| `locale` | string | no | BCP-47 tag (e.g. "en", "en-GB", "zh-Hans-CN"); "system" restores the device locale. |
| `textScale` | number | no | Text scale factor (1.0 normal); 0 restores the system value. |
| `orientation` | string | no |  |
| `windowSize` | string | no | macOS desktop: the window's size in logical pixels, "WIDTHxHEIGHT" (e.g. "390x844" for a phone width, "1280x860"). The title bar is part of the height. |
| `debugPaint` | boolean | no |  |
| `repaintRainbow` | boolean | no |  |
| `slowAnimations` | boolean | no |  |

## `capture_screenshot`

Image of the app's screen, PNG at half size by default; scale 1.0 for full resolution, format "jpeg" for a smaller file. Use when you need to see layout, color or images — for text and structure get_app_summary or get_widget_tree are cheaper.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `format` | string | no |  |
| `scale` | number | no | 0.2–1.0 (default 0.5). |
| `quality` | integer | no | JPEG compression quality 10-100 (default: 80 for jpeg). |

## `compare_screenshot`

Visual regression: save:true stores the current screen as the named baseline (per device); without it, compares the screen with that baseline pixel by pixel and returns the changed %, plus a diff image (changes in magenta) when over threshold.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Baseline name, e.g. "home_screen", "login_dark". |
| `save` | boolean | no | Save (or replace) the baseline instead of comparing. |
| `threshold` | number | no | Allowed diff % before test fails (default 1.0 = 1%) |

## `get_widget_tree`

The app's own widgets on screen (DevTools summary tree) with keys, text, selectors and bounds (rect: [x, y, w, h], left out when the same as the parent's); layout wrappers are pruned unless compact is false. rootKey scopes it to one subtree (a dialog, a form). diff:true returns only what changed since the previous call.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `diff` | boolean | no | Only widgets added/removed/changed since the last call. |
| `rootKey` | string | no | Optional widget key or semantic selector (e.g. "checkout_form", "Button['Save']") to scope the tree capture to only that subtree. |
| `maxDepth` | integer | no | Maximum tree depth (default 50). |
| `compact` | boolean | no | Whether to prune intermediate unkeyed layout containers (default: true). |

## `get_interactive_elements`

Every widget the user can tap or type into right now (buttons, fields, checkboxes, switches, sliders, tappable tiles) with type, label, key and bounds; covered or off-screen ones are left out. get_app_summary shows the first 15.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `types` | array | no | Optional filter for specific widget types (e.g. ["ElevatedButton", "TextField"]). |

## `get_app_summary`

Start here. The running app in a few lines: route, viewport, focused widget, the tappable elements (labels + keys), uncaught errors, recent logs, jank, and whether the window is visible or covered by a system alert.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_widget_properties`

One widget's state: type, text (Text/TextField content), isEnabled, isChecked (Checkbox/Switch), value/min/max (Slider), isFocused and bounds.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to inspect. |
| `target` | string | no | Same as key (either name works). |

## `inspect_widget`

Which file:line in the app's code creates a widget: pass key (key, selector or visible text) or x,y (logical pixels, e.g. from a screenshot). Returns the source (for framework widgets, the app widget that builds it) and the app widgets above it. layout:true adds the constraints and size of each box up its ancestors and explains overflows and 0-sized widgets (which children fill a Row, which ancestor gives max width 0). Use before editing UI code.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key, semantic selector or visible text. |
| `target` | string | no | Same as key (either name works). |
| `x` | number | no | X in logical pixels (top-left origin), with y. |
| `y` | number | no | Y in logical pixels. |
| `layout` | boolean | no | Also constraints and sizes up the ancestors, and why it overflows or is 0 wide. |

## `get_semantics_tree`

What a screen reader (VoiceOver/TalkBack) gets: per node id, label, value, hint, role flags, checked/enabled/focused and rect. Only what is set is listed: a missing flag is false, isChecked appears on checkable nodes, isEnabled only when false. Use to check labels for accessibility; semanticsId works in tap_widget.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxDepth` | integer | no | Maximum tree depth (default 50). |

## `hot_reload`

Recompiles edited .dart files and hot reloads them into the running app, keeping state. restart:true does a hot restart instead (state is reset) — needed for main(), initState, global/static initializers, enums, generic type changes and provider definitions. Needs an app started by `flutter run` or an IDE debug session.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `restart` | boolean | no | Hot restart instead of hot reload. |

## `get_state`

Current values of the app's Riverpod providers and Blocs/Cubits (name: value (type)), as their plugins observe them. type limits it to one of the two.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string | no |  |

## `set_state`

Sets a Riverpod provider or Bloc/Cubit state in memory: name + value, or several at once with states. Names come from get_state; type is inferred. Works for bool/number/String/List/Map states; for enum or class states it explains why not — drive the UI instead.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | no | Provider or bloc name from get_state (e.g. "counterProvider", "CounterCubit#2"). |
| `value` | any | no | New value: plain (42, true, "text") or JSON. |
| `states` | object | no | Several at once: {"counterProvider": 10, "themeProvider": "dark"}. |
| `type` | string | no | Only needed if the name is not observed yet. |

## `get_network_logs`

Recent Dio requests and responses: method, URL, status, error, body (truncated, secrets redacted), and whether a mock answered. Use when an API call failed or to check what was sent.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_hive_contents`

Keys and values of the Hive boxes the app registered with HivePilotInspector.registerBox, e.g. to check the UI saved something.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `exec_sql_query`

Run a read-only SQL query (SELECT, WITH, PRAGMA, EXPLAIN) on the app's local database — Drift or sqflite, whichever is wired. Rows come back as JSON. List tables with "SELECT name FROM sqlite_master WHERE type='table'". If the app registers several databases, a call without database names them.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `sql` | string | yes | SQL statement to execute. |
| `database` | string | no | Database name, only needed when the app registers several. |

## `get_shared_preferences`

Returns all SharedPreferences keys and their typed values (String, int, double, bool, List<String>). Values matching sensitive key patterns (token, password, secret, auth, etc.) are redacted by default — pass showSensitive=true to reveal them.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | string | no | Set to "true" to reveal values for sensitive-looking keys. Default: redacted. |

## `set_shared_preference`

Writes a SharedPreferences key (type: string (default), int, double, bool, stringList as a JSON array). remove:true deletes the key; no key with confirm "CLEAR_ALL" clears every preference. Needs --allow-destructive.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The key. Omit only to clear all (with confirm). |
| `remove` | boolean | no | Delete the key. |
| `confirm` | string | no | "CLEAR_ALL" to clear every preference (no key). |
| `value` | string | no | The value to set as a string. Booleans: "true"/"false". Numbers: numeric string. |
| `type` | string | no | Value type: "string", "bool", "int", "double", or "stringList" (comma-separated). |

## `simulate_network`

Makes every Dio request slow (slow_3g, fast_4g), fail (offline) or normal again, to test loading and offline states.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `condition` | string | yes |  |

## `mock_http_response`

Registers a URL pattern mock so that any Dio request whose URL contains urlPattern returns a synthetic response instead of hitting the network. Use to test error states, empty states, or edge-case API responses. clear:true removes the mock for urlPattern, or all mocks without one — do that when done.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `urlPattern` | string | no | Substring of the URL to match (e.g. "/api/users") |
| `clear` | boolean | no | Remove mocks instead of adding one. |
| `statusCode` | integer | no | HTTP status code (e.g. 200, 404, 500) |
| `body` | string | no | Response body as a JSON string (e.g. '{"error":"not found"}') |
| `delayMs` | integer | no | Artificial delay in milliseconds before returning the mock (default 0) |

## `call_custom_tool`

Runs a tool the app registered with FlutterPilot.registerCustomTool(). Without name, lists them.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | no | The custom tool name. Omit to list the tools. |
| `params` | object | no |  |

## `mock_platform_channel`

Stands in for the native side of a plugin (camera, scanner, location, permissions, Bluetooth), which a simulator or CI has not. channel + method + result (or error): the app's calls to that method get the value, or a PlatformException. channel + event: delivers an event to the app's EventChannel listeners, e.g. a scanned barcode. No argument lists the mocks and the calls the app made (channel, method, arguments, whether a plugin answered): how to find the names. clear:true removes mocks. Pigeon APIs: the whole channel name, no method.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `channel` | string | no | Channel name, e.g. "dev.fluttercommunity.plus/battery". |
| `method` | string | no | The method the app invokes, e.g. "getBatteryLevel". |
| `result` | any | no | What the call returns: any JSON (null for a void method; {"$bytes": "<base64>"} is a byte array). |
| `error` | string | no | Fail the call with a PlatformException of this code, e.g. "PERMISSION_DENIED". |
| `errorMessage` | string | no |  |
| `event` | any | no | The event to deliver on an EventChannel: any JSON. |
| `clear` | boolean | no | Remove the mocks of channel (and method), or all of them. |

## `assert_widget`

Checks the screen in the running app in milliseconds; an error result is a failed assertion. One check per call: text — that text is visible (substring unless exact); key — that widget is on screen, or with enabled true/false that it is enabled/disabled; type + count — exactly that many widgets of the type. Only what the user can see counts (not covered routes or hidden tabs).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | no | Text expected on screen. |
| `exact` | boolean | no | Require an exact text match (default substring). |
| `key` | string | no | Key, selector or label of the widget. |
| `enabled` | boolean | no | With key: expect enabled (true) or disabled (false), i.e. onPressed/onTap/onChanged set or null. |
| `type` | string | no | Widget type to count (e.g. "ListTile"). |
| `count` | integer | no | Expected count of type. |

## `get_memory_details`

Heap used/capacity and external (native) memory per isolate. classes:true lists the top Dart classes by heap bytes and instance count instead (the DevTools Memory tab). Leak check: cycle (action tool calls that end where they started, e.g. open a screen then press back) runs times rounds; returns the classes that gained instances every round, where they are defined and what keeps one alive.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `classes` | boolean | no | List the top classes by heap usage. |
| `limit` | integer | no | Number of classes (default 30). |
| `cycle` | array | no | Leak check: steps [{"tool": "tap_widget", "arguments": {"key": "Open"}}, {"tool": "press_key", "arguments": {"key": "back"}}] that return to the starting screen. |
| `times` | integer | no | Leak check rounds after one warm-up (default 5). |

## `profile_action`

Why an interaction is slow: runs tool (tap_widget, scroll_into_view, execute_action_chain, ...) with arguments while profiling the app, then returns its functions by self/total CPU time with file:line, the hottest framework functions with the app code that called them, and for frames over budget their build/layout/paint/raster times and which app widgets rebuilt. durationMs keeps profiling after the action (results that load later); without tool it profiles whatever the app does.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `tool` | string | no | The action tool to run, e.g. "tap_widget" or "execute_action_chain". |
| `arguments` | object | no | Its arguments, e.g. {"key": "Load more"}. |
| `durationMs` | integer | no | Keep sampling this long after the action returns, for work that lands later (a network response, an animation). Without tool: how long to sample (default 1000, max 10000). |

## `get_http_profile`

HTTP requests the app made through any dart:io client (HttpClient, package:http, Dio; the DevTools Network tab): #number, method, URL, status, duration, sizes, most recent first; url filters. id: one request in full — headers, bodies (JSON, secrets masked), timing, redirects, error. clear:true empties the list for a clean baseline.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `clear` | boolean | no | Clear the recorded requests instead of listing them. |
| `limit` | integer | no | Maximum number of requests to return, most recent first (default: 50). |
| `status_filter` | integer | no | Optional HTTP status code filter (e.g. 404, 500). Omit to return all requests. |
| `url` | string | no | Only requests whose URL contains this text. |
| `id` | integer | no | The #number of a request in the list: its headers, bodies and timing. |

## `generate_test`

Turns what you do in the app into an integration_test. start:true restarts the app (hot restart) and records from there: taps, text, keys, scrolls, drags, back, assert_widget, wait_for and mock_http_response, with the widgets found by key, text or tooltip. name:"checkout" then writes integration_test/checkout_test.dart, runs it on the same device and reports whether it passed (with the failure if not). Obscured text is passed with --dart-define, never written. Takes minutes: the test builds the app again.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `start` | boolean | no | Restart the app and start recording. |
| `name` | string | no | Test name (letters, digits, _): stop recording, write and run the test. |
| `run` | boolean | no | Run the written test (default true). |

## `scenario`

Named app states to start from, kept as flutterpilot/scenarios/<name>.json in the app (check them in, edit them). save:"name" writes the route, SharedPreferences (sensitive keys left out), the rows of registered Drift/sqflite databases and plain Hive boxes, active mocks (HTTP, platform channel) and simple Riverpod/Bloc values. load:"name" replaces the stored data, hot-restarts with the mocks in place from the first call, sets the state and goes to the route (state is set behind the widgets: a TextField keeps its own text). No argument lists them. Loading stored data needs --allow-destructive.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `save` | string | no | Scenario name to write. |
| `load` | string | no | Scenario name to apply. |
| `description` | string | no | With save: what the scenario is for. |

## `verify_feature`

Checks a feature against acceptance criteria and writes a pass/fail report with evidence. Start with feature + criteria (plain sentences; scenario loads one first). Then for each: criterion:N, drive the app and check it with assert_widget, wait_for or compare_screenshot. A criterion passes only if a check passed and none failed and the app threw no error; driven but unchecked is "not verified". Each criterion gets the steps, the HTTP requests made, errors and a screenshot. finish:true writes flutterpilot/reports/<feature>-<time>/report.md in the app and returns the verdicts.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `feature` | string | no | What is verified. |
| `criteria` | array | no | Acceptance criteria, one sentence each. |
| `scenario` | string | no | With criteria: load this scenario first. |
| `criterion` | integer | no | The criterion (1-based) the next calls are evidence for; picking one again starts its evidence over. |
| `finish` | boolean | no | Close the last criterion and write the report. |

## `get_supabase_auth`

Supabase auth state: user, session and JWT expiry, recent auth events; realtime:true adds the Realtime channels (topic, joined, closed). Email/phone are redacted unless showSensitive is true.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | boolean | no | Reveal email/phone/user_id. |
| `realtime` | boolean | no | Include Realtime channel subscriptions. |

## `query_supabase_table`

Rows of a Supabase table read with the app's own client (its session, so row-level security applies): up to limit (default 20, max 200), optional "column=value" filter.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `table` | string | no | Supabase table name (required). |
| `limit` | string | no | Max rows to return (1–200, default 20). |
| `filter` | string | no | Optional equality filter in "column=value" format, e.g. "user_id=abc123". |

## `supabase_session`

Real Supabase Auth API call on the app's session (dev/test projects only): action "refresh" force-refreshes the token (test expiry flows); "sign_out" signs out with scope local (default), global or others. Needs --allow-destructive.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `action` | string | yes |  |
| `scope` | string | no | For sign_out. |

## `get_connectivity`

Network connectivity as the app sees it (wifi, mobile, ethernet, vpn, none) and whether it is online. history:true adds the timestamped transitions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `history` | boolean | no | Include the connectivity changes. |
| `limit` | integer | no | Max history entries (default 100). |

## `get_firebase_auth`

Who is signed in to Firebase Auth in the app: uid (for Firestore paths like users/{uid}/...), providers, anonymous/verified, token expiry and custom claims, recent sign-in/out events, and the Firebase project. Email/name/phone are redacted unless showSensitive=true.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | boolean | no | Reveal email, display name and phone number. |

## `query_firestore`

Read Firestore with the app's own connection and signed-in user (so security rules apply as in the app). path is a collection ("users/UID/notes") or a document ("users/UID"). Optional where ("done == false", ops == != < <= > >= array-contains), orderBy ("createdAt desc"), limit (default 20, max 100), source "cache" to see what the app has locally instead of the server.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `path` | string | no | Collection or document path. |
| `where` | string | no | One filter: "field op value". |
| `orderBy` | string | no | Field, optionally followed by "desc". |
| `limit` | integer | no | 1–100, default 20. |
| `source` | string | no | "server" (default) or "cache". |

## `get_secure_storage`

FlutterSecureStorage keys, values redacted unless showValues is true; key reads one. Keys like password/secret/api_key are always redacted.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Read only this key. |
| `showValues` | boolean | no | Reveal values (except always-redacted keys). |

## `set_secure_storage_key`

Writes a FlutterSecureStorage key (test data). delete:true removes it; no key with delete:true and confirm "DELETE_ALL" wipes all keys. Needs --allow-destructive.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The key. |
| `value` | string | no | The value to store. |
| `delete` | boolean | no | Delete instead of write. |
| `confirm` | string | no | "DELETE_ALL" to wipe every key (no key given). |

