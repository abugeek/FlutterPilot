# flutterpilot_firebase

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**firebase_auth / cloud_firestore**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Firebase state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects firebase_auth and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_firebase
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_firebase/flutterpilot_firebase.dart';

FirebasePilotInspector.register(auth: FirebaseAuth.instance, firestore: FirebaseFirestore.instance);
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_firebase_auth`** — the signed-in user as the app sees it
- **`query_firestore`** — read documents and collections with the app's own credentials and rules

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
