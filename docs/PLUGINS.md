# FlutterPilot Plugin Development Guide

Complete guide to creating custom FlutterPilot plugins for state managers and services.

## Table of Contents
- [Plugin Architecture](#plugin-architecture)
- [Creating a Custom Plugin](#creating-a-custom-plugin)
- [Built-in Plugins](#built-in-plugins)
- [Testing Your Plugin](#testing-your-plugin)
- [Examples](#examples)

---

## Plugin Architecture

### What is a Plugin?

A plugin is a Dart package that:
1. Hooks into a third-party library (e.g., Bloc, Riverpod)
2. Registers a **service extension** with FlutterPilot SDK
3. Exposes state for inspection and manipulation via the server

### How Plugins Work

```
┌──────────────────────────────────────────────────────┐
│ Your App                                             │
├──────────────────────────────────────────────────────┤
│ Bloc.observer = BlocPilotObserver()                  │
│              ↓                                        │
│ Bloc fires events → BlocPilotObserver.onChange()     │
│              ↓                                        │
│ Static map _blocStates updated:                      │
│   {'MyBloc': {'state': 'loaded', 'timestamp': ...}}  │
│              ↓                                        │
│ registerExtension('ext.flutterpilot.getBlocStates'   │
│                   → returns JSON of _blocStates      │
└──────────────────────────────────────────────────────┘
         ↑                                 ↓
         │      VM Service WebSocket       │
         │                                 ↓
┌──────────────────────────────────────────────────────┐
│ FlutterPilot Server                                  │
├──────────────────────────────────────────────────────┤
│ AI Agent calls: get_bloc_state()                     │
│             ↓                                        │
│ Server calls: _callExtensionRaw(                     │
│   'ext.flutterpilot.getBlocStates', {}              │
│ )                                                    │
│             ↓                                        │
│ Returns _blocStates JSON to AI Agent                │
└──────────────────────────────────────────────────────┘
```

---

## Creating a Custom Plugin

### Step 1: Create Package Structure

```bash
cd packages/plugins
mkdir flutterpilot_mylib
cd flutterpilot_mylib

# Create package
dart create --template=package .
```

Your structure:
```
flutterpilot_mylib/
├── lib/
│   └── flutterpilot_mylib.dart       # Main plugin file
├── test/
│   └── flutterpilot_mylib_test.dart  # Plugin tests
├── pubspec.yaml                      # Package metadata
├── analysis_options.yaml              # Lint config
└── README.md                          # Plugin docs
```

### Step 2: Define pubspec.yaml

```yaml
name: flutterpilot_mylib
description: FlutterPilot integration for MyLib state manager.
version: 0.1.0

environment:
  sdk: ^3.11.0
  flutter: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  mylib: ^1.0.0                    # The library you're integrating
  flutterpilot_sdk: ^0.1.0         # Always depend on core SDK

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  test: ^1.24.0
```

### Step 3: Implement Plugin Observer

**lib/flutterpilot_mylib.dart**:

```dart
import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mylib/mylib.dart';  // The library to integrate
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// Observer for MyLib state manager.
///
/// Tracks state changes and exposes them via `ext.flutterpilot.getMyLibStates`.
///
/// ## Setup
/// ```dart
/// void main() {
///   FlutterPilot.initialize();
///   MyLib.addObserver(MyLibPilotObserver());  // Register observer
///   runApp(MyApp());
/// }
/// ```
class MyLibPilotObserver extends MyLibObserver {
  // Static state tracking — survives widget lifecycle
  static final Map<String, dynamic> _states = {};
  static bool _initialized = false;
  static const int _maxEntries = 100;

  MyLibPilotObserver() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  /// Register service extension for state inspection.
  void _registerExtension() {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: MyLibPilotObserver registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
      return;
    }

    // Register state getter
    registerExtension('ext.flutterpilot.getMyLibStates', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'states': _states}),
      );
    });

    // (Optional) Register state setter
    registerExtension('ext.flutterpilot.setMyLibState', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final value = parameters['value'];

      if (key == null || value == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key or value',
        );
      }

      try {
        // Your implementation: find the store and update state
        // Example:
        // final store = MyLib.getStore(key);
        // await store.setState(value);

        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'key': key}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Failed to set state: $e',
        );
      }
    });
  }

  /// Clean up stale state entries when buffer grows too large.
  static void _cleanStaleEntries() {
    if (_states.length >= _maxEntries) {
      // Remove old entries, keep recent ones
      final keys = _states.keys.toList();
      final toRemove = keys.length - _maxEntries + 1;
      for (int i = 0; i < toRemove; i++) {
        _states.remove(keys[i]);
      }
    }
  }

  /// Clear state on hot-restart to prevent memory leaks.
  static void reset() {
    _states.clear();
    _initialized = false;
  }

  // Implement observer callbacks from MyLib
  @override
  void onStateChange(String key, dynamic newValue) {
    _states[key] = {
      'value': newValue?.toString() ?? 'null',
      'type': newValue.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    _cleanStaleEntries();
  }

  // Add other callback methods as needed...
}
```

### Step 4: Add Tests

**test/flutterpilot_mylib_test.dart**:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_mylib/flutterpilot_mylib.dart';

void main() {
  group('MyLibPilotObserver', () {
    test('initializes correctly', () {
      final observer = MyLibPilotObserver();
      expect(observer, isNotNull);
    });

    test('tracks state changes', () {
      final observer = MyLibPilotObserver();
      // Simulate state change
      observer.onStateChange('myKey', 'myValue');
      // Verify state was recorded
      // (You may need to use reflection to access static _states)
    });

    test('resets state on hot-restart', () {
      MyLibPilotObserver.reset();
      // Verify _states is cleared
    });
  });
}
```

### Step 5: Update melos.yaml

Add your plugin to the root `melos.yaml`:

```yaml
packages:
  - 'packages/plugins/flutterpilot_mylib'
```

Then bootstrap:
```bash
melos bootstrap
```

### Step 6: Add to Server Tools

In **packages/flutterpilot_server/lib/src/tools/state_management_tools.dart**:

```dart
// After existing state tools, add:
_registerAppTool(
  name: 'get_mylib_state',
  description:
      'Inspect current MyLib state values. Call this to debug state flow.',
  extension: 'ext.flutterpilot.getMyLibStates',
  formatResult: (json) {
    final states = json['states'] as Map?;
    if (states == null || states.isEmpty) return 'No MyLib state.';
    return states
        .entries
        .map((e) => '${e.key}: ${e.value['value']} (${e.value['type']})')
        .join('\n');
  },
);
```

---

## Built-in Plugins

### flutterpilot_bloc

**Purpose**: Track Bloc/Cubit state

**Setup**:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';

void main() {
  FlutterPilot.initialize();
  Bloc.observer = BlocPilotObserver();
  runApp(MyApp());
}
```

**Server Tool**: `get_bloc_state`, `set_bloc_state`

**Capabilities**: Full state read/write

### flutterpilot_riverpod

**Purpose**: Track Riverpod provider values

**Setup**:
```dart
import 'package:riverpod/riverpod.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';

void main() {
  FlutterPilot.initialize();
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: MyApp(),
    ),
  );
}
```

**Server Tools**: `get_riverpod_state`, `set_riverpod_state`

**Capabilities**: Full state read/write, container tracking

### flutterpilot_dio

**Purpose**: Log HTTP requests, mock endpoints, simulate network conditions

**Setup**:
```dart
import 'package:dio/dio.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';

final dio = Dio();

void main() {
  FlutterPilot.initialize();
  dio.interceptors.add(DioPilotInterceptor());
  runApp(MyApp());
}
```

**Server Tools**: 
- `get_network_logs` — HTTP request/response log
- `simulate_network` — offline, slow 3G, fast 4G
- `add_http_mock` — Mock endpoint with status/body
- `clear_http_mocks` — Remove mocks

**Capabilities**: Log inspection, condition simulation, response mocking

### flutterpilot_drift

**Purpose**: Inspect database via SQL queries (read-only)

**Setup**:
```dart
import 'package:drift/drift.dart';
import 'package:flutterpilot_drift/flutterpilot_drift.dart';

void main() {
  FlutterPilot.initialize();
  DriftPilotInspector.registerDatabase('main', myDatabase);
  runApp(MyApp());
}
```

**Server Tools**: 
- `query_drift_db` — Execute SELECT/EXPLAIN/PRAGMA/WITH
- `list_drift_tables` — Enumerate tables

**Capabilities**: Read-only SQL with injection prevention

### flutterpilot_hive

**Purpose**: Inspect Hive boxes (read-only)

**Setup**:
```dart
import 'package:hive/hive.dart';
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

void main() async {
  await Hive.initFlutter();
  FlutterPilot.initialize();
  
  final box = await Hive.openBox('settings');
  HivePilotInspector.registerBox('settings');
  
  runApp(MyApp());
}
```

**Server Tools**: `get_hive_contents` — All box contents

**Capabilities**: Read-only box inspection

### flutterpilot_shared_preferences

**Purpose**: Inspect and modify SharedPreferences

**Setup**:
```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';

void main() async {
  final prefs = await SharedPreferences.getInstance();
  FlutterPilot.initialize();
  SharedPrefsPilotInspector.register(prefs);
  runApp(MyApp());
}
```

**Server Tools**: 
- `get_shared_preferences` — All preferences
- `set_shared_preference` — Write key/value
- `clear_shared_preferences` — Delete key or all

**Capabilities**: Full read/write

---

## Testing Your Plugin

### Unit Tests

```dart
test('plugin initializes without FlutterPilot', () {
  // Should log warning but not crash
  final observer = MyLibPilotObserver();
  expect(observer, isNotNull);
});

test('plugin initializes with FlutterPilot', () {
  FlutterPilot.initialize();
  final observer = MyLibPilotObserver();
  // Should succeed without warning
});
```

### Integration Testing

1. Create a test app that uses your plugin
2. Run the app
3. Manually call the server tools
4. Verify correct results

### Manual Testing

```bash
# Build your plugin
cd packages/plugins/flutterpilot_mylib
dart pub get
dart pub run test

# Add to example app
cd ../../examples/flutter_pilot_example
flutter pub add --dev ../plugins/flutterpilot_mylib

# Run with plugin
flutter run
```

---

## Examples

### Example 1: GetX State Manager Plugin

```dart
import 'package:get/get.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

class GetXPilotObserver {
  static final Map<String, dynamic> _controllers = {};
  static bool _initialized = false;

  static void initialize() {
    if (!_initialized) {
      _initialized = true;
      registerExtension('ext.flutterpilot.getGetXState', (_, __) async {
        return ServiceExtensionResponse.result(
          json.encode({'controllers': _controllers}),
        );
      });
    }
  }

  static void trackController(String name, GetxController controller) {
    _controllers[name] = controller.obs.toString();  // Simplified
  }
}

// Usage in main:
// void main() {
//   FlutterPilot.initialize();
//   GetXPilotObserver.initialize();
//   runApp(MyApp());
// }
```

### Example 2: Firebase Realtime Database Plugin

```dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

class FirebaseRTPilotObserver {
  static final Map<String, dynamic> _snapshots = {};

  static void initialize() {
    registerExtension('ext.flutterpilot.getFirebaseRTData', (_, __) async {
      return ServiceExtensionResponse.result(
        json.encode({'data': _snapshots}),
      );
    });
  }

  static void trackSnapshot(String path, DataSnapshot snapshot) {
    _snapshots[path] = snapshot.value;
  }
}
```

---

## Best Practices

1. **Always clear state on hot-restart**: Implement `reset()` method
2. **Bound state size**: Implement `_cleanStaleEntries()` to cap buffer
3. **Register extension safely**: Check `FlutterPilot.isInitialized` first
4. **Use descriptive names**: `ext.flutterpilot.<library><action>`
5. **Return structured JSON**: Clients expect consistent format
6. **Document setup steps**: Users need clear instructions
7. **Add tests**: Unit + integration tests boost adoption

---

## Submitting Your Plugin

1. Create GitHub repo: `flutterpilot_mylib`
2. Publish to pub.dev
3. Open PR to add to FlutterPilot plugins list
4. Update docs with plugin reference

See [CONTRIBUTING.md](../CONTRIBUTING.md) for details.
