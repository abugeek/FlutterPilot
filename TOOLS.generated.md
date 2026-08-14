# FlutterPilot MCP Tools

Generated from the running server registration. Do not edit manually.

Tool count: 147

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

## `get_app_context`

High-speed batch context fetcher: Concurrently gathers 360° app overview, active errors, and state snapshots (Riverpod/Bloc) in a single ~100ms round-trip. Saves 2-3 tool call latencies at the start of an agent session or after navigation.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_app_summary`

Get a 360-degree overview of the app: current route, widget count, pending errors, loaded plugins, and FPS stats. CALL THIS FIRST upon connecting to orient yourself. AFTER: Use get_widget_tree to find interactable elements, or capture_screenshot to see the visual state.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_errors`

Retrieve the most recent unhandled exceptions and stack traces with duplicate aggregation. CALL THIS whenever you suspect a crash or logic failure.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_recent_events`

Retrieves the last 50 proactive events (errors, taps, state changes) from the stream. Use this to catch up on what happened while you were processing or if the user interacted with the app manually.

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

Returns captured console output from the running app — including print(), debugPrint(), and dart:developer log() calls. This replaces the need to manually copy-paste from VS Code debug console. Use level filter ("debug", "info", "warning", "error") and limit to narrow results. Call this any time you need to see what the app is printing.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `level` | string | no | Filter by log level: "debug", "info", "warning", or "error". Omit to return all levels. |
| `limit` | integer | no | Maximum number of log entries to return. Defaults to 100. Use smaller values for recent output only. |
| `logger` | string | no | Filter by logger name (partial match). E.g. "debugPrint", "stdout", or a custom logger name. |

## `clear_debug_logs`

Clears the captured console log buffer on the server side. Use this before a specific test scenario so you get a clean baseline.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `set_log_filter`

Clears the in-app SDK debug log buffer. Call before a test run to get a clean log window. Tip: pair with get_debug_logs(level:"error") after the action.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_capabilities`

Returns the server capabilities: connection status, loaded plugins, available state managers, buffer sizes, and configuration. CALL THIS FIRST to discover what plugins and tools are available before attempting state inspection or plugin-specific operations.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `assert_ui_health_batch`

Unified 1-Shot UI Screen Health Auditor: Inspects current screen for RenderFlex overflows, touch targets smaller than 48x48 dp, and unlabelled interactive controls in <2ms. Returns a single structured health verdict.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `hot_restart_and_restore`

Fast Hot Restart & State Re-hydration: Automatically snapshots current app state, performs hot restart, and re-applies the saved state snapshot. Keeps the app on the exact same screen and state after restart.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `profile_frame_budget`

Microsecond Frame Budget & Jank Pinpointer: Analyzes rolling 120-frame timings (Build, Raster, Total) and identifies whether UI thread (build/layout) or GPU thread (raster) is causing dropped frames.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `replay_flight_log`

Live Autonomous Flight Replay Engine: Re-executes the recorded rolling 30s user actions, taps, and gestures live inside the running app in fast-forward mode (~150ms per action). Enables instant live reproduction of bugs.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `delayMs` | integer | no | Delay between replayed actions in milliseconds (default: 150ms). |

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

Finds a widget by Key or Virtual Semantic Selector (e.g. "ElevatedButton['Log In']", "Button['Submit']", or plain visible button text "Log In") and taps its center. Works reliably across all devices without needing hardcoded coordinates. PREREQUISITES: Call get_widget_tree to discover available keys or semantic selectors. AFTER: Verify the tap worked with capture_screenshot or a state inspection tool.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string, semantic selector (e.g. "ElevatedButton['Sign In']"), or visible button text to tap. |

## `enter_text`

Types text into a TextField or TextFormField identified by Key or Semantic Selector (e.g. "TextField['Email']", placeholder, or label). Automatically updates the TextEditingController and fires onChanged/onSubmitted callbacks. AFTER: The text field now contains the new text. You may need to tap a submit button.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string, selector (e.g. "TextField['Email']"), or label of the text field to type into. |
| `text` | string | yes | The text to enter into the text field. |

## `scroll_into_view`

Ensures a widget is visible by scrolling its parent list. Works with Keys, semantic selectors, or text labels.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string, semantic selector, or label of the widget to scroll into view. |

## `double_tap_widget`

Double-taps a widget by Key (two rapid taps). Use for zoom gestures, selection toggles, or any widget that responds to double-tap.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to double-tap. Use get_widget_tree to find keys. |

## `long_press_widget`

Long-presses a widget by Key. Use to trigger context menus, drag handles, or long-press actions. Optional durationMs (default 600).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to long-press. |
| `durationMs` | integer | no | Duration of the long press in milliseconds (default: 600ms). |

## `swipe_widget`

Swipes on a widget in a direction (up/down/left/right). Use to scroll lists, dismiss cards, open drawers, or trigger swipe actions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to swipe. |
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
| `key` | string | yes | The ValueKey string of the text field to clear. |

## `focus_widget`

Taps the centre of the widget identified by key to request focus (opens the software keyboard for a TextField). Use unfocus_all to close the keyboard afterwards.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to focus. |

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
| `key` | string | yes | The ValueKey string of the Slider widget. |
| `value` | number | yes | The new slider value. Must be within the slider min/max range. |

## `toggle_checkbox`

Taps the centre of the first Checkbox, Switch, or Radio widget found under the given key to toggle its state. Use get_widget_properties to read the resulting isChecked value.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the Checkbox, Switch, or Radio widget to toggle. |

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
| `selector` | string | yes | Semantic selector or key to wait for (e.g. "Text['Dashboard']" or "order_confirmed_icon"). |
| `timeoutMs` | integer | no | Maximum milliseconds to wait before failing (default: 3000). |

## `audit_screen_health`

Performs an autonomous UI & layout audit on the active screen. Detects yellow-black striped RenderFlex overflow errors (e.g. "overflowed by 14px") and flags touch targets smaller than the standard 48x48 dp accessibility guideline.

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
| `target` | string | yes | Key, semantic selector, or text of the widget to tap (e.g. "login_btn", "Button['Submit']"). |
| `expect` | string | yes | Key, semantic selector, or text of the widget expected to appear (e.g. "home_dashboard", "Text['Welcome']"). |
| `timeout` | integer | no | Timeout in milliseconds to wait for the expected widget (default: 5000ms). |

## `enter_text_and_submit`

Macro composite tool: Enters text into an input field and immediately taps a submit button. Executes both steps in a single tool call.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `target` | string | yes | Key or semantic selector of the text field (e.g. "email_input", "TextField['Email']"). |
| `text` | string | yes | Text string to enter into the field. |
| `submitTarget` | string | yes | Key or semantic selector of the submit button to tap after entering text (e.g. "submit_btn", "Button['Continue']"). |

## `fill_form_batch`

Atomic Form Auto-Filler Macro: Fills multiple input fields and toggles checkboxes/switches in a single frame pass (<5ms) and optionally submits. Reduces 5+ agent turns to 1.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `fields` | object | yes | Map of field targets (keys/selectors) to values (string for TextFields, bool for Checkboxes/Switches). Example: {"TextField['Email']": "alice@test.com", "Checkbox['Terms']": true} |
| `submitTarget` | string | no | Optional key or selector of the submit button to tap after filling all fields. |

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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `wait_for_widget`

Polls until a widget with the given Key appears in the tree, or times out. Use after navigation or async operations. Default timeout 5000ms.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to wait for to appear. |
| `timeoutMs` | integer | no | Maximum milliseconds to wait for the widget (default: 5000ms). |

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
| `timeoutMs` | integer | no | Maximum milliseconds to wait for all animations to settle (default: 5000ms. |

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

Capture an image of the current screen for visual analysis with adaptive compression. Supports scale (e.g. 0.5x) and quality (e.g. 75) to reduce token payload by up to 80%.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `format` | string | no |  |
| `scale` | number | no | Scale factor between 0.25 and 1.0 (default: 1.0). Use 0.5 for fast token-efficient AI vision. |
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

## `get_widget_tree_diff`

Delta Widget Tree Inspector: Compares current screen with the previously captured tree and returns only added, removed, or updated elements. Saves 95% token consumption.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxDepth` | integer | no | Maximum depth to inspect (default: 50). |
| `compact` | boolean | no | Whether to prune intermediate layout wrappers (default: true). |

## `get_screen_hash`

Fast lightweight screen mutation checker (<10 tokens). Returns the 64-bit frame mutation counter and active route. Call this to check if a user action mutated the UI without fetching a full tree.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_widget_properties`

Reads the semantic properties of a widget identified by its key. Returns: type, text (Text/TextField content), isEnabled (onPressed/onTap/onChanged non-null), isChecked (Checkbox/Switch), value/min/max (Slider), isFocused, and screen-space bounds. Use this instead of screenshots to verify widget state.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to inspect. |

## `get_semantics_tree`

Returns the full accessibility semantics tree as seen by screen readers (VoiceOver/TalkBack). Each node has: id, label, value, hint, tooltip, role flags (isButton/isTextField/isSlider/isImage/isLink/isLiveRegion), isChecked, isEnabled, isFocused, and screen-space rect. Use this for accessibility audits. Use maxDepth to limit tree size (default: 50).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `maxDepth` | integer | no | Maximum tree depth to traverse (default: 50). Lower values for faster results. |

## `export_session_gif`

Generates an animated GIF replay artifact of the interaction session or baseline screens. Saves directly to disk (e.g. "artifacts/session_replay.gif") for visual proof in pull requests or reviews.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `outputPath` | string | no | Target file path for the GIF (default: "artifacts/session_replay.gif"). |
| `delayMs` | integer | no | Delay between frames in milliseconds (default: 500). |

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

## `generate_repro_test`

Synthesizes a standalone, executable Flutter widget test (`test/repro_test.dart`) from the continuous Flight Recorder session leading up to a crash or bug. Run the generated test with `flutter test test/repro_test.dart` to verify reproduction and fix.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `testName` | string | no | Optional descriptive name for the test. |
| `widgetName` | string | no | Root widget or screen name to mount (default: "MyApp()"). |
| `writeToDisk` | boolean | no | Whether to automatically write the test to test/repro_test.dart (default: false). |
| `filePath` | string | no | Custom file path to write to (default: "test/repro_test.dart"). |

## `export_test_suite`

Exports recorded user journeys and flight sessions as production-ready test suites for Patrol, standard Flutter Integration Tests, or Widget Tests. Can write the file directly to disk (e.g. integration_test/flow_test.dart or test/flow_test.dart).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `framework` | string | no | Target test framework: "patrol", "integration_test", or "widget_test" (default: "patrol"). |
| `testName` | string | no | Descriptive test name. |
| `appWidget` | string | no | Target app/screen widget name (e.g. "MyApp()", "CheckoutScreen()"). |
| `writeToDisk` | boolean | no | Whether to write generated test to disk (default: false). |
| `filePath` | string | no | File path to write (e.g. "integration_test/checkout_flow_test.dart"). |

## `clear_flight_log`

Clears the flight recorder event buffer.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `diagnose_last_error`

[DEPRECATED] Use `get_latest_crash_report` or `get_flight_log` instead.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `hot_reload`

Trigger a source code hot reload. CALL THIS after you have modified a .dart file to apply the fix to the running app.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `hot_restart`

Trigger a full app hot restart. CALL THIS for structural code changes (main(), providers) or to reset app state.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `generate_pr_report`

Auto-generates a ready-to-paste GitHub Pull Request Markdown report summarizing the verified changes, UI Health Audit (0 overflows), test results, and visual proof replay links.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `title` | string | yes | Pull Request title (e.g. "feat: implement responsive product checkout"). |
| `description` | string | no | Summary of what was built, changed, or fixed. |
| `generatedTestPath` | string | no | Path to synthesized test file if generated (e.g. "integration_test/flow_test.dart"). |
| `gifPath` | string | no | Path to exported session GIF if created (e.g. "artifacts/demo.gif"). |

## `get_riverpod_state`

Inspect current values of all active Riverpod providers. Returns provider name, current value (as string), value type, and timestamp. PREREQUISITES: App must use flutterpilot_riverpod plugin with RiverpodPilotObserver. Use get_capabilities first to check if the riverpod plugin is loaded. COMMON ERRORS: Empty result means no providers are active or plugin is not registered.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `set_riverpod_state`

Inject a new state into a Riverpod provider. Use the provider name (type) from `get_riverpod_state`. The `value` should be a JSON-compatible string (e.g. "42", "true", "\"hello\"").

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `provider` | string | yes | The Riverpod provider name as registered with FlutterPilot.registerStateSetter (e.g. "counterProvider"). |
| `value` | string | yes | The new state value to inject. Use JSON-serializable types. Complex objects should be JSON strings. |

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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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

View the last 50 HTTP requests and responses. CALL THIS if an API call failed or to verify network payload accuracy.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_hive_contents`

Dump the contents of all registered Hive boxes. CALL THIS to verify local persistent storage.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `list_drift_tables`

List all tables in the SQLite (Drift) database.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `dbName` | string | no | The Drift database name registered via FlutterPilot. |
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `list_sqflite_tables`

List all tables in a sqflite database. PREREQUISITES: App must use flutterpilot_sqflite plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `dbName` | string | no | The sqflite database name registered via FlutterPilot. |
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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

## `save_state_snapshot`

Captures a named point-in-time snapshot of the entire running app state (active route, Riverpod/Bloc providers, storage). Use restore_state_snapshot later to rewind to this exact state in <100ms.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Descriptive identifier for the snapshot (e.g. "checkout_with_items"). |

## `restore_state_snapshot`

Instantly rewinds the running app back to a previously captured state snapshot (<100ms) without restarting the app.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Name of the snapshot to restore. |

## `list_state_snapshots`

Lists all available point-in-time state snapshots currently stored in memory.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `delete_state_snapshot`

Deletes a specific state snapshot by name.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Name of the snapshot to delete. |

## `record_fixtures`

Saves current or recent HTTP/Dio network traffic logs as an offline test fixture JSON file (e.g. "test/fixtures/checkout_flow.json"). Enables deterministic offline test execution.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Fixture name (e.g. "checkout_success"). |

## `replay_fixtures`

Loads a recorded network fixture JSON file and registers mock rules for all endpoints, enabling full offline application testing without hitting real backend servers.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `name` | string | yes | Fixture name to load from test/fixtures/<name>.json. |

## `start_recording`

Starts recording manual interactions. User should perform the flow in the app while this is active.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `stop_and_generate_test`

Stops recording and returns a log of actions. Use your LLM capability to convert this log into a Flutter `testWidgets` block.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `list_custom_tools`

Discover additional app-specific tools registered by the developer.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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
| `key` | string | yes | The ValueKey string of the widget to assert is visible. |

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
| `key` | string | yes | The ValueKey string of the widget to assert is enabled. |

## `assert_widget_disabled`

Asserts that the widget identified by key is DISABLED (onPressed / onTap / onChanged is null). Returns error if the widget is enabled or not found.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `key` | string | yes | The ValueKey string of the widget to assert is disabled. |

## `get_perf_metrics`

Get current FPS and Heap Memory usage. CALL THIS to verify that code optimizations actually improved performance.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `run_chaos_fuzzing`

Runs autonomous monkey/chaos stress fuzzing against the running Flutter app for a specified duration. Randomly clicks interactive elements, inputs text, and navigates to detect crashes and unhandled exceptions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `durationSeconds` | integer | no | Duration to run chaos fuzzing in seconds (default: 5). |
| `eventRatePerSecond` | integer | no | Rate of chaos events per second (default: 5). |

## `get_memory_details`

Returns a detailed memory breakdown of the running app: heap used, heap capacity, external (native) memory, and RSS for every Dart isolate. Use this to detect memory leaks or unexpected growth. Heap > 200 MB or external > 50 MB usually warrants investigation.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_allocation_profile`

Returns the top Dart classes by current heap allocation (like the DevTools Memory tab class list). Use this to find memory leaks — look for classes with unexpectedly high instance counts or byte sizes. Accepts optional limit (default 30) for number of classes to show.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `limit` | integer | no | Number of top classes to show, sorted by heap bytes (default: 30). |

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

## `get_render_tree`

Dumps the render object tree — the layout/paint layer beneath the widget tree. Use this to debug layout issues, overflow errors, or understand exactly how Flutter is sizing and positioning widgets. This is the DevTools Layout Explorer equivalent for AI agents.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_layer_tree`

Dumps the compositing layer tree — the GPU-level representation of the scene. Use this to debug performance issues caused by unnecessary repaint layers, or to understand why widgets are not composited efficiently.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_vm_info`

Returns Dart VM version, process ID, all running isolates and their pause/run state. Use this to confirm which Dart version the app is running on, or to check isolate health.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `toggle_repaint_rainbow`

Enables or disables the repaint rainbow overlay (each layer that repaints cycles through colors). Use this to visually identify which parts of the UI are repainting more than expected — a classic Flutter performance debugging technique.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to enable the repaint rainbow overlay, false to disable. |

## `toggle_debug_paint`

Enables or disables debug paint — shows layout padding (blue), widget boundaries (orange), baselines (green), and pointer hit areas. Use this to debug layout issues like unexpected padding or misaligned widgets.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to show debug paint boundaries and padding, false to hide. |

## `toggle_slow_animations`

Slows all animations to 1/5 speed (timeDilation=5) or restores normal speed (timeDilation=1). Use this to visually inspect animation curves, catch jank frames, or verify transition correctness. Set enabled=false to restore normal speed.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to slow animations to 1/5 speed (timeDilation=5), false to restore normal speed. |

## `enable_widget_rebuild_tracking`

Enables or disables per-widget rebuild counting (equivalent to DevTools "Track Widget Builds"). After enabling, interact with the app, then call get_debug_logs to see rebuild events, or check the performance overlay via get_perf_metrics. Set enabled=false to stop tracking.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | boolean | yes | true to start tracking per-widget rebuild counts, false to stop. |

## `get_gc_stats`

Returns garbage collection statistics for all Dart isolates: number of GC rounds, total bytes collected, and current heap pressure. High GC frequency (>5/sec) can cause jank.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `audit_memory_health`

Audits Flutter ImageCache memory, checks total allocated megabytes against thresholds, and identifies oversized image allocations (>4x layout size) causing memory bloat.

| Parameter | Type | Required | Description |
|---|---|---:|---|

## `get_supabase_auth`

Inspect current Supabase auth state: user profile, session, JWT expiry, and recent auth events. Pass showSensitive=true to reveal email/phone. PREREQUISITES: App must use flutterpilot_supabase plugin.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `showSensitive` | string | no | Set to "true" to reveal email/phone/user_id. Default: redacted. |
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_supabase_realtime`

List all active Supabase Realtime channel subscriptions. Shows topic, join status, and close status.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `supabase_sign_out`

⚠ MAKES REAL NETWORK CALL — signs out the current Supabase user via the Supabase Auth API. This affects the real session. Scope: "local" (default, this device only), "global" (all devices), "others" (other sessions only). Only use in dev/test environments.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `scope` | string | no | Sign-out scope: "local" (this device), "global" (all devices), "others". |

## `supabase_refresh_session`

⚠ MAKES REAL NETWORK CALL — force-refreshes the current Supabase session token via the Supabase Auth API. Use when testing token expiry flows. Only use in dev/test environments.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_gorouter_state`

Inspect the current GoRouter navigation state: location, path parameters, query parameters, matched routes, and whether pop is available.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_gorouter_config`

List all registered GoRouter routes and their configuration (paths, names, children).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_gorouter_history`

View the recent navigation history — timestamped list of route changes.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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

## `get_connectivity`

Check current network connectivity status: wifi, mobile, ethernet, vpn, none. Also shows whether simulated-offline mode is active.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_connectivity_history`

View timestamped log of connectivity state transitions.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `limit` | string | no | Max number of entries to return (default: 100). |
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `simulate_offline`

Toggle simulated offline mode. When enabled, ConnectivityPilotInspector.isSimulatedOffline returns true. App code can check this flag to simulate offline behavior for testing.

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `enabled` | string | yes | "true" to enable simulated offline, "false" to disable. |

## `get_firebase_status`

Check which Firebase services are registered and their status (Crashlytics, Analytics, Performance, Messaging).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
| `operationId` | string | no | Optional caller-supplied ID, enabling cancellation while queued. |
| `operationDeadlineMs` | integer | no | Optional server deadline, clamped to 100–120000 ms. |
| `async` | boolean | no | Return immediately with an operation ID; poll using get_operation. |
| `deviceId` | string | no | Optional target device. Registered devices can be addressed directly; when omitted, the active device is used. |

## `get_fcm_token`

Get the Firebase Cloud Messaging token (truncated for security).

| Parameter | Type | Required | Description |
|---|---|---:|---|
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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
| `ifMutation` | integer | no | Optional optimistic-concurrency contextVersion. The mutation is rejected if the app changed. |
| `ifVersion` | integer | no | Alias for ifMutation. |
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

