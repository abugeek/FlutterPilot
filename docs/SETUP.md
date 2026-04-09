# FlutterPilot Installation & Setup Guide

Complete platform-specific setup guide for using FlutterPilot in your Flutter project.

## Table of Contents
- [Prerequisites](#prerequisites)
- [iOS Setup](#ios-setup)
- [Android Setup](#android-setup)
- [Web Setup](#web-setup)
- [macOS Setup](#macos-setup)
- [Windows Setup](#windows-setup)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:
- **Flutter SDK** ≥ 3.0.0 (check: `flutter --version`)
- **Dart SDK** ≥ 3.11.0 (included with Flutter)
- An IDE: VS Code, Android Studio, or Xcode
- A Flutter project (or create: `flutter create my_app`)

Verify setup:
```bash
flutter doctor
```

---

## Universal Setup (All Platforms)

### Step 1: Add FlutterPilot SDK

```bash
cd your_flutter_project
flutter pub add --dev flutterpilot_sdk
```

This adds to `pubspec.yaml`:
```yaml
dev_dependencies:
  flutterpilot_sdk: ^0.1.0
```

### Step 2: Initialize in Your App

In `lib/main.dart`, add **before** `runApp()`:

```dart
import 'package:flutter/material.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  // IMPORTANT: Initialize before runApp()
  FlutterPilot.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const MyHomePage(),
    );
  }
}
```

### Step 3: Verify SDK Loads

Run your app and watch the debug console for:
```
FlutterPilot initialized 🚀
```

If you see this, SDK is working. Continue to platform-specific setup.

---

## iOS Setup

### Debugger Connection

iOS requires special handling for the VM service URI.

#### Using Xcode

1. **Run the app**:
   ```bash
   flutter run -d ios
   ```

2. **Find VM Service URI** in console output:
   ```
   The Dart VM service is listening on http://127.0.0.1:54321/xxxxx=
   ```

3. **Start FlutterPilot Server**:
   ```bash
   dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
     --uri "http://127.0.0.1:54321/xxxxx="
   ```

#### Using VS Code

1. **Create `.vscode/launch.json`**:
   ```json
   {
     "version": "0.2.0",
     "configurations": [
       {
         "name": "Flutter",
         "type": "dart",
         "request": "launch",
         "program": "lib/main.dart",
         "deviceId": "iphone",
         "flutterMode": "debug"
       }
     ]
   }
   ```

2. **Press F5 to run**, then copy VM Service URI from debug console.

### Network Access

If running on a physical device:
- iOS may block localhost VM service access
- Use USB connection: `flutter run -d ios --observatory-port 12345`
- This forwards VM service to your machine

---

## Android Setup

### Emulator (Recommended for Development)

1. **Start Android Emulator**:
   ```bash
   emulator -avd Pixel_5_API_31
   ```

2. **Run the app**:
   ```bash
   flutter run -d emulator-5554
   ```

3. **Copy VM Service URI** from console

4. **Start server**:
   ```bash
   dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
     --uri "<VM-SERVICE-URI>"
   ```

### Physical Device (USB)

1. **Enable USB debugging**: Settings → Developer Options → USB Debugging

2. **Connect device**:
   ```bash
   adb devices  # Verify device is listed
   ```

3. **Run app**:
   ```bash
   flutter run -d <device-id>
   ```

4. **Forward VM service port** (if needed):
   ```bash
   adb forward tcp:12345 tcp:12345
   flutter run --observatory-port 12345
   ```

---

## Web Setup

### Important Limitations

Web support is **limited**:
- ❌ Cannot access VM service (uses JavaScript VM)
- ❌ Widget tree unavailable
- ❌ State inspection limited
- ✅ Screenshot via canvas snapshot
- ✅ Basic navigation tracking

For **web testing**, use integration_test package instead.

If you still want FlutterPilot on web:

```bash
flutter run -d chrome
```

The SDK initializes but will log warnings for unavailable features.

---

## macOS Setup

### Desktop Development

macOS requires Xcode command-line tools:

```bash
xcode-select --install
```

Then run normally:

```bash
flutter run -d macos
```

VM Service URI appears in console; use like iOS.

### Specific Issue: ARM64 Macs

If you get `Cannot find kernel module`:

```bash
flutter clean
flutter pub get
flutter run -d macos
```

---

## Windows Setup

### Prerequisites

- Visual Studio 2019+ (Community free version OK)
- Flutter Windows SDK
- Windows 10+

### Running

```bash
flutter run -d windows
```

VM Service URI appears in console output.

### Firewall

Windows Defender may block localhost port. If server can't connect:
1. Open Windows Defender Firewall → Advanced Settings
2. Inbound Rules → New Rule → Port → TCP → 127.0.0.1
3. Or temporarily disable firewall for testing

---

## Plugin Setup (Optional)

Enhance FlutterPilot with state manager plugins:

### Bloc Plugin

```bash
flutter pub add --dev flutterpilot_bloc flutter_bloc
```

In `main.dart`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';

void main() {
  FlutterPilot.initialize();
  Bloc.observer = BlocPilotObserver();  // Add this
  runApp(MyApp());
}
```

### Riverpod Plugin

```bash
flutter pub add --dev flutterpilot_riverpod riverpod flutter_riverpod
```

In `main.dart`:
```dart
import 'package:riverpod/riverpod.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';

void main() {
  FlutterPilot.initialize();
  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],  // Add this
      child: MyApp(),
    ),
  );
}
```

### Dio Plugin (HTTP Mocking)

```bash
flutter pub add --dev flutterpilot_dio dio
```

In `main.dart`:
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

### Other Plugins

- **flutterpilot_shared_preferences** — SharedPreferences spy
- **flutterpilot_drift** — Database SQL queries
- **flutterpilot_hive** — Hive box inspection

Setup follows same pattern: `pub add`, then register in `main()`.

---

## Troubleshooting

### "FlutterPilot: SDK not initialized"

**Problem**: Plugin logs warning but doesn't register.

**Solution**: Ensure `FlutterPilot.initialize()` is called **before** `runApp()`:

```dart
void main() {
  FlutterPilot.initialize();  // Must be first!
  Bloc.observer = BlocPilotObserver();  // After FlutterPilot
  runApp(MyApp());
}
```

### "Extension not found in any isolate"

**Problem**: Server calls an extension but plugin is not loaded.

**Solution**: Check plugin is registered. Example for Bloc:

```dart
// ❌ Wrong: observer set after or not at all
void main() {
  FlutterPilot.initialize();
  runApp(MyApp());  // Missing Bloc.observer = ...
}

// ✅ Correct
void main() {
  FlutterPilot.initialize();
  Bloc.observer = BlocPilotObserver();  // Add this
  runApp(MyApp());
}
```

Verify with server tool: `get_capabilities` will show which plugins loaded.

### "Cannot find VM Service URI"

**Problem**: `flutter run` output doesn't show URI.

**Solution**: Ensure you're in **debug mode**:

```bash
# ❌ Won't show VM service
flutter run --release

# ✅ Correct
flutter run
flutter run --debug
```

Copy the URI that looks like:
```
The Dart VM service is listening on http://127.0.0.1:54321/xxxxx=
```

### "Server connection refused"

**Problem**: Server starts but can't reach app.

**Solution**: Verify URI is correct. Test with curl:

```bash
curl "http://127.0.0.1:54321/xxxxx=" -v
```

If refused:
- Ensure app is still running
- Ensure URI is current (can expire on hot reload)
- Restart app if needed

### "Hot reload breaks state inspection"

**Problem**: After hot reload, state tools return empty.

**Solution**: Plugin state is reset on hot reload. This is **expected**:
- State maps are cleared to prevent memory leaks
- Your app state persists in widgets
- Re-run state-changing actions, then inspect

If this is problematic, run with `--no-fast-start`:
```bash
flutter run --no-fast-start
```

### Platform-Specific Issues

#### iOS: "Port already in use"

```bash
# Kill process on port
lsof -ti:54321 | xargs kill -9

# Or use different port
flutter run --observatory-port 12345
```

#### Android: "Device offline"

```bash
adb devices  # Check device listed
adb reconnect  # Reconnect
flutter run
```

#### Web: "No VM service available"

Web uses JavaScript VM, not Dart VM. State inspection won't work. This is a fundamental limitation, not a bug.

### "Slow performance after SDK init"

FlutterPilot adds < 2% overhead (measured). If app is sluggish:

1. Check if debugger is attached (can slow Flutter)
2. Ensure app is built in release mode for benchmarks
3. Close other apps consuming RAM
4. Try smaller `maxDepth` in `get_widget_tree` calls

---

## Next Steps

After setup:
1. **Verify tools work**: Run `get_app_summary` → should show current route
2. **Check plugins**: Run `get_capabilities` → shows loaded plugins
3. **Test AI integration**: Try with Claude or Cursor
4. **Read [TOOLS.md](../TOOLS.md)** → All 83 tools reference

---

## Getting Help

- **GitHub Issues**: https://github.com/abugeek/FlutterPilot/issues
- **Discord**: Join our community
- **Stack Overflow**: Tag with `#flutterpilot`

Common issues are documented in [Troubleshooting](#troubleshooting) above.
