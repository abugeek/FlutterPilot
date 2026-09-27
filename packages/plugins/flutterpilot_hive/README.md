# FlutterPilot Hive Plugin

Expose Hive / Hive CE box contents to FlutterPilot for AI inspection.

## Setup

```yaml
dependencies:
  flutterpilot_hive:
    path: packages/plugins/flutterpilot_hive
```

```dart
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

// After opening a box (works with hive and hive_ce):
final settings = await Hive.openBox('settings');
HivePilotInspector.registerBox(settings);
```

## What It Exposes

- **`get_hive_contents`** — Dumps all registered box contents as JSON
