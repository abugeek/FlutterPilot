# FlutterPilot SDK

The lightweight core Flutter SDK for AI-native runtime introspection. **Zero external dependencies** — only `flutter` and `meta`.

## Features

- **43+ Service Extensions** — Complete remote control via VM service
- **Widget Introspection** — Read text, state, bounds from any widget
- **Screenshots** — RenderRepaintBoundary capture as PNG
- **Error Interception** — Automatic error buffering and reporting
- **Navigation Tracking** — Route stack with history
- **UI Automation** — Tap, scroll, text entry, deep links
- **Accessibility** — Full semantics tree for VoiceOver/TalkBack
- **Test Recording** — Record taps → generate integration tests
- **Custom Tools** — Register app-specific tools
- **State Injection** — Write state into Riverpod, Bloc, etc.

## Installation

```bash
flutter pub add --dev flutterpilot_sdk
```

Or in `pubspec.yaml`:
```yaml
dev_dependencies:
  flutterpilot_sdk: ^0.1.0
```

## Quick Start

```dart
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  FlutterPilot.initialize();  // Must be before runApp!
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [NavigationTracker()],
      home: MyHomePage(),
    );
  }
}
```

## Service Extensions Reference

All extensions are registered in the `ext.flutterpilot.*` namespace and callable via the VM service or MCP server.

### Inspection & State (18 Extensions)

| Extension | Parameters | Returns | Description |
|-----------|-----------|---------|-------------|
| `ping` | — | `{version}` | Health check |
| `getSummary` | — | `{currentRoute, errorCount, recordingState, widgetCount}` | App snapshot |
| `getErrors` | — | `{errors: [...]}` | Buffered runtime errors |
| `getWidgetTree` | — | `{tree: {...}}` | Full widget hierarchy as JSON |
| `captureScreenshot` | — | `base64-png` | PNG screenshot |
| `getNavigationStack` | — | `{stack: [...]}` | Route stack (bottom → top) |
| `getPerfMetrics` | — | `{fps, memory, frameTime}` | Performance metrics |
| `getSemantics Tree` | — | `{root: {...}}` | Accessibility tree (VoiceOver/TalkBack) |
| `getWidgetProperties` | `key` | `{text, isEnabled, isChecked, value, isFocused, bounds}` | Read any widget's state |
| `assertWidgetEnabled` | `key` | `{enabled: true}` | Assert widget is interactive |
| `assertWidgetDisabled` | `key` | `{disabled: true}` | Assert widget is disabled |
| `getRiverpodStates` | — | `{providers: {...}}` | Active Riverpod providers (if plugin registered) |
| `getBlocStates` | — | `{blocs: {...}}` | Active Bloc/Cubit states (if plugin registered) |
| `getNetworkLogs` | — | `{requests: [...]}` | HTTP requests (if Dio plugin registered) |
| `queryDriftDb` | `sql` | `{rows: [...]}` | Database query results (if Drift plugin registered) |
| `getHiveContents` | — | `{boxes: {...}}` | Hive storage contents (if Hive plugin registered) |
| `getSharedPreferences` | — | `{prefs: {...}}` | SharedPreferences key-value map (if plugin registered) |
| `getBuildConfig` | — | `{pubspec: {...}}` | pubspec.yaml and build metadata |

### UI Automation (18 Extensions)

| Extension | Parameters | Returns | Description |
|-----------|-----------|---------|-------------|
| `tapAt` | `x, y` | `{success}` | Tap at screen coordinates |
| `tapWidget` | `key` | `{success}` | Tap widget center by key |
| `doubleTapWidget` | `key` | `{success}` | Double-tap widget by key |
| `longPressWidget` | `key` | `{success}` | Long-press widget by key |
| `enterText` | `key, text` | `{success}` | Fill text field by key |
| `clearTextField` | `key` | `{success}` | Clear text field by key |
| `scrollIntoView` | `key, duration?` | `{success}` | Scroll until widget visible |
| `scrollBy` | `dx, dy, duration?` | `{success}` | Scroll by pixel amount |
| `pressBack` | — | `{popped: bool}` | Pop current route (hardware back) |
| `setSliderValue` | `key, value` | `{success}` | Set slider to numeric value |
| `toggleCheckbox` | `key` | `{success}` | Toggle checkbox/switch/radio |
| `focusWidget` | `key` | `{success}` | Request focus on widget |
| `unfocusAll` | — | `{success}` | Dismiss keyboard |
| `navigateTo` | `route` | `{success}` | Push named route |
| `simulateDeepLink` | `url` | `{success}` | Trigger deep link navigation |
| `setLocale` | `locale` | `{success}` | Switch app language (`'en'`, `'es'`, `'pt_BR'`, `'default'`) |
| `setTheme` | `'light' \| 'dark'` | `{success}` | Switch theme mode |
| `setTextScaleFactor` | `scale` | `{success}` | Accessibility text scale (1.0 = normal) |

### Recording & Performance (7 Extensions)

| Extension | Parameters | Returns | Description |
|-----------|-----------|---------|-------------|
| `startRecording` | — | `{recording: true}` | Begin session recording |
| `stopRecording` | — | `{actions: [...]}` | Stop; return captured actions |
| `pumpFrames` | `count` | `{success}` | Wait for N vsync frames |
| `showPerformanceOverlay` | `show` | `{success}` | Toggle Flutter performance overlay |
| `hotReload` | — | `{success}` | Trigger hot reload |
| `setDeviceRotation` | `'portrait' \| 'landscape'` | `{success}` | Device orientation |
| `getLatestCrashReport` | — | `{crash: {...}}` | Full error report after crash |

### Custom Tools & State (4 Extensions)

| Extension | Parameters | Returns | Description |
|-----------|-----------|---------|-------------|
| `listCustomTools` | — | `{tools: [...]}` | List registered custom tools |
| `callCustomTool` | `name, ...args` | `{...result}` | Execute app-specific tool |
| `setState` | `type, name, value` | `{success, value}` | Inject state (riverpod/bloc/custom) |
| `registerCustomTool` | `name, callback` | — | Register tool at runtime (Dart-side only) |

---

## API Classes

### `FlutterPilot` (Main)

```dart
class FlutterPilot {
  // Core
  static void initialize();  // Must be called before runApp
  static String get sdkVersion => '0.1.0';
  
  // Notifiers (listen for runtime changes)
  static final localeNotifier = ValueNotifier<Locale?>(null);
  static final textScaleNotifier = ValueNotifier<double?>(null);
  
  // Custom tools
  static Future<void> registerCustomTool(
    String name,
    Future<dynamic> Function(Map<String, dynamic>) callback,
  );
  
  // State injection
  static Future<void> registerStateSetter(
    String type,  // 'riverpod', 'bloc', 'custom'
    Future<dynamic> Function(String name, dynamic value) setter,
  );
  
  // Logging (for test recording)
  static void logStateChange(String source, String name, dynamic value);
}
```

### `NavigationTracker` (Observer)

```dart
class NavigationTracker extends NavigatorObserver {
  // Static for global access
  static List<String> get stack;      // Route stack (unmodifiable)
  static String get currentRoute;     // Top-most route name
  static void reset();                // Clear stack (for tests)
}
```

### `ErrorInspector` (Global)

```dart
class ErrorInspector {
  static List<Map<String, dynamic>> get errors;  // Last 10 errors
  static void initialize();  // Hook into FlutterError.onError (idempotent)
}
```

### `PilotWidgetInspector` (Introspection)

```dart
class PilotWidgetInspector {
  static Map<String, dynamic> captureWidgetTree();
  static Element? findElementByKey(String key);
  static int countElements(Element root);
}
```

### `InteractionManager` (Gestures)

```dart
class InteractionManager {
  static void initialize();  // Install pointer listener (called by SDK.initialize)
  static Future<void> tapAt(Offset position);
}
```

---

## Integration Patterns

### With Riverpod

```dart
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';

ProviderScope(
  observers: [RiverpodPilotObserver()],
  child: MyApp(),
)

// AI can now:
// - View active providers with get_riverpod_states
// - Inject state with set_state type:riverpod
```

### With Bloc

```dart
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';

void main() {
  FlutterPilot.initialize();  // Auto-registers Bloc plugin
  runApp(MyApp());
}

// AI can now:
// - View Bloc/Cubit state with get_bloc_states
// - Inject state with set_state type:bloc
```

### With Dio

```dart
import 'package:flutterpilot_dio/flutterpilot_dio.dart';

final dio = Dio();
dio.interceptors.add(DioPilotInterceptor());

// AI can now:
// - View all HTTP requests with get_network_logs
```

### With SharedPreferences

```dart
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';

final prefs = await SharedPreferences.getInstance();
SharedPrefsPilotInspector.register(prefs);

// AI can now:
// - Read with get_shared_preferences
// - Write with set_shared_preference
// - Clear with clear_shared_preferences
```

### Custom Tools

```dart
void main() {
  FlutterPilot.initialize();
  
  FlutterPilot.registerCustomTool('clearCache', (params) async {
    await cacheManager.clear();
    return {'cleared': true};
  });
  
  runApp(MyApp());
}

// AI can now call: call_custom_tool name:clearCache
```

### Locale Runtime Switching

```dart
MaterialApp(
  locale: Locale('en'),
  supportedLocales: [Locale('en'), Locale('es')],
  localizationsDelegates: [...],
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
  home: MyApp(),
)
```

### Text Scale Override (Accessibility)

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
  home: MyApp(),
)
```

---

## Performance Considerations

- **SDK Overhead:** ~2% (lightweight service extensions only)
- **Screenshot:** ~500ms (RenderRepaintBoundary rendering)
- **Widget Tree JSON:** ~100ms for 500-widget app
- **Tap/Scroll:** <50ms
- **VM Service Call Timeout:** 10-15 seconds (configurable in server)

**Best practice:** FlutterPilot is designed for development/testing, not production. Keep it in `dev_dependencies`.

---

## Troubleshooting

### SDK Not Initializing
- Ensure `FlutterPilot.initialize()` is called **before** `runApp()`
- Check console for errors: `FlutterPilot initialized 🚀`

### Extensions Not Registering
- Verify app was started with `flutter run` (not `flutter run --release`)
- Release builds disable service extensions

### Custom Tool Not Callable
- Verify tool registered via `registerCustomTool()` before `runApp()`
- Check tool name in call matches registration name
- Use `list_custom_tools` MCP tool to verify registration

### Widget Not Found
- Ensure widget has a `key: const Key('myKey')`
- Key must be a string literal, not dynamic
- `tap_widget` also works with default Keys from `ValueKey(value)`

### Locale/Theme Not Changing
- Ensure `ValueListenableBuilder` wraps `MaterialApp`
- Check that app has `supportedLocales` defined
- Verify notifiers are listened in the correct widget tree level

---

## Source Code Structure

```
packages/flutterpilot_sdk/
├── lib/
│   ├── flutterpilot_sdk.dart          # Main entry point + extensions
│   ├── src/
│   │   ├── widget_inspector.dart      # PilotWidgetInspector
│   │   ├── navigation_tracker.dart    # NavigationTracker
│   │   ├── error_inspector.dart       # ErrorInspector
│   │   ├── interaction_manager.dart   # InteractionManager
│   │   ├── screenshot_capture.dart    # Screenshot utilities
│   │   └── vm_service_helper.dart     # VM service utilities
│   └── flutterpilot_sdk.dart
├── test/
│   ├── widget_inspector_test.dart
│   ├── navigation_tracker_test.dart
│   └── service_extensions_test.dart
└── pubspec.yaml
```

---

## Contributing

Found a bug or want to add a feature? See [CONTRIBUTING.md](../../CONTRIBUTING.md) — adding a new service extension takes ~20 minutes.

## License

MIT — see [LICENSE](../../LICENSE).
