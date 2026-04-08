# FlutterPilot SDK

The core Flutter SDK for AI-native runtime introspection.

## Features

- **Service Extensions** — Exposes 20+ tools to the VM service for remote inspection and control.
- **Error Interception** — Automatically buffers and reports runtime errors.
- **UI Interaction** — Programmatically tap, enter text, and scroll.
- **Navigation Tracker** — Keeps track of the app's navigation stack.
- **Session Recording** — Record user interactions and replay them.
- **Performance Metrics** — Access real-time FPS estimates.
- **Widget Tree Inspection** — Serialize the full widget tree to JSON.
- **Screenshot Capture** — Capture the current screen as a PNG.
- **Locale Override** — Switch the app's locale at runtime.
- **Custom Tools** — Register app-specific tools callable by AI agents.
- **State Injection** — Write state values into Riverpod, Bloc, or any registered state manager.

## Getting Started

Add the SDK as a dev dependency in `pubspec.yaml`:

```yaml
dev_dependencies:
  flutterpilot_sdk: ^0.1.0
```

## Usage

### Initialize

Call `FlutterPilot.initialize()` **before** `runApp`:

```dart
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  FlutterPilot.initialize();
  runApp(const MyApp());
}
```

### Navigation Tracking

Add `NavigationTracker` as a navigator observer:

```dart
MaterialApp(
  navigatorObservers: [NavigationTracker()],
)
```

### Register Custom Tools

Expose app-specific actions to the AI agent:

```dart
FlutterPilot.registerCustomTool('clearCache', (params) async {
  await cacheManager.clear();
  return {'cleared': true};
});
```

### State Injection

Register a state setter for your state-management system:

```dart
FlutterPilot.registerStateSetter('riverpod', (name, value) async {
  final provider = lookupProviderByName(name);
  container.read(provider.notifier).state = value;
  return container.read(provider);
});
```

### Locale Override

Listen to `FlutterPilot.localeNotifier` to respond to runtime locale changes:

```dart
ValueListenableBuilder<Locale?>(
  valueListenable: FlutterPilot.localeNotifier,
  builder: (context, locale, child) {
    return MaterialApp(locale: locale);
  },
)
```

## API Overview

### `FlutterPilot` (main class)

| Method | Description |
|---|---|
| `initialize()` | Initializes the SDK. Must be called before `runApp`. Idempotent. |
| `registerCustomTool(name, callback)` | Registers a tool callable via `ext.flutterpilot.callCustomTool`. |
| `registerStateSetter(type, setter)` | Registers a state setter invoked by `ext.flutterpilot.setState`. |
| `logStateChange(source, name, value)` | Logs a state change event during session recording. |
| `localeNotifier` | `ValueNotifier<Locale?>` for runtime locale overrides. |

### `NavigationTracker`

A `NavigatorObserver` that maintains a static route stack.

| Member | Description |
|---|---|
| `stack` | Unmodifiable list of route names (bottom → top). |
| `currentRoute` | Name of the top-most route. |
| `reset()` | Clears the stack (for tests). |

### `ErrorInspector`

Intercepts Flutter errors into a capped buffer (max 10).

| Member | Description |
|---|---|
| `errors` | Unmodifiable list of captured error maps. |
| `initialize()` | Hooks into `FlutterError.onError`. Idempotent. |

### `PilotWidgetInspector`

Read-only widget tree introspection.

| Method | Description |
|---|---|
| `captureWidgetTree()` | Returns the full tree as a nested JSON map. |
| `findElementByKey(key)` | Finds an `Element` by its string key. |
| `countElements(element)` | Counts all elements in a subtree. |

### `InteractionManager`

Pointer tracking and gesture simulation.

| Method | Description |
|---|---|
| `initialize()` | Installs a global pointer listener. |
| `tapAt(position)` | Simulates a tap at screen coordinates. |

## Service Extensions Reference

All extensions are in the `ext.flutterpilot.*` namespace.

| Extension | Parameters | Description |
|---|---|---|
| `ping` | — | Health check; returns SDK version. |
| `getSummary` | — | Current route, error count, recording state, widget count. |
| `getErrors` | — | Returns buffered errors. |
| `getWidgetTree` | — | Full widget tree as JSON. |
| `captureScreenshot` | — | Base64-encoded PNG screenshot. |
| `getNavigationStack` | — | Ordered route stack. |
| `getPerfMetrics` | — | Current FPS estimate. |
| `navigateTo` | `route` | Pushes a named route. |
| `setLocale` | `locale` | Overrides locale (`'fr'`, `'pt_BR'`, or `'default'`). |
| `startRecording` | — | Begins session recording. |
| `stopRecording` | — | Stops recording; returns captured actions. |
| `tapAt` | `x`, `y` | Simulates tap at coordinates. |
| `tapWidget` | `key` | Taps center of widget by key. |
| `enterText` | `key`, `text` | Sets text on a text field by key. |
| `scrollIntoView` | `key` | Scrolls widget into viewport. |
| `setState` | `type`, `name`, `value` | Injects state via registered setter. |
| `listCustomTools` | — | Lists registered custom tools. |
| `callCustomTool` | `name`, ... | Invokes a custom tool. |
