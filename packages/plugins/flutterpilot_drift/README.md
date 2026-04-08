# FlutterPilot Drift Plugin

Expose Drift database tables and run SQL queries via FlutterPilot.

## Setup

```yaml
dependencies:
  flutterpilot_drift:
    path: packages/plugins/flutterpilot_drift
```

```dart
import 'package:flutterpilot_drift/flutterpilot_drift.dart';

// After opening your Drift database:
DriftPilotInspector.registerDatabase('mydb', database);
```

## What It Exposes

- **`list_drift_tables`** — Lists all table names in the registered database
- **`query_drift_db`** — Run read-only SQL queries (SELECT, EXPLAIN, PRAGMA)

Write queries require the server to be started with `--allow-destructive`.
