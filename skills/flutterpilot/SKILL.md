---
name: flutterpilot
description: Autonomous Flutter UI inspection, state verification, virtual semantic key selectors, time-travel state snapshots, crash flight recorder, visual regression diffing, network chaos mocking, and runtime self-healing via FlutterPilot MCP tools.
---

# FlutterPilot Agent Skill

This skill guides AI agents on orchestrating FlutterPilot MCP tools to test, debug, and develop Flutter applications autonomously.

## When to Use
- Autonomous UI verification (filling forms, clicking buttons, testing user journeys).
- Interacting with Flutter widgets using Virtual Semantic Selectors without requiring manual `ValueKey`s.
- Time-Travel State Snapshots & instant state rewind (<100ms) across Riverpod, Bloc, and local storage.
- Continuous Crash Flight Recording & auto-synthesizing executable `repro_test.dart` reproduction tests.
- Exporting production-ready Patrol, Integration, and Widget test suites.
- Visual regression testing with pixel diff detection.
- Debugging state management (Riverpod, Bloc), network calls (Dio), databases (Drift, SQLite), or local storage (Hive, SharedPreferences, SecureStorage).
- Simulating network chaos (offline mode, slow 3G latency, synthetic 500 error mocks).
- Multi-device fleet testing across iOS, Android, and Web.
- Catching unhandled runtime exceptions and auto-applying hot reloads.

## Step-by-Step Autonomous Workflow

```mermaid
flowchart TD
    A[Connect Session] --> B[get_app_summary]
    B --> C[capture_screenshot]
    C --> D[get_widget_tree]
    D --> E[Semantic Interaction: tap_widget / enter_text]
    E --> F[Save State Checkpoint: save_state_snapshot]
    F --> G[Verify State / Network Logs / Diff]
    G --> H{Error Detected?}
    H -- Yes --> I[get_flight_log -> generate_repro_test -> Fix Code -> hot_reload]
    H -- No --> J[Complete Task]
```

### 1. Initial State Reconnaissance
```json
// 1. Get summary
call_tool("get_app_summary", {})

// 2. See visual UI
call_tool("capture_screenshot", {})

// 3. Inspect widget hierarchy with semantic selectors (PII automatically masked)
call_tool("get_widget_tree", {"maxDepth": 250})
```

### 2. UI Driving via Virtual Semantic Selectors
You can interact using explicit keys, semantic selectors, or visible button text:
```json
// Fill input field using semantic selector or label
call_tool("enter_text", {"key": "TextField['Email']", "text": "user@example.com"})

// Scroll if off-screen
call_tool("scroll_into_view", {"key": "Button['Submit']"})

// Tap button via semantic selector or text (triggers live AI visual pointer on app screen)
call_tool("tap_widget", {"key": "ElevatedButton['Sign In']"})
// Or simply by visible text:
call_tool("tap_widget", {"key": "Sign In"})

// Advance frames
call_tool("pump_frames", {"count": 10})
```

### 3. Time-Travel State Snapshots
```json
// Save current point-in-time state checkpoint
call_tool("save_state_snapshot", {"name": "onboarding_step_2"})

// Rewind app state anytime in <100ms without restarting
call_tool("restore_state_snapshot", {"name": "onboarding_step_2"})
```

### 4. Visual Regression Diff Engine
```json
// 1. Establish golden baseline
call_tool("save_screenshot_baseline", {"name": "checkout_screen"})

// 2. After making modifications, compare:
call_tool("compare_screenshot", {"name": "checkout_screen", "threshold": 0.5})
```

### 5. Network Chaos & Mocking
```json
// Mock endpoint with synthetic 500 error
call_tool("mock_http_response", {
  "urlPattern": "/api/v1/payment",
  "statusCode": 500,
  "body": "{\"error\": \"Payment processor unavailable\"}",
  "delayMs": 1000
})

// Simulate slow 3G or offline
call_tool("simulate_network", {"condition": "slow_3g"})
call_tool("simulate_offline", {"enabled": "true"})
```

### 6. Multi-Device Fleet Manager
```json
// List connected iOS/Android/Web instances
call_tool("list_connected_devices", {})

// Switch target device
call_tool("switch_device", {"id": "android_emu"})
```

### 7. Crash Flight Recorder & Self-Healing
```json
// 1. Inspect the 30s rolling flight timeline
call_tool("get_flight_log", {})

// 2. Auto-generate reproduction test to disk
call_tool("generate_repro_test", {
  "testName": "Reproduce checkout crash",
  "writeToDisk": true
})

// 3. After editing Dart file in workspace, hot reload:
call_tool("hot_reload", {})
```
