# FlutterPilot Tools Reference

Complete reference of all **110+ MCP tools** available through FlutterPilot Server.

**Table of Contents:**
- [Screenshots & Visual Regression](#screenshots--layout) (5 tools)
- [UI Automation & Visual AI Overlay](#ui-automation) (15 tools)
- [Navigation & Routing](#navigation--routing) (8 tools)
- [State & Inspection](#state--inspection) (19 tools)
- [Network Chaos & Mocking](#network-chaos--mocking) (5 tools)
- [Multi-Device Fleet Manager](#multi-device-fleet-manager) (4 tools)
- [Recording & Testing](#recording--testing) (6 tools)
- [Custom Tools](#custom-tools) (3 tools)
- [Performance & DevTools](#performance--devtools) (11 tools)
- [Debug Console](#debug-console) (3 tools)
- [DevTools Deep Inspection](#devtools-deep-inspection) (12 tools)
- [Plugin Integrations](#plugin-integrations) (22 tools)

---

## Screenshots & Layout

### `capture_screenshot`

Capture the current screen as a PNG image.

**Parameters:** None

**Returns:**
```json
{
  "type": "resource",
  "resource": {
    "uri": "data:image/png;base64,iVBORw0KGgoAAAANS...",
    "mimeType": "image/png"
  }
}
```

**Use Cases:**
- AI visual debugging (layout, colors, spacing)
- Test screenshot baselines
- Bug documentation
- Accessibility validation

**Performance:** ~500ms for typical app

---

### `get_widget_tree`

Return the full widget hierarchy as a nested JSON structure.

**Parameters:** None

**Returns:**
```json
{
  "tree": {
    "type": "MaterialApp",
    "key": null,
    "props": {
      "title": "My App",
      "theme": "ThemeData(...)"
    },
    "children": [
      {
        "type": "Scaffold",
        "key": null,
        "props": { "appBar": "AppBar(...)" },
        "children": [
          { "type": "FloatingActionButton", "key": "submitBtn", ... }
        ]
      }
    ]
  }
}
```

**Includes:**
- Widget type name
- Keys (for targeting)
- Properties (text, colors, sizes)
- Full nesting hierarchy
- Creation location (file path + line)

**Use Cases:**
- Understand widget structure
- Locate widgets by key
- Debug layout hierarchy
- Automated UI analysis

---

### `get_widget_properties` `key: string`

Read state from a specific widget by key.

**Parameters:**
```json
{
  "key": "submitButton"
}
```

**Returns:**
```json
{
  "text": "Submit",
  "isEnabled": true,
  "isChecked": null,
  "value": null,
  "isFocused": false,
  "bounds": {
    "x": 100.5,
    "y": 200.0,
    "width": 150.0,
    "height": 50.0
  }
}
```

**Supports Reading:**
- `Text.data` for Text widgets
- `enabled` for buttons/tappables
- `value`/`selected` for Checkbox, Radio, Slider
- `controller.text` for TextFields
- `min`/`max` for Sliders
- Focus state (is this widget focused?)
- Bounds in screen space

**Use Cases:**
- Assert widget state before/after action
- Read form values
- Verify enabled/disabled state
- Get positions for custom interactions

---

### `save_screenshot_baseline` `filename: string`

Save current screenshot as a baseline for regression testing.

**Parameters:**
```json
{
  "filename": "home_screen.png"
}
```

**Returns:**
```json
{
  "success": true,
  "path": "/path/to/baselines/home_screen.png",
  "size": 125432
}
```

**Use Cases:**
- Visual regression testing setup
- Golden master images
- Before/after comparison

---

### `compare_screenshot` `filename: string`

Compare current screenshot to a saved baseline.

**Parameters:**
```json
{
  "filename": "home_screen.png"
}
```

**Returns:**
```json
{
  "match": true,
  "percentage": 100.0,
  "diff": null,
  "baseline": "/path/to/baselines/home_screen.png",
  "current": "data:image/png;base64,..."
}
```

**If differences found:**
```json
{
  "match": false,
  "percentage": 94.2,
  "diff": "data:image/png;base64,...",
  "changes": {
    "pixelsChanged": 5821,
    "areaChanged": "top-right button area"
  }
}
```

**Use Cases:**
- Visual regression detection
- Layout change verification
- Baseline updates

---

## UI Automation

### `tap_at` `x: number, y: number`

Tap at absolute screen coordinates.

**Parameters:**
```json
{
  "x": 250.5,
  "y": 450.0
}
```

**Returns:**
```json
{
  "success": true
}
```

**Notes:**
- Coordinates are in logical pixels (device-independent)
- Use `capture_screenshot` to identify tap locations visually
- Consider using `tap_widget` for device-independent taps

**Use Cases:**
- Tap custom widgets without keys
- Tap at precise coordinates for testing
- Interaction that requires exact position

---

### `tap_widget` `key: string`

Tap a widget at its center by key.

**Parameters:**
```json
{
  "key": "submitButton"
}
```

**Returns:**
```json
{
  "success": true,
  "widgetFound": true,
  "bounds": { "x": 100, "y": 200, "width": 150, "height": 50 }
}
```

**Advantages over `tap_at`:**
- Works on any screen size (device-independent)
- Finds center automatically
- Fails gracefully if widget not found

**Use Cases:**
- Tap buttons, FABs, menu items
- Device-independent test automation
- Form submission

**Widget Key Format:**
```dart
// In your app:
ElevatedButton(
  key: const Key('submitButton'),
  onPressed: () { ... },
  child: Text('Submit'),
)

// In MCP call:
{
  "key": "submitButton"
}
```

---

### `double_tap_widget` `key: string`

Double-tap a widget.

**Parameters:**
```json
{
  "key": "imageGallery"
}
```

**Returns:**
```json
{
  "success": true
}
```

**Use Cases:**
- Zoom in/out
- Select/deselect items in gallery views
- Custom double-tap handlers

---

### `long_press_widget` `key: string`

Long-press a widget (0.5 second hold).

**Parameters:**
```json
{
  "key": "contextMenuItem"
}
```

**Returns:**
```json
{
  "success": true
}
```

**Use Cases:**
- Context menus
- Long-press handlers
- Selection gestures

---

### `enter_text` `key: string, text: string`

Fill a text field with the given text.

**Parameters:**
```json
{
  "key": "emailField",
  "text": "user@example.com"
}
```

**Returns:**
```json
{
  "success": true,
  "finalText": "user@example.com"
}
```

**Notes:**
- Clears existing text first
- Triggers `onChanged` callbacks
- Handles multiline text (with `\n`)

**Use Cases:**
- Form filling
- Text input testing
- Search field entry

---

### `clear_text_field` `key: string`

Clear a text field by key.

**Parameters:**
```json
{
  "key": "searchField"
}
```

**Returns:**
```json
{
  "success": true
}
```

**Use Cases:**
- Reset search/filter
- Clear form before resubmit
- Test empty field validation

---

### `scroll_into_view` `key: string, duration?: number`

Scroll until a widget is visible in the viewport.

**Parameters:**
```json
{
  "key": "bottomItem",
  "duration": 500
}
```

**Returns:**
```json
{
  "scrolled": true,
  "visible": true,
  "scrollDistance": 350.5
}
```

**Parameters:**
- `key` — Widget to scroll to
- `duration` — Animation duration in milliseconds (optional, default 300ms)

**Use Cases:**
- Navigate within scrollable lists
- Ensure widget visible before tap
- Scroll to bottom/top of page

---

### `scroll_by` `dx: number, dy: number, duration?: number`

Scroll by pixel amount (relative, not absolute).

**Parameters:**
```json
{
  "dx": 0,
  "dy": 300,
  "duration": 500
}
```

**Returns:**
```json
{
  "success": true
}
```

**Parameters:**
- `dx` — Horizontal scroll (positive = right, negative = left)
- `dy` — Vertical scroll (positive = down, negative = up)
- `duration` — Animation duration in milliseconds (optional)

**Use Cases:**
- Scroll down a feed
- Horizontal scrolling (carousels)
- Multiple scroll steps in a list

---

### `press_back`

Pop the current route (simulate hardware back button).

**Parameters:** None

**Returns:**
```json
{
  "popped": true,
  "previousRoute": "/home"
}
```

**Returns `false` if:**
- Already at root route
- Back navigation disabled
- App custom navigation logic blocked pop

**Use Cases:**
- Navigate back
- Test back button behavior
- Pop modals/dialogs

---

### `set_slider_value` `key: string, value: number`

Set a Slider to a specific numeric value.

**Parameters:**
```json
{
  "key": "brightnessSlider",
  "value": 0.75
}
```

**Returns:**
```json
{
  "success": true,
  "finalValue": 0.75
}
```

**How it works:**
- Computes tap position based on slider range (min/max)
- Simulates tap at computed position
- Clamps value to min/max range

**Use Cases:**
- Test brightness/volume controls
- Slider range validation
- Settings configuration

---

### `toggle_checkbox` `key: string`

Toggle a Checkbox, Switch, or Radio widget.

**Parameters:**
```json
{
  "key": "rememberMeCheckbox"
}
```

**Returns:**
```json
{
  "success": true,
  "newValue": false
}
```

**Supported Widgets:**
- Checkbox
- Switch
- Radio (toggles selection)

**Use Cases:**
- Test checkbox state changes
- Settings toggles
- Form validation with required checkboxes

---

### `focus_widget` `key: string`

Request focus on a widget (opens keyboard if TextField).

**Parameters:**
```json
{
  "key": "passwordField"
}
```

**Returns:**
```json
{
  "success": true,
  "focused": true
}
```

**Use Cases:**
- Focus text field to show keyboard
- Test focus-related UI changes
- Trigger focus callbacks

---

### `unfocus_all`

Dismiss the keyboard by unfocusing all widgets.

**Parameters:** None

**Returns:**
```json
{
  "success": true
}
```

**Use Cases:**
- Close keyboard after text entry
- Reset focus state
- Clear input UI

---

### `set_text_scale_factor` `scale: number`

Set accessibility text scale (1.0 = normal).

**Parameters:**
```json
{
  "scale": 2.0
}
```

**Returns:**
```json
{
  "success": true,
  "appliedScale": 2.0
}
```

**Scale Values:**
- `0.8` — Small text
- `1.0` — Normal (default)
- `1.5` — Large text
- `2.0` — Very large text (accessibility)

**IMPORTANT:** Requires app to listen to `FlutterPilot.textScaleNotifier`:
```dart
MaterialApp(
  builder: (context, child) {
    return ValueListenableBuilder<double?>(
      valueListenable: FlutterPilot.textScaleNotifier,
      builder: (context, scale, _) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: scale != null
              ? TextScaler.linear(scale)
              : MediaQuery.textScalerOf(context),
          ),
          child: child,
        );
      },
    );
  },
)
```

**Use Cases:**
- Accessibility testing
- WCAG compliance (test at 2.0×)
- Large text UX validation

---

### `pump_frames` `count: number`

Wait for N vsync frames (useful for animations).

**Parameters:**
```json
{
  "count": 60
}
```

**Returns:**
```json
{
  "framesWaited": 60,
  "duration": "1016ms"
}
```

**Use Cases:**
- Wait for animation to complete
- Wait for state updates
- Verify animation behavior

**Frame counts:**
- 1-5 frames = Instant UI updates
- 10-20 frames = Quick animations
- 30-60 frames = Full-second animations

---

## Navigation & Routing

### `navigate_to` `route: string`

Push a named route.

**Parameters:**
```json
{
  "route": "/home/profile"
}
```

**Returns:**
```json
{
  "success": true,
  "previousRoute": "/home",
  "currentRoute": "/home/profile"
}
```

**Requirements:**
- Route must be registered in MaterialApp routes
- Or use named route with `onGenerateRoute`

**Use Cases:**
- Navigation testing
- Multi-screen flow automation
- Deep navigation

---

### `get_navigation_stack`

Get the current route stack.

**Parameters:** None

**Returns:**
```json
{
  "stack": ["/", "/home", "/home/profile"],
  "currentRoute": "/home/profile",
  "count": 3
}
```

**Stack shows:**
- Root route at index 0
- Current route at end
- Full navigation history

**Use Cases:**
- Verify navigation flow
- Check route order
- Test navigation stack cleanup

---

### `simulate_deep_link` `url: string`

Trigger deep link routing (e.g., `myapp://product/123`).

**Parameters:**
```json
{
  "url": "myapp://product/123?promo=summer"
}
```

**Returns:**
```json
{
  "success": true,
  "routeResolved": "/product/123"
}
```

**URL Formats:**
- `myapp://home`
- `https://myapp.com/product/123`
- `myapp://user/alice?tab=settings`

**Use Cases:**
- Test deep link handling
- Push notification routing
- Share link testing

---

### `set_locale` `locale: string`

Switch app language at runtime.

**Parameters:**
```json
{
  "locale": "es"
}
```

**Supported Locales:**
- `'en'` — English
- `'es'` — Spanish
- `'fr'` — French
- `'pt_BR'` — Brazilian Portuguese
- `'de'` — German
- `'zh'` — Chinese
- `'ja'` — Japanese
- `'default'` — System default

**Returns:**
```json
{
  "success": true,
  "appliedLocale": "es"
}
```

**IMPORTANT:** Requires app to listen to `FlutterPilot.localeNotifier`:
```dart
MaterialApp(
  builder: (context, child) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: FlutterPilot.localeNotifier,
      builder: (context, locale, _) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            locale: locale ?? Locale('en'),
          ),
          child: child,
        );
      },
    );
  },
)
```

**Use Cases:**
- Internationalization (i18n) testing
- Multi-language validation
- RTL language testing

---

### `set_theme` `theme: 'light' | 'dark'`

Switch light/dark theme.

**Parameters:**
```json
{
  "theme": "dark"
}
```

**Returns:**
```json
{
  "success": true,
  "appliedTheme": "dark"
}
```

**Use Cases:**
- Test dark mode UI
- Contrast validation
- Theme switching behavior

---

### `set_device_rotation` `rotation: 'portrait' | 'landscape'`

Change device orientation.

**Parameters:**
```json
{
  "rotation": "landscape"
}
```

**Returns:**
```json
{
  "success": true,
  "appliedRotation": "landscape"
}
```

**Use Cases:**
- Responsive layout testing
- Rotation handling validation
- Tablet/landscape UX testing

---

### `wait_for_state` `condition: string, timeout?: number`

Wait until a condition is true (polling).

**Parameters:**
```json
{
  "condition": "route.contains('success')",
  "timeout": 5000
}
```

**Available conditions:**
- `route == '/home'`
- `route.contains('success')`
- `!hasErrors`
- `errorCount == 0`
- `widgetCount > 100`

**Returns:**
```json
{
  "success": true,
  "conditionMet": true,
  "checkCount": 12
}
```

**Use Cases:**
- Wait for async operations
- Test loading states
- Verify app transitions

---

### `hot_reload`

Trigger hot reload on the app.

**Parameters:** None

**Returns:**
```json
{
  "success": true,
  "reloadTime": "523ms"
}
```

**Use Cases:**
- Apply code changes
- Verify hot reload behavior
- Code change testing

---

## State & Inspection

### `get_app_summary`

Snapshot of app state.

**Parameters:** None

**Returns:**
```json
{
  "currentRoute": "/home/dashboard",
  "errorCount": 0,
  "widgetCount": 254,
  "recordingActive": false,
  "fpsEstimate": 59.8,
  "memoryUsage": 45600000,
  "sdkVersion": "0.1.0"
}
```

**Use Cases:**
- Health check
- Quick app state overview
- FPS monitoring

---

### `get_errors`

Return all buffered Flutter errors.

**Parameters:** None

**Returns:**
```json
{
  "errors": [
    {
      "message": "NoSuchMethodError: The method 'add' was called on null.",
      "stackTrace": "packages/myapp/main.dart:42:15\npackages/flutter/...",
      "timestamp": "2024-04-08T20:00:00.123Z",
      "type": "NoSuchMethodError"
    }
  ],
  "count": 1
}
```

**Buffer:** Last 10 errors (FIFO)

**Use Cases:**
- Error monitoring
- Debugging
- Error-triggered testing

---

### `diagnose_last_error`

Full diagnostic report of the most recent error.

**Parameters:** None

**Returns:**
```json
{
  "error": {
    "message": "NoSuchMethodError: ...",
    "type": "NoSuchMethodError",
    "timestamp": "2024-04-08T20:00:00.123Z"
  },
  "stackTrace": "packages/myapp/...",
  "screenshot": "data:image/png;base64,...",
  "widgetTree": { ... },
  "appState": {
    "currentRoute": "/home",
    "navigationStack": [...],
    "errors": [...]
  },
  "appSummary": { ... }
}
```

**Includes:**
- Error details + stack trace
- Screenshot at time of error
- Widget tree at error time
- Full app state snapshot

**Use Cases:**
- Deep debugging
- Error context analysis
- Self-heal AI analysis

---

### `get_flight_log`

Retrieves the rolling 30-60 second continuous Flight Recorder timeline (user gestures, route shifts, state mutations, and network requests) leading up to the current state or crash.

**Parameters:** None

**Returns:**
```json
{
  "totalEvents": 14,
  "hasCrashSnapshot": true,
  "lastException": "NullPointerException: user is null",
  "crashTime": "2026-08-14T04:10:00.000Z",
  "timeline": [
    {
      "category": "route",
      "action": "push",
      "data": { "name": "/checkout" },
      "offsetMs": "+0 ms"
    },
    {
      "category": "gesture",
      "action": "tapWidget",
      "data": { "key": "ElevatedButton['Pay Now']" },
      "offsetMs": "+450 ms"
    }
  ]
}
```

---

### `generate_repro_test`

Synthesizes a standalone, executable Flutter widget test (`test/repro_test.dart`) from the continuous Flight Recorder session leading up to a crash or bug.

**Parameters:**
- `testName` (optional string): Descriptive name for the test.
- `widgetName` (optional string): Root widget or screen name to mount (default: `"MyApp()"`).
- `writeToDisk` (optional boolean): Automatically write test code to disk (default: `false`).
- `filePath` (optional string): Target file path to write (default: `"test/repro_test.dart"`).

**Returns:** Complete, runnable `testWidgets` Dart code string.

---

### `clear_flight_log`

Resets the flight recorder buffer and clears frozen snapshots.

**Parameters:** None

**Returns:** `{"status": "cleared"}`

---

### `export_test_suite`

Exports recorded interactive user journeys and flight sessions into production-ready test suites for Patrol, standard Flutter Integration Tests, or Widget Tests.

**Parameters:**
- `framework` (optional string): `"patrol"`, `"integration_test"`, or `"widget_test"` (default: `"patrol"`).
- `testName` (optional string): Descriptive name for the test.
- `appWidget` (optional string): Target root widget to mount (default: `"MyApp()"`).
- `writeToDisk` (optional boolean): Whether to write the synthesized test file directly to disk.
- `filePath` (optional string): Custom file path (default: `"integration_test/flow_test.dart"` or `"test/flow_test.dart"`).

**Returns:** Complete, runnable test file string.

---

### `save_state_snapshot`

Captures a named point-in-time snapshot of the entire running application state (current route, Riverpod/Bloc providers, and storage).

**Parameters:**
- `name` (required string): Descriptive identifier for the snapshot (e.g. `"checkout_with_items"`).

**Returns:** `{"status": "saved", "snapshot": {...}}`

---

### `restore_state_snapshot`

Instantly rewinds the running application back to a previously captured state snapshot (<100ms) without restarting.

**Parameters:**
- `name` (required string): Name of the snapshot to restore.

**Returns:** `{"status": "restored", "name": "checkout_with_items"}`

---

### `list_state_snapshots`

Lists all point-in-time state snapshots stored in memory.

**Parameters:** None

**Returns:** List of saved snapshot metadata.

---

### `delete_state_snapshot`

Deletes a saved state snapshot by name.

**Parameters:**
- `name` (required string): Name of the snapshot to delete.

**Returns:** `{"status": "deleted"}`

---

### `get_perf_metrics`

Real-time performance metrics.

**Parameters:** None

**Returns:**
```json
{
  "fpsEstimate": 59.8,
  "frameTimes": [16.2, 16.1, 16.0, 16.1, 16.2],
  "memory": {
    "heapUsage": 45600000,
    "externalMemory": 12340000,
    "totalMemory": 57940000
  },
  "refreshRate": 60.0,
  "averageFrameTime": "16.1ms"
}
```

**Use Cases:**
- Performance monitoring
- Jank detection
- Memory usage tracking
- Optimize rendering

---

### `get_semantics_tree`

Full accessibility tree (VoiceOver/TalkBack compatible).

**Parameters:** None

**Returns:**
```json
{
  "root": {
    "label": "Home Screen",
    "role": "button",
    "enabled": true,
    "bounds": { "x": 0, "y": 0, "width": 414, "height": 896 },
    "actions": ["activate"],
    "children": [
      {
        "label": "Login Button",
        "role": "button",
        "enabled": true,
        "bounds": { "x": 100, "y": 400, "width": 214, "height": 50 },
        "actions": ["activate"]
      }
    ]
  }
}
```

**Includes:**
- Semantic labels
- Roles (button, text, slider, etc.)
- Enabled state
- Bounds in screen space
- Available actions
- Full nesting

**Use Cases:**
- Accessibility testing (a11y)
- VoiceOver/TalkBack validation
- Screen reader testing
- WCAG compliance

---

### `assert_widget_enabled` `key: string`

Assert that a widget is interactive (enabled, tappable).

**Parameters:**
```json
{
  "key": "submitButton"
}
```

**Returns:**
```json
{
  "enabled": true
}
```

**Fails if:**
- Widget is disabled
- Widget is not found
- Widget doesn't support interaction

**Use Cases:**
- Form validation (submit button enabled after fill)
- State-dependent UI (disable during loading)
- Test preconditions

---

### `assert_widget_disabled` `key: string`

Assert that a widget is disabled.

**Parameters:**
```json
{
  "key": "deleteButton"
}
```

**Returns:**
```json
{
  "disabled": true
}
```

**Use Cases:**
- Verify loading states (disable during fetch)
- Test permission denial (button disabled for non-admin)
- Precondition validation

---

### `get_riverpod_states` *(requires flutterpilot_riverpod)*

Current state of all active Riverpod providers.

**Parameters:** None

**Returns:**
```json
{
  "providers": {
    "userProvider": {
      "id": 1,
      "name": "Alice",
      "email": "alice@example.com"
    },
    "counterProvider": 42,
    "isLoadingProvider": false
  },
  "count": 3
}
```

**Use Cases:**
- Inspect provider state
- Verify state after action
- State mutation validation

---

### `get_bloc_states` *(requires flutterpilot_bloc)*

Current state of all active Bloc/Cubit instances.

**Parameters:** None

**Returns:**
```json
{
  "blocs": {
    "counterCubit": 42,
    "authBloc": "authenticated",
    "themeBloc": "dark"
  },
  "count": 3
}
```

**Use Cases:**
- Inspect bloc state
- Verify state after action
- State mutation validation

---

### `get_network_logs` *(requires flutterpilot_dio)*

All HTTP requests/responses captured by Dio.

**Parameters:** None

**Returns:**
```json
{
  "requests": [
    {
      "method": "GET",
      "url": "https://api.example.com/users",
      "statusCode": 200,
      "responseTime": 125,
      "requestTime": "2024-04-08T20:00:00.123Z",
      "headers": {
        "Authorization": "Bearer token",
        "Content-Type": "application/json"
      },
      "response": [
        { "id": 1, "name": "Alice" },
        { "id": 2, "name": "Bob" }
      ]
    },
    {
      "method": "POST",
      "url": "https://api.example.com/login",
      "statusCode": 401,
      "responseTime": 89,
      "error": "Unauthorized"
    }
  ],
  "count": 2
}
```

**Captured:**
- Method, URL, status code
- Request/response times
- Headers
- Response body
- Errors

**Use Cases:**
- Network debugging
- API response validation
- Mocking server responses
- Load testing

---

### `query_drift_db` `sql: string` *(requires flutterpilot_drift)*

> **Note:** The tool name registered by the server is `query_drift`. Both names are documented here for reference.

Execute SQL query on Drift database.

**Parameters:**
```json
{
  "dbName": "main",
  "sql": "SELECT * FROM users WHERE id = 1"
}
```

**Returns:**
```json
{
  "rows": [
    {
      "id": 1,
      "name": "Alice",
      "email": "alice@example.com",
      "createdAt": "2024-01-15T10:30:00Z"
    }
  ]
}
```

**Query Types:**
- `SELECT` — Always allowed (read-only)
- `INSERT`, `UPDATE`, `DELETE` — Requires `--allow-destructive` flag

**Use Cases:**
- Database inspection
- Data validation
- Test data setup/teardown
- Schema debugging

---

### `query_sqflite` `sql: string` *(requires flutterpilot_sqflite)*

Execute a read-only SQL query on a sqflite database.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `dbName` | string | **Yes** | Database name registered with `SqflitePilotInspector.registerDatabase()`. |
| `sql` | string | **Yes** | SELECT/EXPLAIN/PRAGMA/WITH query. Write operations are blocked. |

**Returns:** Rows from the query result.

---

### `list_sqflite_tables` *(requires flutterpilot_sqflite)*

List all tables in a registered sqflite database.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `dbName` | string | **Yes** | Database name. |

**Returns:** Table names in the database.

---

### `list_sqflite_databases` *(requires flutterpilot_sqflite)*

List all sqflite databases registered with FlutterPilot.

**Parameters:** None

**Returns:** Names of all registered databases.

---

### `get_hive_contents` *(requires flutterpilot_hive)*

All key-value pairs from registered Hive boxes.

**Parameters:** None

**Returns:**
```json
{
  "boxes": {
    "userBox": {
      "currentUserId": "user123",
      "userName": "Alice",
      "preferences": {
        "theme": "dark",
        "language": "en"
      }
    },
    "cacheBox": {
      "api_response_v1": "{...}"
    }
  }
}
```

**Use Cases:**
- Local storage inspection
- Cache validation
- Persistent state debugging

---

### `get_shared_preferences` *(requires flutterpilot_shared_preferences)*

Current SharedPreferences key-value map. Values for keys matching sensitive patterns (`token`, `password`, `secret`, `auth`, `session`, etc.) are **redacted by default**.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `showSensitive` | string | No | `"true"` to reveal sensitive-looking values. Default: redacted. |

**Returns:**
```json
{
  "prefs": {
    "username": "alice",
    "theme": "dark",
    "notification_enabled": true,
    "auth_token": "[redacted — pass showSensitive=true to reveal]"
  }
}
```

**Use Cases:**
- User preferences inspection
- Settings validation
- Persistent data debugging

---

### `set_shared_preference` `key: string, value: any, type?: string` *(requires flutterpilot_shared_preferences)*

Write a value to SharedPreferences.

**Parameters:**
```json
{
  "key": "theme",
  "value": "dark",
  "type": "string"
}
```

**Supported Types:**
- `string` (default)
- `int`
- `double`
- `bool`
- `stringList` (JSON array of strings)

**Returns:**
```json
{
  "success": true,
  "key": "theme",
  "value": "dark",
  "type": "string"
}
```

**Use Cases:**
- Test preferences UI
- Settings state injection
- Persistent data setup

---

### `clear_shared_preferences` *(requires flutterpilot_shared_preferences)*

> ⚠️ **DESTRUCTIVE** — Cannot be undone. Clearing all keys requires `confirm="CLEAR_ALL"`.

Remove one or all SharedPreferences entries.

**Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | No | Key to remove. Omit to clear ALL preferences (requires `confirm`). |
| `confirm` | string | Conditional | Must be `"CLEAR_ALL"` when `key` is omitted. |

**Examples:**
```
# Remove one key
clear_shared_preferences(key: "theme")

# Clear everything — requires confirmation
clear_shared_preferences(confirm: "CLEAR_ALL")
```

**Use Cases:**
- Reset app state for tests
- Clean up between test runs
- Debug preferences issues

---

### `get_build_config`

Return pubspec.yaml and build metadata.

**Parameters:** None

**Returns:**
```json
{
  "pubspec": {
    "name": "my_app",
    "version": "1.0.0",
    "description": "My Flutter App",
    "environment": {
      "sdk": ">=3.11.0"
    },
    "dependencies": {
      "flutter": { "sdk": "flutter" },
      "riverpod": "^2.0.0"
    }
  },
  "buildInfo": {
    "buildNumber": "1",
    "buildName": "1.0.0"
  }
}
```

**Use Cases:**
- Verify app version
- Check dependency versions
- Build metadata inspection

---

### `read_dart_file` `path: string` *(requires `--project-root`)*

Read a Dart source file from your project.

**Parameters:**
```json
{
  "path": "lib/main.dart"
}
```

**Returns:**
```json
{
  "path": "lib/main.dart",
  "content": "import 'package:flutter/material.dart';\n\nvoid main() {\n  ...",
  "lines": 42
}
```

**Path Format:**
- Relative to project root
- Example: `"lib/screens/home.dart"`
- Example: `"test/mocks/mock_api.dart"`

**Use Cases:**
- AI code analysis
- Source code inspection
- Test implementation reference

---

### `list_dart_files` `pattern?: string` *(requires `--project-root`)*

List Dart files in your project.

**Parameters:**
```json
{
  "pattern": "lib/screens/**/*.dart"
}
```

**Returns:**
```json
{
  "files": [
    "lib/screens/home.dart",
    "lib/screens/profile.dart",
    "lib/screens/settings.dart"
  ],
  "count": 3
}
```

**Pattern Syntax:**
- `*` — any characters
- `**` — recursive directories
- `?` — single character
- `{a,b}` — alternatives

**Use Cases:**
- Project structure discovery
- File listing for AI
- Pattern-based filtering

---

## Recording & Testing

### `start_recording`

Begin recording user interactions.

**Parameters:** None

**Returns:**
```json
{
  "recording": true,
  "startTime": "2024-04-08T20:00:00.123Z"
}
```

**Records:**
- Taps (location, widget)
- Text entry
- Scrolls
- Navigation
- Assertions

**Use Cases:**
- Manual test flow recording
- AI test generation setup

---

### `stop_and_generate_test`

Stop recording and generate a testWidgets block.

**Parameters:** None

**Returns:**
```json
{
  "testCode": "testWidgets('user flow', (WidgetTester tester) async {\n  await tester.pumpWidget(const MyApp());\n  expect(find.text('Home'), findsOneWidget);\n  \n  await tester.tap(find.byKey(const Key('loginBtn')));\n  await tester.pumpAndSettle();\n  \n  await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');\n  await tester.tap(find.byKey(const Key('submitBtn')));\n  await tester.pumpAndSettle();\n  \n  expect(find.text('Welcome'), findsOneWidget);\n});",
  "actionsRecorded": 4,
  "duration": "45 seconds"
}
```

**Generated test:**
- Uses Flutter `testWidgets` pattern
- Includes `find.byKey` for widget location
- Includes `pumpAndSettle` for async operations
- Includes expectations for assertions

**Use Cases:**
- Autonomous test generation
- Manual flow → test code
- Integration test creation

---

### `get_latest_crash_report`

Get the most recent crash diagnostic.

**Parameters:** None

**Returns:**
```json
{
  "crash": {
    "timestamp": "2024-04-08T20:00:00.123Z",
    "error": {
      "type": "NoSuchMethodError",
      "message": "The method 'add' was called on null."
    },
    "stackTrace": "packages/myapp/main.dart:42:15\n...",
    "screenshot": "data:image/png;base64,iVBORw0KGgoAAAANS...",
    "widgetTree": { ... },
    "appState": { ... }
  }
}
```

**Captured at crash time:**
- Full error + stack trace
- Screenshot
- Widget tree
- App state

**Use Cases:**
- Self-heal crash analysis
- Bug reproduction
- Error context debugging

---

### `show_performance_overlay` `show: boolean`

Toggle the Flutter performance overlay.

**Parameters:**
```json
{
  "show": true
}
```

**Returns:**
```json
{
  "success": true,
  "visible": true
}
```

**Shows:**
- FPS graph
- GPU/UI thread times
- Frame raster times
- Janky frame indicators

**Use Cases:**
- Performance debugging
- Jank detection
- Rendering analysis

---

### `list_custom_tools`

List all app-registered custom tools.

**Parameters:** None

**Returns:**
```json
{
  "tools": [
    {
      "name": "clearCache",
      "description": "Clear app image cache"
    },
    {
      "name": "resetDatabase",
      "description": "Reset local database"
    },
    {
      "name": "simulateBadNetwork",
      "description": "Simulate slow/offline network"
    }
  ],
  "count": 3
}
```

**Use Cases:**
- Discover available tools
- Test custom tool registration

---

### `call_custom_tool` `name: string, ...args`

Invoke an app-registered custom tool.

**Parameters:**
```json
{
  "name": "clearCache"
}
```

**Returns:**
```json
{
  "cleared": true,
  "freedMemory": 45000000
}
```

**With arguments:**
```json
{
  "name": "simulateBadNetwork",
  "latency": 5000,
  "packetLoss": 0.25
}
```

**Use Cases:**
- Call app-specific logic
- Custom testing scenarios
- State manipulation

---

## Performance & DevTools

### Additional Performance Tools

**Note:** These tools are implemented in the server and app integration patterns.

#### `wait_for_state`
Wait for async operations, state changes, navigation. See [Navigation](#wait_for_state) section.

#### `hot_reload`
Apply code changes. See [Navigation](#hot_reload) section.

#### `pump_frames`
Wait for animation frames. See [UI Automation](#pump_frames) section.

---

## Common Patterns

### Form Filling
```json
[
  { "enter_text": { "key": "emailField", "text": "user@example.com" } },
  { "enter_text": { "key": "passwordField", "text": "password123" } },
  { "tap_widget": { "key": "rememberCheckbox" } },
  { "tap_widget": { "key": "submitButton" } },
  { "wait_for_state": { "condition": "route.contains('success')" } }
]
```

### Navigation Testing
```json
[
  { "navigate_to": { "route": "/settings" } },
  { "assert_widget_enabled": { "key": "themeToggle" } },
  { "tap_widget": { "key": "themeToggle" } },
  { "press_back": {} },
  { "get_navigation_stack": {} }
]
```

### Visual Regression
```json
[
  { "set_device_rotation": { "rotation": "landscape" } },
  { "capture_screenshot": {} },
  { "compare_screenshot": { "filename": "landscape_layout.png" } }
]
```

### Accessibility Testing
```json
[
  { "set_text_scale_factor": { "scale": 2.0 } },
  { "capture_screenshot": {} },
  { "get_semantics_tree": {} },
  { "set_locale": { "locale": "ar" } },
  { "capture_screenshot": {} }
]
```

---

## Tool Availability

| Tool | Core SDK | Server | Riverpod Plugin | Bloc Plugin | Dio Plugin | Drift Plugin | Hive Plugin | SharedPref Plugin |
|------|----------|--------|-----------------|-------------|-----------|-------------|-----------|-------------------|
| capture_screenshot | ✅ | ✅ | — | — | — | — | — | — |
| get_widget_tree | ✅ | ✅ | — | — | — | — | — | — |
| get_widget_properties | ✅ | ✅ | — | — | — | — | — | — |
| tap_at / tap_widget | ✅ | ✅ | — | — | — | — | — | — |
| enter_text | ✅ | ✅ | — | — | — | — | — | — |
| navigate_to | ✅ | ✅ | — | — | — | — | — | — |
| get_riverpod_states | — | ✅ | ✅ | — | — | — | — | — |
| get_bloc_states | — | ✅ | — | ✅ | — | — | — | — |
| get_network_logs | — | ✅ | — | — | ✅ | — | — | — |
| query_drift_db | — | ✅ | — | — | — | ✅ | — | — |
| get_hive_contents | — | ✅ | — | — | — | — | ✅ | — |
| get_shared_preferences | — | ✅ | — | — | — | — | — | ✅ |

---

**Last Updated:** April 2026  
**Total Tools:** 82  
**Documentation Status:** Complete ✅

---

## Debug Console

*Automatically captures `print()`, `debugPrint()`, and `dart:developer log()` from the running app — no manual copy-paste from VS Code needed.*

### `get_debug_logs`

Returns captured console output from the running app.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `level` | string | No | Filter: `"debug"`, `"info"`, `"warning"`, `"error"`. Omit for all. |
| `logger` | string | No | Filter by logger name (partial match, e.g. `"stdout"`, `"debugPrint"`). |
| `limit` | integer | No | Max entries to return (default: 100). |

**Returns:**
```
10 log entries (buffer total: 42):
[2026-04-08T20:52:16.965Z] [info] (debugPrint) FlutterPilot initialized 🚀
[2026-04-08T20:52:17.123Z] [info] (stdout) User tapped login button
[2026-04-08T20:52:17.890Z] [error] (debugPrint) API call failed: 401 Unauthorized
```

**Use Cases:**
- See what the app is printing without opening VS Code debug console
- Debug API responses by checking logged output
- Catch errors the app printed during a test sequence

---

### `clear_debug_logs`

Clears the server-side log capture buffer.

**Parameters:** None

**Use Cases:** Clean baseline before a specific test scenario.

---

### `set_log_filter`

Clears both the server-side and in-app SDK log buffers at once.

**Parameters:** None

**Use Cases:** Full reset before starting a new debug session.

---

## DevTools Deep Inspection

*These tools use the same VM Service Protocol as Flutter DevTools. No browser needed — AI agents can read memory, network, render trees directly.*

### `get_memory_details`

Detailed memory breakdown per isolate: heap used, heap capacity, external (native) memory.

**Parameters:** None

**Returns:**
```
Memory details:
  main (id=isolates/123): heap=45.23/128.00 MB  external=2.10 MB

Totals: heap=45.23/128.00 MB  external=2.10 MB
```

**Use Cases:**
- Detect memory leaks (heap growing over time)
- Check if external memory (images, platform channels) is unexpectedly large
- Compare memory before/after a navigation or operation

---

### `get_allocation_profile`

Top Dart classes by current heap allocation (like DevTools Memory tab class list).

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `limit` | integer | No | Number of top classes to show (default: 30). |

**Returns:**
```
Top 30 classes by heap usage (from 412 total):
Class                                           Bytes     Instances
----------------------------------------------------------------------
_CompactLinkedHashMap                         384.0KB           42
Image                                         128.5KB            8
Uint8List                                      96.2KB          156
```

**Use Cases:**
- Find memory leaks — which class is accumulating instances?
- Detect large image buffers
- Identify unexpected object retention

---

### `get_http_profile`

All HTTP requests made by the app (DevTools Network tab equivalent).

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `limit` | integer | No | Max requests to return, most recent first (default: 50). |
| `status_filter` | integer | No | Filter by HTTP status code (e.g. `404`, `500`). |

**Returns:**
```
12 HTTP requests (showing last 12):
[200] GET https://api.example.com/users  ⏱234ms  ↑0B ↓1842B
[201] POST https://api.example.com/auth  ⏱89ms  ↑256B ↓512B
[404] GET https://api.example.com/missing  ⏱45ms  ↑0B ↓128B
```

**Use Cases:**
- Confirm the app actually sent an API request
- Debug auth failures (check request headers, response body size)
- Find slow requests (>2s) without opening a browser

---

### `clear_http_profile`

Resets the HTTP request history.

**Parameters:** None

**Use Cases:** Clean baseline before testing a specific user flow's network calls.

---

### `get_render_tree`

Dumps the render object tree — how Flutter sizes and positions widgets (DevTools Layout Explorer equivalent).

**Parameters:** None

**Returns:** Full render tree as text (truncated at 8000 chars if very large).

**Use Cases:**
- Debug layout issues and overflow errors
- Understand exact sizing constraints
- Find unexpected padding or clipping

---

### `get_layer_tree`

Dumps the compositing layer tree — the GPU-level scene representation.

**Parameters:** None

**Use Cases:**
- Debug why widgets are causing unnecessary GPU layers
- Check compositing efficiency
- Investigate transparency/opacity rendering

---

### `get_vm_info`

Dart VM version, process ID, and all running isolates.

**Parameters:** None

**Returns:**
```
VM version: 3.4.0 (stable) ...
PID: 12345
Isolates (1):
  main (id=isolates/7684015)
```

---

### `toggle_repaint_rainbow`

Enables/disables the repaint rainbow overlay — each layer that repaints cycles through colors.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `enabled` | boolean | Yes | `true` to enable, `false` to disable. |

**Use Cases:**
- Identify widgets repainting every frame (performance issue)
- Confirm that `const` widgets are NOT repainting
- Find unnecessary `setState()` calls

---

### `toggle_debug_paint`

Shows layout padding (blue), widget boundaries (orange), baselines (green), pointer hit areas.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `enabled` | boolean | Yes | `true` to show debug paint, `false` to hide. |

**Use Cases:**
- Debug unexpected padding or margin
- Check widget alignment and boundary issues
- Verify touch target sizes meet accessibility guidelines

---

### `toggle_slow_animations`

Slows all animations to 1/5 speed for detailed inspection.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `enabled` | boolean | Yes | `true` for 5x slow-motion, `false` to restore normal speed. |

**Use Cases:**
- Inspect animation curves and easing
- Catch jank frames in complex transitions
- Verify animation correctness before recording

---

### `enable_widget_rebuild_tracking`

Enables per-widget rebuild counting (DevTools "Track Widget Builds").

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `enabled` | boolean | Yes | `true` to start tracking, `false` to stop. |

**Use Cases:**
- Find widgets rebuilding more than expected
- Verify that `const` or memoized widgets are not rebuilding
- Identify `setState()` calls that trigger excessive subtree rebuilds

---

### `get_gc_stats`

Garbage collection heap pressure statistics across isolates.

**Parameters:** None

**Use Cases:**
- Detect heap pressure causing GC-induced jank
- Compare heap before/after an operation
- Identify memory not being released

---

## Plugin Integrations

These tools become available when the corresponding FlutterPilot plugin is registered in the app.

### Supabase (5 tools)

Requires: `flutterpilot_supabase` plugin with `SupabasePilotInspector.register(client)`.

---

#### `get_supabase_auth`

Inspect current Supabase auth state: user profile, session, JWT expiry, and recent auth events.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `showSensitive` | string | No | `"true"` to reveal email/phone/user_id. Default: redacted. |

**Returns:** Authentication status, user profile, session details, auth event history.

---

#### `get_supabase_realtime`

List all active Supabase Realtime channel subscriptions.

**Parameters:** None

**Returns:** List of channels with topic, join status, and closed status.

---

#### `query_supabase_table`

Query rows from a Supabase table using the app's own credentials. Useful for inspecting live data during debug.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `table` | string | **Yes** | Supabase table name. |
| `limit` | string | No | Max rows to return (1–200, default 20). |
| `filter` | string | No | Equality filter in `"column=value"` format, e.g. `"user_id=abc123"`. |

**Returns:** Row data from the specified table.

---

#### `supabase_sign_out`

> ⚠️ **MAKES REAL NETWORK CALL** — Signs out via the Supabase Auth API. Affects the real session. Use only in dev/test environments.

Sign out the current Supabase user.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `scope` | string | No | `"local"`, `"global"` (all devices), or `"others"` (other sessions). Default: `"local"`. |

---

#### `supabase_refresh_session`

> ⚠️ **MAKES REAL NETWORK CALL** — Calls `client.auth.refreshSession()`. Use only in dev/test environments.

Force-refresh the current Supabase session token. Use when testing token expiry flows.

**Parameters:** None

---

### GoRouter (4 tools)

Requires: `flutterpilot_gorouter` plugin with `GoRouterPilotInspector.register(router)`.

---

#### `get_gorouter_state`

Inspect the current GoRouter navigation state.

**Parameters:** None

**Returns:** Current location, path parameters, query parameters, matched routes, can-pop status.

---

#### `get_gorouter_config`

List all registered GoRouter routes and their configuration.

**Parameters:** None

**Returns:** Route tree with paths, names, types, and children.

---

#### `get_gorouter_history`

View timestamped navigation history.

**Parameters:** None

**Returns:** List of recent route changes with timestamps.

---

#### `gorouter_navigate`

Navigate programmatically using GoRouter.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `location` | string | Yes (except pop) | Route path (e.g. `"/home"`, `"/user/123"`). |
| `action` | string | No | `"go"` (replace stack), `"push"`, `"replace"`, `"pop"`. Default: `"go"`. |

---

### Connectivity (3 tools)

Requires: `flutterpilot_connectivity` plugin with `ConnectivityPilotInspector.register()`.

---

#### `get_connectivity`

Check current network connectivity status.

**Parameters:** None

**Returns:** Online status, connectivity types (wifi/mobile/ethernet/vpn), simulated-offline flag.

---

#### `get_connectivity_history`

View timestamped log of connectivity state transitions.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `limit` | string | No | Max entries to return (default: 100). |

---

#### `simulate_offline`

Toggle simulated offline mode for testing.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `enabled` | string | Yes | `"true"` to simulate offline, `"false"` to restore. |

**Note:** App code can check `ConnectivityPilotInspector.isSimulatedOffline` to honor this flag.

---

### Firebase (7 tools)

Requires: `flutterpilot_firebase` plugin. Register only the Firebase services you use:

```dart
FirebasePilotInspector.register(
  crashlytics: FirebaseCrashlytics.instance,
  analytics: FirebaseAnalytics.instance,
  performance: FirebasePerformance.instance,
  messaging: FirebaseMessaging.instance,
);
```

---

#### `get_firebase_status`

Check which Firebase services are registered and their status.

**Parameters:** None

**Returns:** Availability and config for Crashlytics, Analytics, Performance, and Messaging.

---

#### `get_fcm_token`

Get the Firebase Cloud Messaging token (truncated for security).

**Parameters:** None

---

#### `log_analytics_event`

> ⚠️ **MAKES REAL NETWORK CALL** — Sends event to your Firebase Analytics dashboard. Do not use in CI or production test runs.

Log a custom Firebase Analytics event.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Event name (e.g. `"button_pressed"`). |
| `params` | string | No | JSON object of parameters (e.g. `'{"button_id":"submit"}'`). |

---

#### `get_analytics_log`

View recent analytics events logged through FlutterPilot.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `limit` | string | No | Max events to return (default: 200). |

---

#### `start_performance_trace`

> ⚠️ **MAKES REAL NETWORK CALL** — Starts a Firebase Performance trace (data sent to Firebase on stop).

Start a named Firebase Performance trace.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Trace name (e.g. `"checkout_flow"`). |

---

#### `stop_performance_trace`

Stop a previously started Firebase Performance trace.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Trace name to stop. |

---

#### `record_crashlytics_error`

> ⚠️ **MAKES REAL NETWORK CALL** — Sends error to your Firebase Crashlytics dashboard. Avoid in CI to prevent dashboard pollution.

Record a test error in Firebase Crashlytics.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | No | Error message (default: "FlutterPilot test error"). |
| `fatal` | string | No | `"true"` for fatal, `"false"` for non-fatal (default). |

---

### Secure Storage (4 tools)

Requires: `flutterpilot_secure_storage` plugin with `SecureStoragePilotInspector.register(storage)`.

---

#### `get_secure_storage_keys`

List all keys in FlutterSecureStorage. Values redacted by default.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `showValues` | string | No | `"true"` to reveal values (sensitive keys always redacted). |

**Security:** Keys matching `password`, `secret`, `private_key`, `api_key` patterns are always redacted, even with `showValues=true`.

---

#### `read_secure_storage_key`

Read a specific key from FlutterSecureStorage.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | Yes | The key to read. |

---

#### `set_secure_storage_key`

Write a key-value pair to FlutterSecureStorage.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | Yes | The key to set. |
| `value` | string | Yes | The value to store. |

---

#### `delete_secure_storage_key`

> ⚠️ **DESTRUCTIVE** — Deletion cannot be undone. Wiping all keys requires `confirm="DELETE_ALL"`.

Delete a key or clear all secure storage.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | No | Key to delete. Omit to clear ALL secure storage (requires `confirm`). |
| `confirm` | string | Conditional | Must be `"DELETE_ALL"` when `key` is omitted. |
