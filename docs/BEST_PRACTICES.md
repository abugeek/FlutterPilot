# FlutterPilot Best Practices Guide

Production-ready patterns and recommendations for using FlutterPilot.

## Table of Contents
- [Setup & Initialization](#setup--initialization)
- [Widget Keys & Targeting](#widget-keys--targeting)
- [State Management](#state-management)
- [Network Mocking](#network-mocking)
- [Performance Optimization](#performance-optimization)
- [Error Handling](#error-handling)
- [Security & Privacy](#security--privacy)
- [Testing Patterns](#testing-patterns)

---

## Setup & Initialization

### ✅ Do: Initialize FlutterPilot First

```dart
void main() {
  // MUST be first
  FlutterPilot.initialize();
  
  // Then add observers
  Bloc.observer = BlocPilotObserver();
  
  // Then run app
  runApp(MyApp());
}
```

### ❌ Don't: Initialize After Observers

```dart
void main() {
  Bloc.observer = BlocPilotObserver();  // ← Too early!
  FlutterPilot.initialize();  // ← Will fail
  runApp(MyApp());
}
```

### ✅ Do: Use Conditional Initialization

```dart
void main() {
  // Only initialize during development
  if (kDebugMode) {
    FlutterPilot.initialize();
    Bloc.observer = BlocPilotObserver();
  }
  runApp(MyApp());
}
```

### ✅ Do: Initialize All Required Plugins

```dart
void main() {
  FlutterPilot.initialize();
  
  // Initialize every plugin you want to monitor
  Bloc.observer = BlocPilotObserver();  // For Bloc
  
  // Riverpod: must wrap app
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: MyApp(),
    ),
  );
}
```

---

## Widget Keys & Targeting

### ✅ Do: Use ValueKey for Simple Widgets

```dart
FloatingActionButton(
  key: const ValueKey('incrementBtn'),  // ← Easy to target
  onPressed: () => context.read<CounterBloc>().add(IncrementEvent()),
  child: const Icon(Icons.add),
)
```

### ✅ Do: Use Descriptive Key Names

```dart
// ✅ Good names
const ValueKey('submitBtn')
const ValueKey('emailField')
const ValueKey('settingsMenu')
const ValueKey('profilePicture')

// ❌ Bad names
const ValueKey('btn1')
const ValueKey('field')
const ValueKey('item')
```

### ✅ Do: Key Dynamic Lists

```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ListTile(
      key: ValueKey(items[index].id),  // ← Use unique ID
      title: Text(items[index].name),
    );
  },
)
```

### ❌ Don't: Use Index as Key

```dart
// ❌ BAD: Reordering breaks targeting
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ListTile(
      key: ValueKey(index),  // ← Don't do this
      title: Text(items[index].name),
    );
  },
)
```

### ✅ Do: Organize Keys by Widget Type

```dart
// Create a constants file for keys
class AppKeys {
  // Navigation
  static const String homeTab = 'homeTab';
  static const String settingsTab = 'settingsTab';
  
  // Forms
  static const String emailField = 'emailField';
  static const String passwordField = 'passwordField';
  static const String submitBtn = 'submitBtn';
  
  // Lists
  static const String itemList = 'itemList';
}

// Use in widgets
FloatingActionButton(
  key: const ValueKey(AppKeys.submitBtn),
  onPressed: () {},
)
```

---

## State Management

### ✅ Do: Track State Manager Usage

Keep track of which state managers your app uses:

```dart
void main() {
  FlutterPilot.initialize();
  
  // Document what's loaded:
  // ✓ Bloc/Cubit: for form validation
  // ✓ Riverpod: for data fetching
  // ✗ GetX: not used
  
  Bloc.observer = BlocPilotObserver();
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: MyApp(),
    ),
  );
}
```

### ✅ Do: Use `get_capabilities` Before Testing

When writing test scripts or AI prompts, first check what's loaded:

```
Claude: "Let me check what state managers are available."
[Claude calls get_capabilities]
Claude: "I see Bloc, Riverpod, and Dio are loaded."
```

### ❌ Don't: Assume Bloc Tracks All State

Bloc plugin only tracks Bloc/Cubit instances that fire events. If a Bloc:
- Is created but never used → not in state
- Never fires events → state not updated
- Is disposed → removed from tracking

This is **expected behavior**, not a bug.

### ✅ Do: Handle Multi-Container Scenarios

If using multiple state containers (common with RiveFlow):

```dart
// ❌ Multiple ProviderScopes cause issues
Scaffold(
  body: ProviderScope(child: PageOne()),
  drawer: ProviderScope(child: PageTwo()),  // ← Collision
)

// ✅ Single root ProviderScope
void main() {
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: MyApp(),  // All pages inside
    ),
  );
}
```

### ✅ Do: Reset State Between Test Cases

If writing manual test cases:

```
Test 1: Login with valid credentials
- [navigate to login]
- [enter credentials]
- [verify success]

[RESET: Hot reload with 'R' to clear state]

Test 2: Login with invalid credentials
- [navigate to login]
- [enter bad credentials]
- [verify error]
```

---

## Network Mocking

### ✅ Do: Mock Only When Testing

```dart
// Mock should be added by test, not in app code
void main() {
  FlutterPilot.initialize();
  
  // ❌ DON'T add mocks here
  // add_http_mock('/api/users', {...})
  
  runApp(MyApp());
}

// Instead: Add mocks via AI agent or test script
```

### ✅ Do: Test Both Success and Failure

```
Mock /auth/login with:
- 200 + valid token (success path)
- 401 unauthorized (auth failure)
- 500 server error (server error)
- Timeout (network error)
```

### ✅ Do: Use Realistic Mock Data

```dart
// ✅ Good: Realistic data structure
{
  "users": [
    {
      "id": "123",
      "name": "John Doe",
      "email": "john@example.com",
      "createdAt": "2024-01-01T00:00:00Z"
    }
  ],
  "total": 1
}

// ❌ Bad: Oversimplified
{
  "success": true,
  "data": "some users"
}
```

### ✅ Do: Clear Mocks Between Tests

```
Test 1: Success path
- Mock endpoint
- Test
- [Clear mock]

Test 2: Failure path
- Mock endpoint (different response)
- Test
```

### ❌ Don't: Leave Mocks Active Between Tests

Mocks persist across hot reloads. Clear them explicitly:

```bash
# Clear all HTTP mocks
clear_http_mocks

# Or restart the app
flutter run  # Kill and restart
```

---

## Performance Optimization

### ✅ Do: Limit Widget Tree Depth

For large widget trees, use `maxDepth` parameter:

```bash
# Instead of: get_widget_tree (might timeout on huge tree)
# Use: get_widget_tree maxDepth=20 (only first 20 levels)
```

### ✅ Do: Split Large Apps with Keys

If analyzing a complex app, narrow down with keys:

```bash
# Get entire tree
get_widget_tree

# Focus on specific widget
get_widget_properties key=settingsPanel

# This is faster than analyzing everything
```

### ✅ Do: Profile Before and After

```bash
# Take baseline screenshot
capture_screenshot  # Save this

# Make change
[edit code]
flutter run

# Compare
capture_screenshot  # Compare with baseline
```

### ❌ Don't: Call Tools Excessively in Loop

```dart
// ❌ DON'T do this in tests
for (int i = 0; i < 100; i++) {
  await server.call('get_widget_tree');  // 100 calls!
}

// ✅ Better: Call once, analyze
final tree = await server.call('get_widget_tree');
for (final widget in tree.traverse()) {
  // Analyze locally
}
```

### ✅ Do: Use Appropriate Buffer Sizes

FlutterPilot buffers are auto-capped:
- Max event buffer: 100 entries
- Max debug log buffer: 100 lines
- Max screenshot baselines: 50

These are optimized for development. No action needed.

---

## Error Handling

### ✅ Do: Check for Extension Errors

When tools fail, they return structured error:

```json
{
  "error": "[connectionLost] Extension not responding",
  "category": "connectionLost",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### ✅ Do: Implement Retry Logic

For unreliable operations (network mocking setup):

```
Try #1: add_http_mock → fails (timeout)
Wait 2 seconds
Try #2: add_http_mock → succeeds
```

### ✅ Do: Handle Validation Errors

When targeting widgets:

```json
{
  "error": "[validation] Widget key 'invalidBtn' not found",
  "category": "validation"
}
```

**Response**: Double-check key name, verify widget is mounted.

### ✅ Do: Log Extension Errors

If using FlutterPilot programmatically:

```dart
try {
  final result = await server.callTool('get_widget_tree', {});
} on FlutterPilotException catch (e) {
  if (e.category == ErrorCategory.connectionLost) {
    // Retry logic
  } else if (e.category == ErrorCategory.timeout) {
    // Increase timeout
  } else if (e.category == ErrorCategory.validation) {
    // Fix parameters
  }
}
```

---

## Security & Privacy

### ❌ Don't: Use FlutterPilot in Production

FlutterPilot is **dev-only**. It:
- Exposes all state and UI
- Allows arbitrary code execution
- Has no authentication
- Should never be in release builds

### ✅ Do: Use dev_dependencies Only

```yaml
dev_dependencies:
  flutterpilot_sdk: ^0.1.0  # ← dev_dependencies
  flutterpilot_bloc: ^0.1.0  # ← dev_dependencies
```

Never put in `dependencies` (which go to production).

### ✅ Do: Protect Sensitive Data

Never pass API keys through FlutterPilot:

```dart
// ❌ Don't leak secrets in state
final apiKey = 'sk_live_123abc...';  // ← Visible to FlutterPilot

// ✅ Use secure storage
final apiKey = await secureStorage.read(key: 'apiKey');
```

### ✅ Do: Be Careful with SharedPreferences Inspection

`get_shared_preferences` returns ALL data, including potentially sensitive values.

```dart
// SharedPreferences are NOT encrypted
// Don't store auth tokens or API keys there

// Use flutter_secure_storage instead:
final secureStorage = FlutterSecureStorage();
await secureStorage.write(key: 'token', value: jwtToken);
```

### ✅ Do: Review Plugin Permissions

Each plugin can see different data:
- **Bloc Plugin**: Bloc state only
- **Dio Plugin**: All HTTP requests/responses
- **SharedPrefs Plugin**: All preferences
- **Drift Plugin**: All database queries (read-only)

Only load plugins you actually need.

---

## Testing Patterns

### Pattern 1: Golden File Testing

```
1. Capture screenshot of expected state
2. Save as "login_screen_golden.png"
3. Run app and capture current screenshot
4. Compare using compare_screenshots
5. Flag if different
```

### Pattern 2: State Transition Testing

```
1. Capture initial state (get_bloc_state)
2. Trigger action (tap_widget)
3. Capture new state
4. Verify state changed correctly
```

### Pattern 3: Error Flow Testing

```
Test error handling:
1. Mock endpoint to return error
2. Trigger action
3. Verify error message appears
4. Verify app recovers (no crash)
```

### Pattern 4: Navigation Testing

```
Test navigation flow:
1. Record current route (get_app_summary)
2. Perform navigation action
3. Verify new route (get_app_summary)
4. Check navigation stack
```

### Pattern 5: Integration Testing

```
Full feature test:
1. Navigate to feature
2. Fill form
3. Mock dependent APIs
4. Submit form
5. Verify navigation to success page
6. Verify state updated
```

---

## Debugging Tips

### Use get_capabilities to Understand What's Available

```bash
# Shows loaded plugins and their state
get_capabilities
```

Output tells you:
- Which plugins are initialized
- Buffer usage
- Connection status

### Start with Simple Tools

When debugging:
1. `get_app_summary` — Understand current state
2. `capture_screenshot` — See visual
3. `get_widget_tree` — Analyze structure
4. Then dive deeper with specific tools

### Use Semantic Tree for Accessibility Issues

```bash
# If visual looks right but interaction fails:
get_semantics_tree

# Shows what accessibility layer sees (what screen readers see)
```

### Check Browser DevTools

For Web-based testing:
```bash
flutter run -d chrome --web-trace-enabled
# Then open DevTools (F12)
# FlutterPilot limitations visible in console
```

---

## Common Patterns

### Waiting for Widget to Appear

```dart
// ❌ Don't do this (blocks app):
await Future.delayed(Duration(seconds: 2));

// ✅ Better: Use widget-specific waits
// Call get_widget_tree in loop until widget appears
for (int i = 0; i < 10; i++) {
  final tree = await getWidgetTree();
  if (tree.findKey('submitBtn') != null) {
    break;  // Widget appeared
  }
  await Future.delayed(Duration(milliseconds: 100));
}
```

### Asserting State Values

```dart
// Get state, verify specific value
final blocState = await getBlocState();
final userBloc = blocState['UserBloc'];
assert(userBloc['status'] == 'authenticated');
assert(userBloc['user']['email'] == 'test@example.com');
```

### Mocking Complex Responses

```
Mock /api/users with:
{
  "data": [
    {"id": "1", "name": "Alice"},
    {"id": "2", "name": "Bob"}
  ],
  "pagination": {
    "page": 1,
    "total": 2
  }
}
```

---

## Checklist: Before Shipping

- [ ] Remove all FlutterPilot plugins from `dependencies`
- [ ] Verify all FlutterPilot packages are in `dev_dependencies`
- [ ] No secrets stored in SharedPreferences (use secure storage)
- [ ] Test both iOS and Android with real devices
- [ ] Remove debugging code that uses FlutterPilot
- [ ] Verify app works without FlutterPilot initialized
- [ ] Check no FlutterPilot code paths in production binary

---

## Need More Help?

- See [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) for common issues
- See [TOOLS.md](../TOOLS.md) for complete tool reference
- See [AI_AGENTS.md](../docs/AI_AGENTS.md) for AI integration patterns
