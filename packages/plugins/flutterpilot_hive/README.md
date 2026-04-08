# FlutterPilot Hive Plugin

Expose Hive box contents to FlutterPilot for AI inspection.

## Setup

```yaml
dependencies:
  flutterpilot_hive:
    path: packages/plugins/flutterpilot_hive
```

```dart
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

// After opening a Hive box:
final box = await Hive.openBox('settings');
HivePilotInspector.registerBox('settings');
```

## What It Exposes

- **`get_hive_contents`** — Dumps all registered box contents as JSON
