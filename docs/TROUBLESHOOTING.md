# FlutterPilot Troubleshooting Guide

Comprehensive troubleshooting for common FlutterPilot issues.

## Table of Contents
- [Installation Issues](#installation-issues)
- [Connection Issues](#connection-issues)
- [Tool Execution Issues](#tool-execution-issues)
- [Performance Issues](#performance-issues)
- [Plugin Issues](#plugin-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [Advanced Debugging](#advanced-debugging)
- [FAQ](#faq)

---

## Installation Issues

### "Could not find package flutterpilot_sdk"

**Problem**: `flutter pub get` fails with package not found.

**Causes**:
- Package not published to pub.dev yet
- Internet connection issue
- Pubspec.yaml typo

**Solutions**:

1. **Check internet**: Verify you have internet connectivity
   ```bash
   ping pub.dev
   ```

2. **Use local path** (during development):
   ```yaml
   dev_dependencies:
     flutterpilot_sdk:
       path: ../path/to/flutterpilot_sdk
   ```

3. **Check pubspec.yaml syntax**:
   ```bash
   flutter pub get --offline  # See what's wrong
   ```

4. **Clear pub cache**:
   ```bash
   flutter pub cache repair
   flutter pub get
   ```

---

### "Failed to compile flutterpilot_sdk"

**Problem**: `pub get` succeeds but `flutter build` fails.

**Causes**:
- SDK requires newer Flutter version
- Missing platform-specific dependencies (iOS CocoaPods, Android gradle)
- Dart SDK version mismatch

**Solutions**:

```bash
# Check Flutter version
flutter --version

# SDK requires: Flutter >= 3.0.0, Dart >= 3.11.0
# Update if needed:
flutter upgrade

# Try pub get again
flutter pub get

# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

---

### "Package has lower priority than..." or dependency conflicts

**Problem**: Conflicting package versions.

**Example**:
```
flutterpilot_bloc ^0.1.0 requires flutter_bloc ^8.0.0
but flutter_bloc ^7.0.0 is already used
```

**Solutions**:

1. **Update conflicting package**:
   ```bash
   flutter pub add flutter_bloc:^8.0.0
   ```

2. **Or downgrade FlutterPilot plugin**:
   ```bash
   flutter pub add flutterpilot_bloc:^0.0.5
   ```

3. **Check current versions**:
   ```bash
   flutter pub deps
   ```

---

## Connection Issues

### "Cannot connect to VM Service"

**Problem**: Server starts but can't reach the app.

**Causes**:
- App not running
- Wrong VM Service URI
- Firewall blocking port
- App exited unexpectedly

**Diagnostic Steps**:

1. **Verify app is running**:
   ```bash
   # In separate terminal
   adb devices  # Android
   # OR check Xcode console output for iOS
   ```

2. **Verify VM Service URI is correct**:
   ```bash
   # Copy from `flutter run` output:
   # "The Dart VM service is listening on http://127.0.0.1:54321/xxxxx="
   
   # Test with curl
   curl "http://127.0.0.1:54321/xxxxx=" -v
   # Should return JSON response
   ```

3. **Check if port is in use**:
   ```bash
   lsof -i :54321  # macOS/Linux
   netstat -ano | findstr :54321  # Windows
   ```

4. **Try different port**:
   ```bash
   flutter run --observatory-port 12345
   # Then use: http://127.0.0.1:12345/xxxxx=
   ```

### Solution:

```bash
# Restart app with fresh URI
flutter run  # Kill previous session first (Ctrl+C)

# Copy new URI from output
# Start server with new URI
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri "<NEW-URI>"
```

---

### "Extension not found in any isolate"

**Problem**: Server calls extension but gets "not found" error.

**Causes**:
- Plugin not initialized (e.g., `Bloc.observer = BlocPilotObserver()` missing)
- FlutterPilot.initialize() not called first
- App crashed
- Wrong isolate targeted

**Check Plugin Registration**:

```dart
// ❌ WRONG
void main() {
  FlutterPilot.initialize();
  runApp(MyApp());  // Missing Bloc.observer!
}

// ✅ CORRECT
void main() {
  FlutterPilot.initialize();
  Bloc.observer = BlocPilotObserver();  // Must add this
  runApp(MyApp());
}
```

**Verify with get_capabilities**:

```bash
# Server has a diagnostic tool:
# "get_capabilities" shows which plugins loaded
# If you don't see your plugin, init is wrong
```

**Check Initialization Order**:

```dart
void main() {
  // 1. Initialize FlutterPilot FIRST
  FlutterPilot.initialize();
  
  // 2. Then register observers
  Bloc.observer = BlocPilotObserver();
  
  // 3. Then run app
  runApp(MyApp());
}
```

---

### "Timeout waiting for VM service response"

**Problem**: Server calls extension but times out.

**Causes**:
- App is hanging/frozen
- Extension handler is slow (>15 seconds)
- Network latency (slow WiFi)
- Too many isolates (rare)

**Solutions**:

```bash
# Check if app is responsive
# Try capturing a screenshot (simple operation)
# If screenshot times out, app is likely frozen

# Option 1: Restart app
flutter run  # Kill + restart

# Option 2: If app is slow, use longer timeout
# (requires source modification in server)

# Option 3: Check for infinite loops in app code
# Common causes:
# - Bloc.add() in build()
# - Widget.didChangeDependencies() with setState()
# - RenderObject laying out in paint()
```

---

## Tool Execution Issues

### "Tool not found: get_widget_tree"

**Problem**: Server responds with "Tool not registered".

**Causes**:
- Typo in tool name
- Tool requires plugin not loaded
- Using old tool name (deprecated)

**Solutions**:

1. **Check tool name spelling**:
   ```bash
   # Correct: get_widget_tree
   # Wrong: getWidgetTree, get_widget_tree_widget, etc.
   ```

2. **List available tools**:
   ```bash
   # Server tool: "list_custom_tools" shows all registered tools
   ```

3. **Check plugin requirements**:
   ```bash
   # Some tools need plugins:
   # get_bloc_state → requires flutterpilot_bloc
   # get_riverpod_state → requires flutterpilot_riverpod
   # get_network_logs → requires flutterpilot_dio
   ```

---

### "Tool returned error: validation failed"

**Problem**: Tool executes but returns validation error.

**Example**:
```json
{
  "error": "[validation] Expected key 'submitButton' but widget not found"
}
```

**Causes**:
- Widget key doesn't exist
- Typo in key name
- Widget not mounted (off-screen, hidden)
- Key type mismatch (ValueKey vs ObjectKey)

**Solutions**:

```dart
// First, verify widget exists:
// 1. Capture screenshot to see UI
// 2. Call get_widget_tree to inspect hierarchy
// 3. Look for your widget and its key

// Make sure key matches exactly:
FloatingActionButton(
  key: const ValueKey('submitBtn'),  // ← Exactly 'submitBtn'
  onPressed: () {},
)

// If widget is dynamically created, verify:
// - It's actually built (not hidden in if statement)
// - It's in the current route/page
// - No typos in key name
```

---

### "Tool returned: {error: extension method took too long}"

**Problem**: Tool execution exceeded 15-second timeout.

**Causes**:
- Widget tree is extremely deep (10,000+ nodes)
- Device is slow
- Another tool is running simultaneously
- Extension handler has slow operation

**Solutions**:

1. **Limit widget tree depth**:
   ```bash
   # Use maxDepth parameter (if available):
   get_widget_tree maxDepth=20  # Only first 20 levels
   ```

2. **Simplify widget tree** in app:
   ```dart
   // ❌ Bad: deeply nested
   Scaffold(
     body: Column(
       children: [
         Row(children: [...]),
         Column(children: [
           Row(children: [
             Column(children: [...])  // 4 levels deep
           ])
         ])
       ],
     ),
   )

   // ✅ Better: extract widgets
   Scaffold(
     body: Column(
       children: [
         MyHeaderRow(),  // Extract
         MyDetailColumn(),  // Extract
       ],
     ),
   )
   ```

3. **Restart app** to clear old state

---

### "Image/screenshot is blank or corrupted"

**Problem**: `capture_screenshot` returns unreadable data.

**Causes**:
- App is still initializing (splash screen)
- Widget rendering failed
- GPU/rendering issue
- Data corruption in transit

**Solutions**:

```bash
# 1. Wait for app to fully load
# 2. Trigger some UI (navigate, scroll) to ensure rendering
# 3. Try screenshot again

# 3. If still corrupted, check:
# - Console for rendering errors
# - Device has enough GPU memory
# - No extreme widget transformations
```

---

## Performance Issues

### "App is very slow after initializing FlutterPilot"

**Problem**: Frame rate drops, jank visible.

**Causes**:
- Debugger is attached (common, expected)
- FlutterPilot overhead is real (~2% on normal apps)
- Plugin is tracking too much state
- Buffer size is too large

**Solutions**:

```bash
# 1. Check if debugger is attached:
flutter run  # With debugger: "Debugger and DevTools are available..."

# 2. If debugger is attached, that's the main cause
# Release mode won't have this:
flutter run --release  # But then no hot reload

# 3. For production perf test:
flutter build apk --release
# Then measure performance

# 4. If truly slow, check plugins are minimal:
# Only load plugins you actually use
```

---

### "Memory usage grows over time"

**Problem**: App RAM increases every minute.

**Causes**:
- Screenshot baseline cache unbounded (fixed in round 5)
- Plugin state maps growing without limit (fixed in round 5)
- Buffers not being trimmed
- Event listeners not unregistered

**Check Plugin State**:

```bash
# Server tool: get_capabilities
# Shows buffer usage and plugin state size
# If any is huge (>100MB), that's the leak
```

**Solutions**:

```dart
// Ensure plugins are initializing correctly:
void main() {
  FlutterPilot.initialize();
  
  // Add plugins AFTER FlutterPilot.initialize()
  Bloc.observer = BlocPilotObserver();  // ← After init
  
  runApp(MyApp());
}

// If memory still grows:
// 1. Check app code for event listener leaks
// 2. Verify dispose() methods are called
// 3. Profile with Android Studio Profiler / Xcode Instruments
```

---

### "Hot reload is slow"

**Problem**: After code change, `flutter run` takes >5 seconds to reload.

**Causes**:
- Large widget tree (not FlutterPilot's fault)
- Plugins resetting state (expected)
- VM service overloaded

**Expected Behavior**:

Hot reload with FlutterPilot plugins:
1. Code recompiled (~1-2 seconds)
2. Plugins reset state (~0.5 seconds)
3. Widget tree rebuilt (~1-3 seconds depending on size)

**Normal total**: 2-6 seconds. If >10 seconds, check app size.

---

## Plugin Issues

### "Plugin X says 'SDK not initialized'"

**Problem**: Warning log appears but plugin doesn't work.

**Cause**: `FlutterPilot.initialize()` called after plugin observer registered.

**Wrong**:
```dart
void main() {
  Bloc.observer = BlocPilotObserver();  // Too early!
  FlutterPilot.initialize();
  runApp(MyApp());
}
```

**Correct**:
```dart
void main() {
  FlutterPilot.initialize();  // First
  Bloc.observer = BlocPilotObserver();  // Second
  runApp(MyApp());
}
```

---

### "Bloc state is empty / not tracked"

**Problem**: `get_bloc_state` returns no blocs.

**Causes**:
- Bloc.observer not set
- Bloc not used yet (empty map)
- Bloc.observer set in wrong place

**Debug Steps**:

```dart
// Verify observer is set:
void main() {
  FlutterPilot.initialize();
  
  debugPrint('Observer before: ${Bloc.observer}');
  Bloc.observer = BlocPilotObserver();
  debugPrint('Observer after: ${Bloc.observer}');  // Should not be null
  
  runApp(MyApp());
}

// Create a test bloc to verify tracking:
class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<IncrementEvent>((event, emit) => emit(state + 1));
  }
}

// In widget:
BlocProvider(
  create: (_) => CounterBloc(),
  child: MyWidget(),
)
```

---

### "Multiple Bloc instances overwrite state"

**Problem**: Two instances of same Bloc type show only one in `get_bloc_state`.

**Cause**: Bloc plugin keys by type name only. Two instances collide.

**Known Issue** (tracked in GitHub #XX):
```dart
// ❌ Both instances lose separately
final bloc1 = MyBloc();
final bloc2 = MyBloc();  // ← bloc2 overwrites bloc1
```

**Workaround** (current limitation):
- Use different Bloc types
- Or wait for fix in next release

**Monitoring**:
- Follow issue #XX for progress
- Use `get_widget_tree` as alternative to inspect state

---

### "Riverpod state not syncing"

**Problem**: `get_riverpod_state` doesn't show current values.

**Cause**: ProviderScope observer not set, or multiple ProviderScopes.

**Setup (Important)**:

```dart
void main() {
  FlutterPilot.initialize();
  
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],  // ← Required
      child: MyApp(),
    ),
  );
}
```

**Multi-Container Issue**:

```dart
// ❌ Multiple ProviderScopes cause sync issues
Scaffold(
  body: ProviderScope(  // Scope 1
    child: PageOne(),
  ),
  drawer: ProviderScope(  // Scope 2 ← Collides with Scope 1
    child: PageTwo(),
  ),
)

// ✅ Single root ProviderScope
void main() {
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: MyApp(),  // All pages inside single scope
    ),
  );
}
```

---

### "HTTP mocks from DioPilot not working"

**Problem**: `add_http_mock` succeeds but requests still hit real endpoints.

**Cause**: Dio instance not using DioPilotInterceptor.

**Setup**:

```dart
import 'package:flutterpilot_dio/flutterpilot_dio.dart';

// At app root:
final dio = Dio();

void main() {
  FlutterPilot.initialize();
  
  // ← Critical: add interceptor
  dio.interceptors.add(DioPilotInterceptor());
  
  // Then use this dio instance everywhere
  runApp(MyApp());
}

// In HTTP calls:
try {
  final response = await dio.get('https://api.example.com/users');
  // If mock was added, returns mock response
} catch (e) {
  // If no mock, makes real request
}
```

**Verify Interceptor**:
```bash
# Use get_network_logs tool
# Should see your mock interceptor in the request log
```

---

### "SharedPreferences returns sensitive data"

**Problem**: API keys visible in `get_shared_preferences`.

**Important**: This is expected behavior. SharedPreferences is **not encrypted**.

**Recommendation**:
```dart
// Store sensitive data securely:
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const storage = FlutterSecureStorage();
await storage.write(key: 'api_key', value: '...');

// FlutterPilot cannot access encrypted storage (by design)
// This is correct security behavior
```

---

## Platform-Specific Issues

### iOS: "Xcode build failed"

**Problem**: `flutter run -d ios` fails with build error.

**Common Causes**:

1. **CocoaPods cache**:
   ```bash
   cd ios
   rm -rf Pods
   rm Podfile.lock
   cd ..
   flutter pub get
   flutter run -d ios
   ```

2. **Xcode version mismatch**:
   ```bash
   xcode-select --install
   xcode-select -p  # Should show: /Applications/Xcode.app/...
   ```

3. **Min iOS version too low**:
   ```bash
   # Edit ios/Podfile:
   # platform :ios, '11.0'  ← Should be >= 11.0
   ```

---

### Android: "Gradle build failed"

**Problem**: `flutter run -d android` fails.

**Solutions**:

```bash
# 1. Clean
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Try building again
flutter run -d android

# 4. If still fails, check gradle cache
rm -rf ~/.gradle/caches
flutter pub get
flutter run -d android
```

---

### Android: "Target SDK version mismatch"

**Problem**: Build fails with "targetSdk 33 but app requires 34".

**Fix** (`android/app/build.gradle`):
```gradle
android {
  compileSdk = 34  // Update to latest
  
  defaultConfig {
    targetSdk = 34  // Update to match
    minSdk = 21  // FlutterPilot supports 21+
  }
}
```

---

### Windows: "Firewall blocks localhost"

**Problem**: Server can't connect, says port in use.

**Fix**:
```powershell
# Open Windows Defender Firewall
# Inbound Rules → New Rule
# Allow TCP port 127.0.0.1:54321

# Or temporarily disable:
netsh advfirewall set allprofiles state off  # Disable
# ... test ...
netsh advfirewall set allprofiles state on   # Enable
```

---

### Web: "VM Service not available"

**Problem**: FlutterPilot warns "Web VM Service unavailable".

**Expected**: Web uses JavaScript VM, not Dart VM. Some tools won't work:
- ❌ Widget tree inspection
- ❌ State manager plugins (Bloc, Riverpod)
- ✅ Screenshot (via canvas)
- ✅ Console logs
- ✅ Navigator state

**This is not a bug**. Use integration_test for web testing instead.

---

## Advanced Debugging

### Enable Debug Logging

```dart
// In main.dart or FlutterPilot SDK:
void main() {
  // Set debug flag (if available)
  debugPrintBeginLine = true;
  debugPrintEndLine = true;
  
  FlutterPilot.initialize();
  runApp(MyApp());
}
```

### Check VM Service Directly

```bash
# Using websocat (or similar):
# 1. Get VM Service URI
# 2. Connect to WebSocket:

curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  "http://127.0.0.1:54321/xxxxx="

# Should respond with WebSocket upgrade
```

### Inspect Server Logs

```bash
# Start server with verbose logging (if available):
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri "<URI>" \
  --verbose
```

### Profile with DevTools

```bash
# While running flutter run:
flutter devtools  # Opens http://localhost:9100

# Check:
# - Memory tab: Look for leaks
# - CPU tab: Check for jank
# - Network tab: View HTTP requests
```

---

## FAQ

### Q: Will FlutterPilot slow down my production app?

**A**: No. FlutterPilot is dev-only (`dev_dependencies`). It won't be included in production builds.

### Q: Can I use FlutterPilot with my iOS app on macOS?

**A**: Yes, but requires running iOS simulator or physical device. Direct macOS desktop apps use different architecture.

### Q: Does FlutterPilot work with Flutter Web?

**A**: Partially. Some tools work (screenshot), others don't (state inspection). See [Web Setup](#web-setup).

### Q: Can I use FlutterPilot in a production app for telemetry?

**A**: Not recommended. It's designed for development. For production, use standard analytics instead.

### Q: How do I reset plugin state without restarting?

**A**: Hot reload will reset all plugin state. Use `flutter run` and hot reload (R) to trigger.

### Q: Can I mock multiple endpoints at once?

**A**: Yes, call `add_http_mock` multiple times, once per endpoint.

### Q: What if my widget key is null?

**A**: Keys are optional in Flutter. Widgets without keys can't be targeted by FlutterPilot UI automation tools. Add a key to target specific widgets.

### Q: Will FlutterPilot work with custom State Managers I wrote?

**A**: Only if you create a FlutterPilot plugin for it. See [PLUGINS.md](../docs/PLUGINS.md) for guide.

---

## Still Having Issues?

1. **Check [docs/](../docs/)** for more detailed guides
2. **Search [GitHub Issues](https://github.com/abugeek/FlutterPilot/issues)**
3. **Open a new issue** with:
   - Error message (exact)
   - Minimal reproducible example
   - Platform (iOS/Android/Web/macOS/Windows)
   - FlutterPilot version
   - Flutter/Dart version (`flutter --version`)
