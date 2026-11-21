# fp_server

`fp_server` is FlutterPilot's local, stdio-based MCP server. It connects AI
coding agents to a running Flutter app through the Dart VM service.

## Recommended setup

Use the CLI from your Flutter project:

```bash
dart pub global activate fp_cli
fp init
fp mcp install
flutter run
```

`fp init` adds `fp_sdk` and any supported plugins it detects. Add the wiring it
prints, then restart the app. Without `fp_sdk`, the server can inspect an app
but cannot drive it.

The server is launched by the MCP client using the project configuration.
`fp mcp install` can configure Claude Code, Cursor, VS Code, Codex, Gemini CLI,
Antigravity, Zed, opencode, Junie, Kiro, and Roo Code.

## Run from a checkout

For server development, start a Flutter app and run:

```bash
cd packages/fp_server
dart run bin/fp_server.dart --project-root /path/to/your_flutter_app
```

The server uses the current project directory if `--project-root` is omitted.
You can pass `--uri <vm-service-uri>` to connect to a specific running app.
Run `dart run bin/fp_server.dart --help` for server options.

## Tools and safety

Current tool inventory: 67 tools; the server lists only those supported by the
connected app's SDK, plugins, and platform. The
[generated reference](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md)
documents their names and parameters.

VM-service connections to remote hosts are blocked by default. Only enable
remote access on a trusted network. Tools that can change app data or call
external services require `--allow-destructive`; leave it disabled unless
your development or test workflow needs those operations.

## Requirements

- Dart SDK 3.11 or later.
- A running Flutter app. Add `fp_sdk` for UI interaction and app capabilities.
- An MCP client that can launch a local stdio server.

See the [FlutterPilot repository](https://github.com/abugeek/FlutterPilot)
for the CLI, SDK, plugins, setup guide, and example app.

## License

MIT. See the [license](https://github.com/abugeek/FlutterPilot/blob/main/LICENSE).
