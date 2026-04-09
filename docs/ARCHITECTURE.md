# FlutterPilot Architecture Guide

Complete guide to FlutterPilot's design, components, and how they work together.

## Table of Contents
- [System Overview](#system-overview)
- [Core Components](#core-components)
- [Data Flow](#data-flow)
- [Plugin System](#plugin-system)
- [Error Handling](#error-handling)
- [Concurrency & Safety](#concurrency--safety)

---

## System Overview

FlutterPilot is a distributed system with three main layers:

```
┌─────────────────────────────────────────────────────────────┐
│ AI Agent (Claude, Cursor, etc.)                             │
│ - Sends MCP requests (JSON-RPC over stdio)                  │
└────────────────────────────┬────────────────────────────────┘
                             │ JSON-RPC (stdio)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ FlutterPilot MCP Server (Dart)                              │
│ - Receives tool calls                                        │
│ - Routes to VM service                                      │
│ - Returns results as text/JSON/images                       │
└────────────────────────────┬────────────────────────────────┘
                             │ VM Service WebSocket
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ Running Flutter App (Dart)                                  │
│ - FlutterPilot SDK hooks                                    │
│ - Service extensions register                               │
│ - Event streams emit diagnostics                            │
│ - Plugins track state                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. FlutterPilot SDK (`flutterpilot_sdk`)

**Location**: `packages/flutterpilot_sdk/`

**Responsibility**: Instrumentation hooks inside the running Flutter app.

**Key Classes**:
- `FlutterPilot` (main) — Initialization, static state, service extension registration
- `PilotWidgetInspector` — Widget tree serialization with bounds
- `ErrorInspector` — Crash detection and stack trace capture
- `NavigationTracker` — Route history and deep link handling
- `InteractionManager` — Global pointer listener for tap tracking

**Service Extensions** (VM service handlers):
```
ext.flutterpilot.captureScreenshot    → PNG as base64
ext.flutterpilot.getWidgetTree        → JSON widget hierarchy
ext.flutterpilot.getSemanticsTree     → Accessibility tree
ext.flutterpilot.tapWidget            → Simulate tap
ext.flutterpilot.enterText            → Input text
ext.flutterpilot.scroll               → Scroll viewport
ext.flutterpilot.getNavigation        → Route stack
ext.flutterpilot.getRiverpodStates    → Provider values
ext.flutterpilot.getBlocStates        → Bloc values
... (and 20+ more)
```

**Zero External Dependencies**: SDK uses only Flutter/Dart built-ins. This ensures it adds no bloat to your app.

### 2. FlutterPilot Server (`flutterpilot_server`)

**Location**: `packages/flutterpilot_server/`

**Responsibility**: MCP server that bridges AI agents to the Flutter app.

**Architecture**:
- Main class: `FlutterPilotServer` (~640 lines)
- 8 tool mixin files in `src/tools/`:
  - `app_inspection_tools.dart` — Summary, errors, logs, build config
  - `ui_automation_tools.dart` — Tap, scroll, text input, gestures
  - `screenshot_tools.dart` — Capture, compare, baseline management
  - `navigation_tools.dart` — Routes, deep links, navigation
  - `state_management_tools.dart` — Bloc, Riverpod, Hive, Drift, SharedPrefs
  - `testing_tools.dart` — Assertions, wait conditions, recordings
  - `devtools_tools.dart` — DevTools integration, profiling
  - `self_heal_tools.dart` — Crash analysis and recovery

**Key Features**:
- Auto-reconnect with exponential backoff
- Event stream buffering (events, logs, screenshots)
- Crash detection via self-heal manager
- Tool registration as MCP capabilities

**Error Handling**:
- `ErrorCategory` enum for structured errors (connectionLost, timeout, toolNotFound, etc.)
- Tools return typed errors so AI agents can retry intelligently

### 3. Plugins (State Management Integration)

**Location**: `packages/plugins/`

**Purpose**: Track and inject state in third-party packages.

**6 Plugins**:
1. **flutterpilot_bloc** — Bloc/Cubit observer
   - Tracks state changes
   - Allows state injection
   - Reset on hot-restart

2. **flutterpilot_riverpod** — Riverpod observer
   - Monitors provider changes
   - Container tracking
   - Reset on hot-restart

3. **flutterpilot_dio** — HTTP interceptor
   - Request/response logging
   - Network condition simulation (offline, slow 3G, etc.)
   - HTTP mocking

4. **flutterpilot_drift** — Database inspector
   - Read-only SQL queries
   - Table enumeration
   - SQL injection prevention

5. **flutterpilot_hive** — Local storage inspector
   - Box contents enumeration
   - No write support (read-only)

6. **flutterpilot_shared_preferences** — Preference viewer
   - Read preferences
   - Write preferences
   - Clear keys

**Plugin Pattern**:
```dart
// Static registration at app startup
void main() {
  FlutterPilot.initialize();
  Bloc.observer = BlocPilotObserver();  // Hook into Bloc
  runApp(MyApp());
}

// Service extension registered inside plugin
registerExtension('ext.flutterpilot.getBlocStates', (...) {
  return ServiceExtensionResponse.result(json.encode(_states));
});

// Server calls the extension
await _callExtensionRaw('ext.flutterpilot.getBlocStates', {})
```

---

## Data Flow

### Example: User taps a button

```
1. AI Agent calls tool: tap_widget(key: "submitButton")
   ↓
2. MCP Server receives: {
     "jsonrpc": "2.0",
     "method": "tools/call",
     "params": { "name": "tap_widget", "arguments": { "key": "submitButton" } }
   }
   ↓
3. Server routes to _registerUiAutomationTools → tap_widget callback
   ↓
4. Callback invokes: _callExtensionRaw("ext.flutterpilot.tapWidget", {"key": "submitButton"})
   ↓
5. VM Service forwards to running app isolate
   ↓
6. SDK finds element by key using PilotWidgetInspector.findElementByKey()
   ↓
7. SDK simulates tap via _simulateTap (pointer events + synthetic tap)
   ↓
8. Flutter processes tap → widget's onPressed() fires
   ↓
9. App may navigate, state changes, errors occur
   ↓
10. Server catches errors via _eventBuffer stream listener
   ↓
11. Server returns to AI Agent: {
      "type": "text",
      "text": "Tap successful. Use get_navigation_stack or get_errors to verify."
    }
```

### Example: Check app state

```
1. AI Agent calls: get_riverpod_state()
   ↓
2. Server invokes _callExtensionRaw("ext.flutterpilot.getRiverpodStates", {})
   ↓
3. Plugin (RiverpodPilotObserver) returns JSON of active providers
   ↓
4. Server formats result → MCP Image/Text content
   ↓
5. AI Agent receives and parses provider values
```

---

## Plugin System

### How Plugins Register State

Each plugin follows this pattern:

```dart
class BlocPilotObserver extends BlocObserver {
  static final Map<String, dynamic> _blocStates = {};
  static final Map<String, BlocBase> _activeBlocs = {};
  
  void _registerExtension() {
    // Called once when first BlocPilotObserver() is created
    registerExtension('ext.flutterpilot.getBlocStates', (method, params) async {
      return ServiceExtensionResponse.result(json.encode({'states': _blocStates}));
    });
  }
  
  @override
  void onChange(BlocBase bloc, Change change) {
    // Track every state change
    _blocStates[bloc.runtimeType.toString()] = change.nextState;
  }
  
  static void reset() {
    // Called on hot-restart to avoid memory leaks
    _blocStates.clear();
    _activeBlocs.clear();
  }
}
```

### Server's Plugin Discovery

```dart
// In get_capabilities tool:
final pluginStatus = <String, String>{};
for (final entry in <String, String>{
  'bloc': 'ext.flutterpilot.getBlocStates',
  'riverpod': 'ext.flutterpilot.getRiverpodStates',
  // ... etc
}.entries) {
  final res = await _callExtensionRaw(entry.value, {});
  pluginStatus[entry.key] = res.isError ? 'not_loaded' : 'loaded';
}
```

---

## Error Handling

### Error Categories

Server uses structured `ErrorCategory` enum for intelligent retry logic:

```dart
enum ErrorCategory {
  connectionLost,    // VM Service disconnected → try reconnect
  reconnecting,      // VM Service reconnecting → retry later
  timeout,           // Extension call timeout → retry or fail
  toolNotFound,      // Extension not in isolate → check plugin loaded
  extensionError,    // Extension returned error → don't retry
  validation,        // Input validation failed → fix inputs
}
```

### Error Response Format

```json
{
  "content": [{
    "type": "text",
    "text": "[timeout] Extension call timed out. The app may be unresponsive."
  }],
  "isError": true
}
```

The `[timeout]` prefix tells AI agents: "This might succeed if you try again."

### Server Reconnection Strategy

```dart
// Exponential backoff: 1s → 2s → 4s → ... → 30s max
// With ±25% jitter to avoid thundering herd
Duration _currentBackoff = Duration.seconds(1);

void _attemptReconnect() {
  final jitter = (_currentBackoff.inMilliseconds * 0.25 * (2 * random - 1)).round();
  final delay = Duration(milliseconds: _currentBackoff.inMilliseconds + jitter);
  
  Timer(delay, () async {
    try {
      await _connectToVmService();
      _currentBackoff = Duration.seconds(1);  // Reset on success
    } catch (e) {
      _currentBackoff = Duration(milliseconds: 
        (_currentBackoff.inMilliseconds * 2).clamp(1000, 30000)
      );
      _attemptReconnect();  // Try again
    }
  });
}
```

---

## Concurrency & Safety

### Buffer Management

All buffers are bounded and use `Queue` (O(1) operations):

```dart
// From flutterpilot_server.dart
final Queue<Map<String, dynamic>> _eventBuffer = Queue();
final Queue<Map<String, dynamic>> _debugLogBuffer = Queue();

// In event handler:
_eventBuffer.add(event);
if (_eventBuffer.length > _Constants.eventBufferMax) {
  _eventBuffer.removeFirst();  // O(1), not O(n)
}
```

Buffer limits in `src/constants.dart`:
- `eventBufferMax`: 50
- `debugLogBufferMax`: 500
- `maxScreenshotBaselines`: 20

### Widget Tree Depth Safety

```dart
// Prevents stack overflow on extremely deep trees
static Map<String, dynamic> captureWidgetTree({int? maxDepth}) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return {'error': 'No root element found'};
  return _elementToJson(root, 0, maxDepth ?? 50);  // Default 50, max 200
}

static Map<String, dynamic> _elementToJson(
  Element element,
  int currentDepth,
  int maxDepth,
) {
  final children = <Map<String, dynamic>>[];
  if (currentDepth < maxDepth) {  // Stop recursion at limit
    element.visitChildren(
      (child) => children.add(_elementToJson(child, currentDepth + 1, maxDepth)),
    );
  }
  // ... rest of serialization
}
```

### Plugin State Cleanup

```dart
// Hot restart shouldn't leak old state
static void reset() {
  _blocStates.clear();
  _activeBlocs.clear();
  _initialized = false;
}
```

Called in development workflow to prevent memory growth across restarts.

### VM Service Communication

Single-threaded, sequential tool calls:
```dart
Future<_ExtensionResult> _callExtensionRaw(
  String extension,
  Map<String, dynamic> parameters,
) async {
  // Get all isolates
  final vm = await _vmService!.getVM().timeout(_Constants.vmServiceTimeout);
  for (final isolateRef in vm.isolates ?? []) {
    try {
      // Call extension in this isolate
      final response = await _vmService!.callServiceExtension(
        extension,
        isolateId: isolateRef.id!,
        args: Map<String, String>.from(parameters),
      ).timeout(_Constants.extensionCallTimeout);
      // Return on first success
      if (response.json != null && response.json!['error'] == null) {
        return _ExtensionResult.success(response.json!);
      }
    } on TimeoutException {
      // Isolate is busy, try next one
      continue;
    }
  }
}
```

---

## Summary

| Component | Role | Key Files |
|-----------|------|-----------|
| **SDK** | In-app instrumentation, service extensions | `packages/flutterpilot_sdk/` |
| **Server** | MCP server, tool orchestration, event streaming | `packages/flutterpilot_server/` |
| **Plugins** | State tracking integration (Bloc, Riverpod, etc.) | `packages/plugins/` |
| **Error System** | Structured categorization for AI retry logic | `ErrorCategory` enum |
| **Safety** | Bounded buffers, depth limiting, plugin cleanup | Constants, reset() methods |

The architecture prioritizes **reliability**, **safety**, and **AI-agent usability** — structured errors, discoverable capabilities, and clean state management.
