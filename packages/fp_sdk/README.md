# fp_sdk

A Flutter SDK for AI agents to inspect, drive, test, and debug a running app
during development. The MCP server uses it to inspect widgets, read errors,
drive the UI, and verify behavior.

## Install

Add the SDK as a development dependency:

```bash
flutter pub add --dev fp_sdk
```

Or use `fp init` from the Flutter project. It also detects supported
integrations and prints the wiring each plugin needs.

## Initialize

Call `FlutterPilot.initialize()` before `runApp`:

```dart
import 'package:fp_sdk/fp_sdk.dart';

void main() {
  FlutterPilot.initialize();
  runApp(const MyApp());
}
```

Then connect an MCP server with `fp mcp install`. The server finds apps started
with `flutter run` or an IDE. Run `fp doctor` to check the setup.

## Capabilities

The SDK provides the runtime bridge and core app capabilities, including
widget and semantics inspection, screenshots, navigation and error tracking,
UI interactions, test recording, network simulation, and screen health
checks. Additional integrations are separate packages:

| Package | Integration |
|---|---|
| `fp_riverpod` | Riverpod |
| `fp_bloc` | Bloc and Cubit |
| `fp_dio` | Dio |
| `fp_drift` | Drift |
| `fp_sqflite` | sqflite |
| `fp_hive` | Hive and Hive CE |
| `fp_shared_preferences` | SharedPreferences |
| `fp_gorouter` | GoRouter |
| `fp_connectivity` | connectivity_plus |
| `fp_firebase` | Firebase Auth and Cloud Firestore |
| `fp_supabase` | Supabase |
| `fp_secure_storage` | flutter_secure_storage |

Plugins register their capabilities with the SDK; follow each plugin's README
for its setup. The server exposes only tools available to the connected app.
See the [generated tool reference](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md)
for the current tool list.

## Notes

Use the SDK in development and test builds, not production. FlutterPilot tools
depend on the Dart VM service and are unavailable in release builds.

For the full setup and contribution guides, see the
[FlutterPilot repository](https://github.com/abugeek/FlutterPilot).

## License

MIT. See the [license](https://github.com/abugeek/FlutterPilot/blob/main/LICENSE).
