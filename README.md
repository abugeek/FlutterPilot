# FlutterPilot

[![CI](https://github.com/abugeek/FlutterPilot/actions/workflows/ci.yml/badge.svg)](https://github.com/abugeek/FlutterPilot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart)](https://dart.dev)

FlutterPilot connects AI coding agents to a running Flutter app through the
[Model Context Protocol (MCP)](https://modelcontextprotocol.io/). Agents can
inspect the UI and runtime, drive interactions, check behavior, and test
failure cases without relying on screen coordinates.

## Get started

Install the CLI, then run these commands from your Flutter project:

```bash
dart pub global activate fp_cli
cd path/to/your_flutter_app
fp init
fp mcp install
flutter run
```

`fp init` adds the SDK and plugins it detects, then prints the app wiring those
plugins need. Add that wiring and restart the app. `fp mcp install` configures
the MCP clients used by the project. Run `fp doctor` to check the setup.

Once connected, ask your agent to inspect the running app. It should start with
`get_app_summary` to learn the current screen and available capabilities.

## Choose an integration

| Need | Use |
|---|---|
| Set up FlutterPilot in an app | `fp init` |
| Connect an AI coding agent | `fp mcp install` |
| Check the app and MCP setup | `fp doctor` |
| Inspect UI without changing the app | Connect the server without `fp_sdk`; only inspection tools are available |
| Add integrations manually | Add `fp_sdk` and only the plugins your app uses |

FlutterPilot runs as a local stdio MCP server. It is not a hosted MCP URL.
`fp mcp install` supports Claude Code, Cursor, VS Code, Codex, Gemini CLI,
Antigravity, Zed, opencode, Junie, Kiro, and Roo Code. For a smaller tool list,
use `fp mcp install --tools core`. For clients that do not refresh tools when
the app connects, use `fp mcp install --static-tools`.

## What agents can do

- Inspect screens, widgets, navigation, accessibility semantics, and runtime
  errors.
- Tap, type, scroll, navigate, and check expected UI states.
- Record a user flow as an integration test or verify acceptance criteria.
- Compare screenshots, audit screen health, and profile performance.
- Mock HTTP responses and network conditions.
- Inspect supported app state, storage, and backend SDKs.
- Connect multiple running devices and repeat a flow across them.

The server lists tools according to the connected app's capabilities. The
[generated tool reference](TOOLS.generated.md) has the current names,
parameters, and behavior. The [agent guide](skills/flutterpilot/SKILL.md)
describes reliable workflows for using them.

Current tool inventory: 67 tools; each app receives only the tools it supports.

## Packages

The initial release contains 15 packages, published separately to pub.dev.
Install only what you need; `fp init` can detect and add matching integrations.

| Package | Adds |
|---|---|
| [`fp_sdk`](packages/fp_sdk/) | In-app runtime inspection and control |
| [`fp_cli`](packages/fp_cli/) | `fp` / `flutterpilot` setup and diagnostics commands |
| [`fp_server`](packages/fp_server/) | MCP server for connecting agents to running apps |
| [`fp_riverpod`](packages/plugins/fp_riverpod/) | Riverpod state inspection and updates |
| [`fp_bloc`](packages/plugins/fp_bloc/) | Bloc/Cubit state inspection and updates |
| [`fp_dio`](packages/plugins/fp_dio/) | Dio request inspection, response mocking, and network simulation |
| [`fp_drift`](packages/plugins/fp_drift/) | Drift database inspection |
| [`fp_sqflite`](packages/plugins/fp_sqflite/) | sqflite database inspection |
| [`fp_hive`](packages/plugins/fp_hive/) | Hive and Hive CE storage inspection |
| [`fp_shared_preferences`](packages/plugins/fp_shared_preferences/) | SharedPreferences inspection |
| [`fp_gorouter`](packages/plugins/fp_gorouter/) | GoRouter route inspection and navigation |
| [`fp_connectivity`](packages/plugins/fp_connectivity/) | Connectivity state and history |
| [`fp_firebase`](packages/plugins/fp_firebase/) | Firebase Auth and Firestore inspection |
| [`fp_supabase`](packages/plugins/fp_supabase/) | Supabase auth and data inspection |
| [`fp_secure_storage`](packages/plugins/fp_secure_storage/) | Secure storage inspection with redaction |

## Development and safety

FlutterPilot is intended for development and testing, not production builds.
The SDK is inactive in release mode. The server connects to the Dart VM service,
which should only be exposed on trusted networks; remote connections are
blocked by default. Keep destructive operations disabled unless a test needs
them, and use non-production app data when enabling them.

## Documentation

- [Complete tool reference](TOOLS.generated.md)
- [Agent workflows](skills/flutterpilot/SKILL.md)
- [CLI guide](packages/fp_cli/README.md)
- [SDK guide](packages/fp_sdk/README.md)
- [MCP server guide](packages/fp_server/README.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Example app](examples/flutter_pilot_example/)
- [Release process](RELEASING.md)

## License

MIT. See [LICENSE](LICENSE).
