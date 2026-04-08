# FlutterPilot SDK

The core Flutter SDK for AI-native runtime introspection.

## Features

- **Service Extensions**: Exposes a wide array of tools to the VM service.
- **Error Interception**: Automatically buffers and reports runtime errors.
- **UI Interaction**: Programmatically tap, enter text, and scroll.
- **Navigation Tracker**: Keeps track of the app's navigation stack.
- **Test Recording**: Record user interactions and generate test code.
- **Performance Metrics**: Access real-time FPS and memory usage.

## Getting started

In `pubspec.yaml`:

```yaml
dev_dependencies:
  flutterpilot_sdk: { path: packages/flutterpilot_sdk }
```

## Usage

Initialize the SDK in your `main.dart`:

```dart
void main() {
  FlutterPilot.initialize();
  runApp(const MyApp());
}
```

To enable navigation tracking, add the `NavigationPilotObserver`:

```dart
MaterialApp(
  navigatorObservers: [NavigationPilotObserver()],
  // ...
)
```
