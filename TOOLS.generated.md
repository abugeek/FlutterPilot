# FlutterPilot MCP Tools

Generated from the running server registration. Do not edit manually.

Tool count: 131

## `get_operation`

Polls an asynchronous operation submitted with async:true. Returns pending, completed, or failed status.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | yes | The operation ID returned by the async submission. |

## `cancel_operation`

Cancels a queued FlutterPilot operation before it starts. Already-running VM calls are allowed to finish safely.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | yes | The operation ID returned by the original tool call. |

## `connect_app`

Connects or reconnects FlutterPilot to a running Flutter application. If uri is omitted, it automatically scans localhost for an active Flutter debug session.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `uri` | string | no | Optional VM Service URI (e.g. "http://127.0.0.1:12345/abcdefg=/"). If omitted, auto-discovers. |

## `list_connected_devices`

Lists all registered Flutter devices/instances in the multi-device fleet and which one is active.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `register_device`

Registers a new device or instance in the multi-device fleet with its name and VM Service URI.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | A unique identifier or name (e.g. "ios_pro_max", "pixel_8", "web_chrome"). |
| `uri` | string | yes | The VM Service WebSocket URI for that device. |

## `switch_device`

Switches the active device to target for all subsequent inspection and UI automation commands.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | The ID or name of the registered device to switch to. |

## `get_errors`

Retrieve the most recent unhandled exceptions and stack traces with duplicate aggregation. CALL THIS whenever you suspect a crash or logic failure.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_recent_events`

Retrieves all buffered proactive events (up to 50: errors, taps, state changes) from the stream. Use this to catch up on what happened while you were processing or if the user interacted with the app manually.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_build_config`

Reads the project's pubspec.yaml and returns the app name, version, Flutter/Dart SDK constraints, and dependency list. Use this to understand what packages are available before suggesting code that requires them.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `read_dart_file`

Reads a Dart source file from the connected Flutter project. The path is relative to the project root (where pubspec.yaml is). Use this to give the AI agent codebase context: read widgets, models, routes, or test files before making changes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `path` | string | yes | Relative or absolute path to the Dart file. Relative paths resolve from the project root. |

## `list_dart_files`

Lists all .dart files in the Flutter project under the given directory (defaults to "lib"). Returns relative paths from the project root. Use to explore project structure before reading files.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `directory` | string | no | Subdirectory to search for Dart files (e.g. "lib", "test"). Defaults to project root if omitted. |

## `get_debug_logs`

Returns captured console output from the running app — including print(), debugPrint(), and dart:developer log() calls. Supports search query, level filter ("debug", "info", "warning", "error"), since_seconds, and limit.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `level` | string | no | Filter by log level: "debug", "info", "warning", or "error". Omit to return all levels. |
| `query` | string | no | Search string to filter log messages. |
| `since_seconds` | integer | no | Only return logs captured within the last N seconds. |
| `limit` | integer | no | Maximum number of log entries to return (default: 100). |
| `logger` | string | no | Filter by logger name (partial match). E.g. "debugPrint", "stdout", "print". |

## `clear_debug_logs`

Clears captured console logs (server and in-app buffers). Use this before a specific test scenario so you get a clean baseline.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_capabilities`

Returns the server capabilities: connection status, loaded plugins, available state managers, buffer sizes, and configuration. CALL THIS FIRST to discover what plugins and tools are available before attempting state inspection or plugin-specific operations.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `profile_frame_budget`

Microsecond Frame Budget & Jank Pinpointer: Analyzes rolling 120-frame timings (Build, Raster, Total) and identifies whether UI thread (build/layout) or GPU thread (raster) is causing dropped frames.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_stream_logs`

Real-Time WebSocket & Stream Channel Inspector: Returns captured incoming and outgoing real-time messages (WebSockets, Supabase Realtime, EventStreams). Supports channel filter.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `channel` | string | no | Optional channel name to filter messages by. |

## `tap_at`

Simulates a physical tap at specific (x, y) coordinates. Prefer `tap_widget` if you have a Key.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `x` | number | yes | X screen coordinate in logical pixels. Screen origin is top-left. |
| `y` | number | yes | Y screen coordinate in logical pixels. Screen origin is top-left. |

## `tap_widget`

Finds a widget by Key, Virtual Semantic Selector (e.g. "ElevatedButton['Log In']"), semantics identifier, visible text, or coordinates, and taps it. Works reliably across all screen sizes and device types without needing hardcoded coordinates. PREREQUISITES: Call get_interactive_elements or get_widget_tree to discover available widgets. The response reports whether the route changed, post-action state, and widget-tree diff.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | ValueKey string, semantic selector (e.g. "ElevatedButton['Sign In']"), visible button text, or icon name (e.g. "IconButton['settings']"). |
| `identifier` | string | no | Semantics identifier property (Flutter 3.19+) for robust AI targeting. |
| `semanticsId` | integer | no | Numeric SemanticsNode ID from get_semantics_tree for accessibility-first interaction. |
| `text` | string | no | Visible text content within the widget to tap. |
| `type` | string | no | Widget runtime type, e.g. "ElevatedButton", "TextButton", "IconButton". |
| `maxAttempts` | integer | no | Max scroll attempts if widget is off-screen (default: 8). |
| `x` | number | no | Optional direct X screen coordinate. |
| `y` | number | no | Optional direct Y screen coordinate. |

## `enter_text`

Types text into a TextField, TextFormField, or editable widget. Can target by Key, identifier, or into the currently focused element if key is omitted or focused_element: true. Automatically updates the TextEditingController and fires onChanged/onSubmitted callbacks. AFTER: The text field now contains the new text. You may need to tap a submit button or call press_key("enter").

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | The text to enter into the text field. |
| `key` | string | no | Optional ValueKey string, selector (e.g. "TextField['Email']"), or label of the text field to type into. |
| `identifier` | string | no | Optional semantics identifier of the text field. |
| `focused_element` | boolean | no | If true, enters text into the currently focused text field without requiring a key. |
| `clear_first` | boolean | no | Whether to clear existing text before typing (default: true). |

## `press_key`

Presses a key on the focused widget: "enter" (submits a text field), "tab", "escape" (closes menus/dialogs), arrow keys, and shortcuts with modifiers (shift, ctrl, alt, meta). The response says which widget received it. To change text use enter_text / clear_text_field — editing keys like backspace are handled by the OS on desktop.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | Key name to press, e.g. "enter", "tab", "escape", "backspace", "arrowDown", "arrowUp", "space", or single characters. |
| `modifiers` | array | no | Optional modifier keys: "shift", "ctrl", "alt", "meta". |

## `secondary_tap`

Performs a secondary tap (right-click / context tap) on a widget or coordinates. Useful for triggering desktop/web context menus.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey or selector of the widget. |
| `identifier` | string | no | Semantics identifier of the widget. |
| `text` | string | no | Visible text of the widget. |
| `type` | string | no | Widget runtime type. |
| `x` | number | no | Optional direct X coordinate. |
| `y` | number | no | Optional direct Y coordinate. |

## `pinch_zoom`

Simulates a two-finger pinch-to-zoom gesture on a widget or at coordinates. Scale > 1 zooms in, scale < 1 zooms out.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `scale` | number | yes | Zoom scale factor (e.g. 1.5 to zoom in, 0.75 to zoom out). |
| `key` | string | no | The ValueKey or selector of the target widget. |
| `identifier` | string | no | Semantics identifier of the target widget. |
| `x` | number | no | Optional center X coordinate for pinch gesture. |
| `y` | number | no | Optional center Y coordinate for pinch gesture. |

## `scroll_into_view`

Ensures a widget is visible by scrolling its parent list. Works with Keys, semantic selectors, or text labels.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string, semantic selector, or label of the widget to scroll into view. |
| `target` | string | no | Same as key (either name works). |
| `maxAttempts` | integer | no | Max scroll attempts to locate the widget in lazy lists (default: 8). |

## `double_tap_widget`

Double-taps a widget by Key (two rapid taps). Use for zoom gestures, selection toggles, or any widget that responds to double-tap.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to double-tap. Use get_widget_tree to find keys. |
| `target` | string | no | Same as key (either name works). |

## `long_press_widget`

Long-presses a widget by Key. Use to trigger context menus, drag handles, or long-press actions. Optional durationMs (default 600).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to long-press. |
| `target` | string | no | Same as key (either name works). |
| `durationMs` | integer | no | Duration of the long press in milliseconds (default: 600ms). |

## `swipe_widget`

Swipes on a widget in a direction (up/down/left/right). Use to scroll lists, dismiss cards, open drawers, or trigger swipe actions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to swipe. |
| `target` | string | no | Same as key (either name works). |
| `direction` | string | yes |  |
| `distance` | number | no | Scroll distance in logical pixels. Positive = down/right, negative = up/left. |

## `drag_widget`

Drags one widget onto another by Key. Use for drag-and-drop reordering, drag targets, or drop zones.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fromKey` | string | yes | The ValueKey string of the widget to drag from (drag source). |
| `toKey` | string | yes | The ValueKey string of the target widget to drag to (drop target). |

## `clear_text_field`

Clears the text of a TextField / TextFormField identified by its widget key. Equivalent to select-all then delete. Use enter_text to type new content afterwards.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the text field to clear. |
| `target` | string | no | Same as key (either name works). |

## `focus_widget`

Taps the centre of the widget identified by key to request focus (opens the software keyboard for a TextField). Use unfocus_all to close the keyboard afterwards.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to focus. |
| `target` | string | no | Same as key (either name works). |

## `unfocus_all`

Removes focus from all widgets and dismisses the software keyboard. Call this after finishing text input to close the keyboard before taking screenshots or tapping other elements.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `set_text_scale_factor`

Overrides the app-wide text scale factor for accessibility testing. Common values: 1.0 (default), 1.5 (large), 2.0 (extra-large), 3.0 (maximum). Pass 0 to reset to system default. Requires the app to wrap MaterialApp with a MediaQuery that listens to FlutterPilot.textScaleNotifier.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `scale` | number | yes | Text scale factor (1.0 = normal, 2.0 = double size, 0.5 = half size). Test accessibility at 2.0. |

## `set_slider_value`

Sets the value of a Slider widget identified by key. Computes the correct tap position for the target value based on the slider's min/max range and dispatches a pointer event. The value is clamped to [min, max].

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the Slider widget. |
| `target` | string | no | Same as key (either name works). |
| `value` | number | yes | The new slider value. Must be within the slider min/max range. |

## `toggle_checkbox`

Taps the centre of the first Checkbox, Switch, or Radio widget found under the given key to toggle its state. Use get_widget_properties to read the resulting isChecked value.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the Checkbox, Switch, or Radio widget to toggle. |
| `target` | string | no | Same as key (either name works). |

## `pump_frames`

Waits for a specified number of vsync animation frames to complete. Use this to let animations, timers, or async widget builds settle without needing a full wait_for_animation call. Max 120 frames.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `count` | integer | no | Number of frames to pump. Use 1–5 for immediate animations, 60 for ~1 second of wall time. |

## `simulate_deep_link`

Simulates opening a deep link URL, triggering the same routing path as an OS-level deep link (e.g., "myapp://product/123" or "/product/123"). Use this to test deep link handlers, share links, and notification tap flows.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `url` | string | yes | The URL pattern to intercept (exact match or prefix). |

## `press_back`

Simulates pressing the hardware/system back button. Pops the current route from the Navigator. Reports whether a route was actually popped (false if already at root).

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `fill_form`

Fills multiple form fields in a single shot using Virtual Semantic Selectors or keys, with optional one-shot form submission. Eliminates multiple turn delays when testing forms.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fields` | object | yes | Map of field selectors to text values (e.g. {"TextField['Email']": "test@flutterpilot.dev", "TextField['Password']": "secret"}). |
| `submitWith` | string | no | Optional selector or key of the submit button to tap after filling (e.g. "ElevatedButton['Log In']"). |

## `wait_for_condition`

Reliably polls until a target element or semantic selector is visible on screen, or until timeout. Prevents flaky test timing during async loading spinners or page transitions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Same as selector. |
| `target` | string | no | Same as selector. |
| `selector` | string | no | Semantic selector or key to wait for (e.g. "Text['Dashboard']" or "order_confirmed_icon"). |
| `timeoutMs` | integer | no | Maximum milliseconds to wait before failing (default: 3000). |

## `audit_screen_health`

Performs an autonomous UI & layout audit on the active screen. Detects yellow-black striped RenderFlex overflows and tap targets below the platform minimum (48dp on phones, 24px on desktop/web).

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `execute_action_chain`

Executes a batch sequence of UI actions (taps, text entries) inside the Flutter engine at native speed. Eliminates multi-turn LLM latency when the sequence of steps is already known.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `actions` | array | yes | List of action objects, e.g. [{"action": "tap", "target": "Icon['menu']"}, {"action": "enterText", "target": "TextField['Search']", "text": "theme"}]. |

## `tap_and_wait`

Macro composite tool: Taps a target widget and immediately waits for an expected widget to appear. Replaces 2 separate round-trip tool calls with 1 fast step.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Same as target. |
| `target` | string | no | Key, semantic selector, or text of the widget to tap (e.g. "login_btn", "Button['Submit']"). |
| `expect` | string | yes | Key, semantic selector, or text of the widget expected to appear (e.g. "home_dashboard", "Text['Welcome']"). |
| `timeout` | integer | no | Timeout in milliseconds to wait for the expected widget (default: 5000ms). |

## `enter_text_and_submit`

Macro composite tool: Enters text into an input field and immediately taps a submit button. Executes both steps in a single tool call.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Same as target. |
| `target` | string | no | Key or semantic selector of the text field (e.g. "email_input", "TextField['Email']"). |
| `text` | string | yes | Text string to enter into the field. |
| `submitTarget` | string | yes | Key or semantic selector of the submit button to tap after entering text (e.g. "submit_btn", "Button['Continue']"). |

## `fill_form_batch`

Atomic Form Auto-Filler Macro: Fills multiple input fields and toggles checkboxes/switches in a single frame pass (<5ms) and optionally submits. Reduces 5+ agent turns to 1.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fields` | object | yes | Map of field targets (keys/selectors) to values (string for TextFields, bool for Checkboxes/Switches). Example: {"TextField['Email']": "alice@test.com", "Checkbox['Terms']": true} |
| `submitTarget` | string | no | Optional key or selector of the submit button to tap after filling all fields. |

## `native_screenshot`

Captures the simulator screen at the OS/framebuffer level via `xcrun simctl` — unlike capture_screenshot, this sees native dialogs, the system keyboard, and any OS chrome layered above the Flutter view. macOS + iOS Simulator only.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_tap`

Taps native screen coordinates via `idb ui tap` — reaches system permission dialogs, alerts, and other OS chrome that tap_widget/tap_at cannot see because they are not part of the Flutter widget tree. Use native_screenshot first to find coordinates. Requires idb (brew install idb-companion && pip3 install fb-idb). macOS + iOS Simulator only.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `x` | number | yes | X coordinate in the native screenshot's pixel space. |
| `y` | number | yes | Y coordinate in the native screenshot's pixel space. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_text`

Types text into the currently-focused native field via `idb ui text` — for native alert text fields, Safari, or anything outside the Flutter engine. For text fields inside the Flutter app itself, use enter_text instead (it is faster and semantic). Requires idb. macOS + iOS Simulator only.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | Text to type. |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_button`

Presses a hardware button via `idb ui button` — HOME, LOCK, SIDE_BUTTON, SIRI, or APPLE_PAY. Requires idb. macOS + iOS Simulator only.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `button` | string | yes |  |
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `native_describe_screen`

Returns the native accessibility tree (labels, frames, roles) for whatever is on screen right now via `idb ui describe-all` — including system dialogs and alerts that are invisible to get_widget_tree. Use this instead of guessing pixel coordinates from a screenshot before calling native_tap: it gives you the actual button labels and frames for "Allow"/"Don't Allow"-style native alerts. Requires idb. macOS + iOS Simulator only.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `simulatorUdid` | string | no | Target simulator UDID. Omit to auto-detect when exactly one simulator is booted. |

## `navigate_to`

Programmatically pushes a named route. Useful for jumping directly to a feature screen for testing.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `route` | string | yes | The named route to navigate to (e.g. "/home", "/profile/123"). Must be registered in the app router. |

## `jump_to_screen`

Directly teleports to a deep application screen with optional seed state injection (Riverpod/Bloc/storage). Bypasses lengthy manual onboarding or multi-step checkout clicks.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `route` | string | yes | Target route name (e.g. "/order/123", "/settings/security"). |
| `state` | object | no | Optional map of state seeds to inject before navigation (e.g. {"riverpod:auth": "logged_in"}). |

## `get_navigation_stack`

Show the current navigation history (stack). CALL THIS to understand where the user is in the application flow.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `wait_for_route`

Polls until the current route matches the expected route, or times out. Use instead of sleep() after navigate_to. Default timeout 5000ms.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `route` | string | yes | The route name to wait for (e.g. "/dashboard", "/settings"). |
| `timeoutMs` | integer | no | Maximum milliseconds to wait for the route (default: 5000ms). |

## `wait_for_animation`

Waits until all animations and frame callbacks have settled. Call this before taking screenshots or making assertions after animated transitions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `timeoutMs` | integer | no | Maximum milliseconds to wait for all animations to settle (default: 5000ms). |

## `wait_for_state`

Polls a Riverpod provider or Bloc/Cubit until its current value string contains expectedValue, or until timeoutMs elapses. Use after triggering async operations to assert that state has settled. Requires the matching plugin to be active (RiverpodPilotObserver or BlocPilotObserver).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string | yes |  |
| `name` | string | yes | State identifier. For Riverpod: the provider's runtimeType string (e.g. "StateProvider<int>"). For Bloc: the bloc's runtimeType string (e.g. "CounterCubit"). |
| `expectedValue` | string | yes | Substring expected in the state's toString() output |
| `timeoutMs` | integer | no | Milliseconds to wait before timing out (default 5000) |

## `set_device_rotation`

Rotates the device to portrait or landscape orientation. Use to test responsive layouts, orientation-locked screens, and rotation animations.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `orientation` | string | yes |  |

## `set_locale`

Switch app language (e.g., "en", "de_DE"). Use this to check for text overflows in different languages.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `locale` | string | yes | BCP-47 locale tag (e.g. "en", "fr", "ar", "zh-CN"). Use "system" to restore the device default. |

## `set_theme`

Toggle Light/Dark mode. Use this to verify design consistency across themes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `theme` | string | yes |  |

## `capture_screenshot`

Capture an image of the current screen for visual analysis. Defaults to a scaled-down PNG (0.5x) for fast, token-efficient AI vision — measured ~56ms vs ~456ms at full resolution on a real device. Pass scale: 1.0 for a full-resolution capture, or format: "jpeg" with a quality if you specifically want lossy compression (jpeg re-encoding is server-side pure-Dart and costs more than PNG at the same scale, so it is opt-in, not the default).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `format` | string | no |  |
| `scale` | number | no | Scale factor between 0.2 and 1.0 (default: 0.5 — fast, token-efficient). Pass 1.0 for full resolution. |
| `quality` | integer | no | JPEG compression quality 10-100 (default: 80 for jpeg). |

## `save_screenshot_baseline`

Captures the current screen and stores it as a named baseline image for future visual regression comparisons. Call this once to establish a golden image, then use compare_screenshot after code changes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | A unique name for this baseline image (e.g. "home_screen", "login_dark"). Used to reference it in compare_screenshot. |

## `compare_screenshot`

Captures the current screen and compares it pixel-by-pixel with a previously saved baseline. Returns the percentage of changed pixels. Use for visual regression testing.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Baseline name set by save_screenshot_baseline |
| `threshold` | number | no | Allowed diff % before test fails (default 1.0 = 1%) |

## `get_widget_tree`

Retrieve the widget hierarchy with screen coordinates (x, y, width, height) and semantic selectors. Automatically performs Semantic Compaction (prunes non-actionable layout wrappers) to save 80% token costs. Pass rootKey/rootSelector to scope capture to a specific dialog/form/sheet (90% extra savings).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `rootKey` | string | no | Optional widget key or semantic selector (e.g. "checkout_form", "Button['Save']") to scope the tree capture to only that subtree. |
| `maxDepth` | integer | no | Maximum tree depth to traverse (default: 50). Lower values return faster for complex UIs. |
| `compact` | boolean | no | Whether to prune intermediate unkeyed layout containers (default: true). Reduces tokens by 80%. |

## `get_interactive_elements`

Discovers all actionable, interactive widgets currently visible and hittable on screen (buttons, text fields, checkboxes, switches, sliders, clickable cards, list tiles). Filters out offstage, occluded, or covered widgets using Flutter hit testing. Returns a clean, compact list with bounds, keys, identifiers, and visible labels.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `types` | array | no | Optional filter for specific widget types (e.g. ["ElevatedButton", "TextField"]). |

## `get_app_summary`

CALL THIS FIRST. One-call overview of the running app: current route, the tappable elements on screen (labels + keys), focused widget, recent errors and logs, frame timing, viewport. Use get_widget_tree for layout structure and capture_screenshot for visuals.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_widget_tree_diff`

Delta Widget Tree Inspector: Compares current screen with the previously captured tree and returns only added, removed, or updated elements. Saves 95% token consumption.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxDepth` | integer | no | Maximum depth to inspect (default: 50). |
| `compact` | boolean | no | Whether to prune intermediate layout wrappers (default: true). |

## `get_widget_properties`

Reads the semantic properties of a widget identified by its key. Returns: type, text (Text/TextField content), isEnabled (onPressed/onTap/onChanged non-null), isChecked (Checkbox/Switch), value/min/max (Slider), isFocused, and screen-space bounds. Use this instead of screenshots to verify widget state.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to inspect. |
| `target` | string | no | Same as key (either name works). |

## `get_semantics_tree`

Returns the full accessibility semantics tree as seen by screen readers (VoiceOver/TalkBack). Each node has: id, label, value, hint, tooltip, role flags (isButton/isTextField/isSlider/isImage/isLink/isLiveRegion), isChecked, isEnabled, isFocused, and screen-space rect. Use this for accessibility audits. Use maxDepth to limit tree size (default: 50).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxDepth` | integer | no | Maximum tree depth to traverse (default: 50). Lower values for faster results. |

## `get_self_heal_status`

Check if the application is currently in an unstable/crash state. Use this to verify if your last fix worked or if a new crash was intercepted.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_latest_crash_report`

Retrieve the most recent structured crash report. CALL THIS immediately if you receive a Self-Heal notification or if `get_self_heal_status` returns UNSTABLE.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_flight_log`

Retrieves the chronological 30-60 second rolling flight recorder timeline (user taps, route changes, state mutations, and network requests) leading up to the current state or crash.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `clear_flight_log`

Clears the flight recorder event buffer.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `diagnose_last_error`

Alias for `get_latest_crash_report`. Returns structured crash diagnostics and state inspection.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `hot_reload`

Recompile edited .dart files and hot reload them into the running app, keeping state. CALL THIS after modifying Dart source. Requires the app to be started with `flutter run` or an IDE debug session.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `hot_restart`

Recompile and hot restart the app (state is reset). CALL THIS for changes hot reload cannot apply: main(), initState, global/static initializers, enums, generic type changes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_riverpod_state`

Inspect current values of all active Riverpod providers. Returns provider name, current value (as string), value type, and timestamp. PREREQUISITES: App must use flutterpilot_riverpod plugin with RiverpodPilotObserver. Use get_capabilities first to check if the riverpod plugin is loaded. COMMON ERRORS: Empty result means no providers are active or plugin is not registered.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `set_riverpod_state`

Inject a new state into a Riverpod provider. Use the provider name or notifier name from `get_riverpod_state`. Accepts plain values (e.g. 42, "active", true) or JSON.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `provider` | string | no | The Riverpod provider name (e.g. "counterProvider", "FeedNotifier"). |
| `name` | string | no | Alias for provider. |
| `target` | string | no | Alias for provider. |
| `value` | any | yes | The new state value to inject. Can be a primitive value (int, bool, string) or JSON string. |

## `batch_set_state`

Atomic multi-state setter: Injects multiple state values at once (Riverpod, Bloc) in 1ms. Eliminates multi-turn LLM latency when seeding test fixtures or forms.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string | no | State management type: "riverpod" or "bloc" (default: "riverpod"). |
| `states` | object | yes | Map of provider/bloc names to their new values, e.g. {"counterProvider": 10, "themeProvider": "dark", "isLoggedIn": true}. |

## `get_bloc_state`

Inspect the current states of all active Blocs and Cubits. CALL THIS to verify business logic transitions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `set_bloc_state`

Force a new state into a Bloc or Cubit. Use the Bloc/Cubit class name from `get_bloc_state`. The `state` should be a JSON string (e.g. "42", "true").

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `cubit` | string | yes | The Bloc/Cubit class name as registered (e.g. "CounterCubit", "AuthBloc"). |
| `state` | string | yes | The new state value to inject. Use JSON-serializable representation. |

## `get_network_logs`

View recent HTTP requests and responses (bodies truncated and redacted; mock status shown). CALL THIS if an API call failed or to verify network payload accuracy.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_hive_contents`

Dump the contents of all registered Hive boxes. CALL THIS to verify local persistent storage.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `list_drift_tables`

List all tables in the SQLite (Drift) database.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `dbName` | string | no | The Drift database name registered via FlutterPilot. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `query_drift`

Execute a raw SQL SELECT query on the local database. CALL THIS to verify complex data relationships or transaction history.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `dbName` | string | yes | The Drift database name registered via FlutterPilot. |
| `sql` | string | yes | A SQL SELECT, EXPLAIN, or WITH query. Write-operations (INSERT/UPDATE/DELETE) are blocked. |

## `list_sqflite_databases`

List all sqflite databases registered with FlutterPilot. PREREQUISITES: App must use flutterpilot_sqflite plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `list_sqflite_tables`

List all tables in a sqflite database. PREREQUISITES: App must use flutterpilot_sqflite plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `dbName` | string | no | The sqflite database name registered via FlutterPilot. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `query_sqflite`

Execute a read-only SQL SELECT query on a sqflite database. Only SELECT/EXPLAIN/PRAGMA/WITH are allowed — write operations are blocked. PREREQUISITES: App must use flutterpilot_sqflite plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `dbName` | string | yes | The sqflite database name registered via FlutterPilot. |
| `sql` | string | yes | A read-only SQL query (SELECT, EXPLAIN, PRAGMA, WITH). Write operations are blocked. |

## `exec_sql_query`

Unified SQL Query Executor: Auto-detects active database (Sqflite or Drift) and executes a safe SQL query (SELECT, WITH, PRAGMA, EXPLAIN). Returns structured result rows.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `sql` | string | yes | SQL statement to execute. |
| `database` | string | no | Optional database name if multiple databases exist. |

## `get_shared_preferences`

Returns all SharedPreferences keys and their typed values (String, int, double, bool, List<String>). Values matching sensitive key patterns (token, password, secret, auth, etc.) are redacted by default — pass showSensitive=true to reveal them. Requires the flutterpilot_shared_preferences plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | string | no | Set to "true" to reveal values for sensitive-looking keys. Default: redacted. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `set_shared_preference`

Writes a key-value pair to SharedPreferences. Specify type as: string (default), int, double, bool, or stringList (JSON array, e.g. '["a","b"]').

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The SharedPreferences key to set. |
| `value` | string | yes | The value to set as a string. Booleans: "true"/"false". Numbers: numeric string. |
| `type` | string | no | Value type: "string", "bool", "int", "double", or "stringList" (comma-separated). |

## `clear_shared_preferences`

⚠ DESTRUCTIVE — Removes SharedPreferences entries. If key is specified, only that key is removed. To clear ALL preferences, omit key and pass confirm="CLEAR_ALL". Cannot be undone.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The specific key to remove. Omit to clear ALL preferences (requires confirm). |
| `confirm` | string | no | Required when clearing all keys (no "key" given). Must be "CLEAR_ALL". |

## `simulate_network`

Simulates a network condition for all Dio HTTP requests. Use to test offline states, loading skeletons, and slow-connection UX. Conditions: normal | slow_3g | fast_4g | offline.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `condition` | string | yes |  |

## `mock_http_response`

Registers a URL pattern mock so that any Dio request whose URL contains urlPattern returns a synthetic response instead of hitting the network. Use to test error states, empty states, or edge-case API responses. Call clear_http_mocks to remove mocks when done.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `urlPattern` | string | yes | Substring of the URL to match (e.g. "/api/users") |
| `statusCode` | integer | yes | HTTP status code (e.g. 200, 404, 500) |
| `body` | string | yes | Response body as a JSON string (e.g. '{"error":"not found"}') |
| `delayMs` | integer | no | Artificial delay in milliseconds before returning the mock (default 0) |

## `clear_http_mocks`

Removes a specific URL pattern mock, or all mocks if urlPattern is omitted. Always call this after testing a mocked flow to restore real network behaviour.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `urlPattern` | string | no | Pattern to remove. Omit to clear ALL mocks. |

## `start_recording`

Starts recording manual interactions. User should perform the flow in the app while this is active.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `stop_and_generate_test`

Stops recording and returns a log of actions. Use your LLM capability to convert this log into a Flutter `testWidgets` block.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `list_custom_tools`

Discover additional app-specific tools registered by the developer.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `call_custom_tool`

Executes an app-specific tool defined by the developer. CALL THIS if you see a relevant tool listed in `list_custom_tools`.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | The custom tool name as registered via FlutterPilot.registerCustomTool(). |
| `params` | object | no |  |

## `assert_widget_visible`

Asserts that a widget with the given Key is present and has layout. Returns error if the assertion fails — treat this as a test failure.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to assert is visible. |
| `target` | string | no | Same as key (either name works). |

## `assert_text_visible`

Asserts that the given text is visible on screen. Set exact=true for exact match, false (default) for substring match.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `text` | string | yes | The text string to assert is visible on screen. |
| `exact` | boolean | no | If true, requires an exact text match. If false (default), a substring match is used. |

## `assert_widget_count`

Asserts the exact number of widgets of a given type (e.g. "ListTile", "ElevatedButton") on screen. Returns error if count does not match.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `type` | string | yes | Widget type name to count (e.g. "ElevatedButton", "Text", "ListTile"). |
| `count` | integer | yes | Expected number of widgets of the given type. |

## `assert_widget_enabled`

Asserts that the widget identified by key is ENABLED (has a non-null onPressed / onTap / onChanged callback). Returns error if the widget is disabled or not found.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to assert is enabled. |
| `target` | string | no | Same as key (either name works). |

## `assert_widget_disabled`

Asserts that the widget identified by key is DISABLED (onPressed / onTap / onChanged is null). Returns error if the widget is enabled or not found.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | The ValueKey string of the widget to assert is disabled. |
| `target` | string | no | Same as key (either name works). |

## `get_memory_details`

Returns a detailed memory breakdown of the running app: heap used, heap capacity, external (native) memory, and RSS for every Dart isolate. Use this to detect memory leaks or unexpected growth. Heap > 200 MB or external > 50 MB usually warrants investigation.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_allocation_profile`

Returns the top Dart classes by current heap allocation (like the DevTools Memory tab class list). Use this to find memory leaks — look for classes with unexpectedly high instance counts or byte sizes. Accepts optional limit (default 30) for number of classes to show.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `limit` | integer | no | Number of top classes to show, sorted by heap bytes (default: 30). |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_http_profile`

Returns all HTTP requests made by the app — URL, method, status code, duration, and request/response size. This is the DevTools Network tab in your AI agent. Use this to debug API calls, check for slow requests (>2s), or confirm the app actually sent a request. Optional limit (default 50) caps the number of requests shown.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `limit` | integer | no | Maximum number of requests to return, most recent first (default: 50). |
| `status_filter` | integer | no | Optional HTTP status code filter (e.g. 404, 500). Omit to return all requests. |

## `clear_http_profile`

Clears the HTTP request history so you get a clean baseline before triggering a specific API call. Pair with get_http_profile.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_vm_info`

Returns Dart VM version, process ID, all running isolates and their pause/run state. Use this to confirm which Dart version the app is running on, or to check isolate health.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `toggle_repaint_rainbow`

Enables or disables the repaint rainbow overlay (each layer that repaints cycles through colors). Use this to visually identify which parts of the UI are repainting more than expected — a classic Flutter performance debugging technique.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to enable the repaint rainbow overlay, false to disable. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `toggle_debug_paint`

Enables or disables debug paint — shows layout padding (blue), widget boundaries (orange), baselines (green), and pointer hit areas. Use this to debug layout issues like unexpected padding or misaligned widgets.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to show debug paint boundaries and padding, false to hide. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `toggle_slow_animations`

Slows all animations to 1/5 speed (timeDilation=5) or restores normal speed (timeDilation=1). Use this to visually inspect animation curves, catch jank frames, or verify transition correctness. Set enabled=false to restore normal speed.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to slow animations to 1/5 speed (timeDilation=5), false to restore normal speed. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_supabase_auth`

Inspect current Supabase auth state: user profile, session, JWT expiry, and recent auth events. Pass showSensitive=true to reveal email/phone. PREREQUISITES: App must use flutterpilot_supabase plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | string | no | Set to "true" to reveal email/phone/user_id. Default: redacted. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_supabase_realtime`

List all active Supabase Realtime channel subscriptions. Shows topic, join status, and close status.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `query_supabase_table`

Query rows from a Supabase table using the project's own credentials. Returns up to `limit` rows (default 20, max 200). Optionally filter with "column=value" equality. Useful for inspecting data during debug. PREREQUISITES: App must use flutterpilot_supabase plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `table` | string | no | Supabase table name (required). |
| `limit` | string | no | Max rows to return (1–200, default 20). |
| `filter` | string | no | Optional equality filter in "column=value" format, e.g. "user_id=abc123". |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `supabase_sign_out`

⚠ MAKES REAL NETWORK CALL — signs out the current Supabase user via the Supabase Auth API. This affects the real session. Scope: "local" (default, this device only), "global" (all devices), "others" (other sessions only). Only use in dev/test environments.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `scope` | string | no | Sign-out scope: "local" (this device), "global" (all devices), "others". |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `supabase_refresh_session`

⚠ MAKES REAL NETWORK CALL — force-refreshes the current Supabase session token via the Supabase Auth API. Use when testing token expiry flows. Only use in dev/test environments.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_gorouter_state`

Inspect the current GoRouter navigation state: location, path parameters, query parameters, matched routes, and whether pop is available.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_gorouter_config`

List all registered GoRouter routes and their configuration (paths, names, children).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_gorouter_history`

View the recent navigation history — timestamped list of route changes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `gorouter_navigate`

Navigate using GoRouter. Actions: "go" (replace stack), "push" (add to stack), "replace" (replace current), "pop" (go back). Requires location for go/push/replace.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `location` | string | no | The route path to navigate to (e.g. "/home", "/user/123"). |
| `action` | string | no | Navigation action. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_connectivity`

Check current network connectivity status: wifi, mobile, ethernet, vpn, none. Also shows whether simulated-offline mode is active.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_connectivity_history`

View timestamped log of connectivity state transitions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `limit` | string | no | Max number of entries to return (default: 100). |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_firebase_status`

Check which Firebase services are registered and their status (Crashlytics, Analytics, Performance, Messaging).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_fcm_token`

Get the Firebase Cloud Messaging token (truncated for security).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `log_analytics_event`

⚠ MAKES REAL NETWORK CALL — logs a custom Firebase Analytics event to your Firebase project (visible in the Firebase console). Useful for verifying analytics instrumentation during development. Do not call in production test runs to avoid polluting analytics data.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Event name (e.g. "button_pressed", "screen_view"). |
| `params` | string | no | Optional JSON object of event parameters (e.g. '{"button_id":"submit"}'). |

## `get_analytics_log`

View recent analytics events logged through FlutterPilot.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `limit` | string | no | Max number of events to return (default: 200). |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `start_performance_trace`

Start a named Firebase Performance trace. Use stop_performance_trace to end it.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Trace name (e.g. "checkout_flow", "data_sync"). |

## `stop_performance_trace`

Stop a previously started Firebase Performance trace.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Trace name that was passed to start_performance_trace. |

## `record_crashlytics_error`

⚠ MAKES REAL NETWORK CALL — records a test error in Firebase Crashlytics (appears in your Firebase console). Useful for verifying crash reporting instrumentation. Do not call repeatedly or in CI — it pollutes your production Crashlytics dashboard.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `message` | string | no | Error message to record. |
| `fatal` | string | no | "true" for fatal error, "false" for non-fatal (default). |

## `get_secure_storage_keys`

List all keys in FlutterSecureStorage. Values are redacted by default. Pass showValues=true to reveal (sensitive keys like passwords are always redacted).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showValues` | string | no | "true" to reveal values (except always-redacted keys). |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `read_secure_storage_key`

Read a specific key from FlutterSecureStorage. Keys matching password/secret/api_key patterns are always redacted.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The key to read. |

## `set_secure_storage_key`

Write a key-value pair to FlutterSecureStorage. Use for test data injection.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The key to set. |
| `value` | string | yes | The value to store. |

## `delete_secure_storage_key`

⚠ DESTRUCTIVE — Delete a specific key from FlutterSecureStorage. To wipe ALL keys, omit "key" and pass confirm="DELETE_ALL". Deletion cannot be undone.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | no | Key to delete. Omit to clear ALL secure storage (requires confirm). |
| `confirm` | string | no | Required when wiping all keys (no "key" given). Must be exactly "DELETE_ALL" to proceed. |

