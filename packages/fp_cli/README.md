# fp_cli

The FlutterPilot command-line interface sets up Flutter apps for AI-assisted
inspection and testing, installs the local MCP server in supported clients,
and checks the app's runtime setup.

## Install

```bash
dart pub global activate fp_cli
```

This adds both `fp` and `flutterpilot` commands. Dart's global executable
directory must be on your `PATH`.

## Set up a Flutter project

Run these commands from the app directory:

```bash
fp init
fp mcp install
flutter run
```

`fp init` detects supported app dependencies, adds `fp_sdk` and matching
plugins, adds `FlutterPilot.initialize()` to `main()` when it can, and runs
`flutter pub get`. It prints any plugin-specific wiring that still needs to
be added. After publication, the default source is pub.dev; before then, it
uses the GitHub repository. Use `fp doctor` to check the setup.

`fp mcp install` configures the project's local stdio MCP server for clients
such as Claude Code, Cursor, VS Code, Codex, Gemini CLI, Antigravity, Zed,
opencode, Junie, Kiro, and Roo Code. It preserves other MCP server entries.

Use the smaller tool profile with `fp mcp install --tools core`. For clients
that do not refresh tools when the app connects, add `--static-tools`.

## Other commands

- `fp dev` runs `flutter run` and writes the VM service URI for discovery. It
  does not start the MCP server.
- `fp doctor` checks the Flutter/Dart setup, SDK and plugin wiring, MCP
  configuration, and connected devices.
- `fp smoke` checks app routes for layout, accessibility, and runtime errors.
- `fp stats` summarizes local FlutterPilot tool-call logs.
- `fp migrate` migrates legacy `flutterpilot_*` packages and configuration.

Run `fp --help` or `fp <command> --help` for all commands and options.

## License

MIT. See the [license](https://github.com/abugeek/FlutterPilot/blob/main/LICENSE).
