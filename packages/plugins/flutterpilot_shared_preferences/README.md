# FlutterPilot SharedPreferences Plugin

A [FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin that exposes
[SharedPreferences](https://pub.dev/packages/shared_preferences) data to AI
agents at runtime via the MCP protocol.

## Setup

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutterpilot_shared_preferences: ^0.1.0
```

Register after initializing SharedPreferences:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterPilot.initialize();
  final prefs = await SharedPreferences.getInstance();
  SharedPrefsPilotInspector.register(prefs);
  runApp(const MyApp());
}
```

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `get_shared_preferences` | Returns all keys and values |
| `set_shared_preference` | Writes a key with a typed value |
| `clear_shared_preferences` | Removes one key or clears all |

### `set_shared_preference` Types

Pass `type` as one of: `string` (default), `int`, `double`, `bool`, `stringList`.

```json
{
  "key": "user_theme",
  "value": "dark",
  "type": "string"
}
```

## License

MIT — see [LICENSE](../../LICENSE).
