## Unreleased

- `flutterpilot smoke` launches the app (`-d <device>`, `--relaunch` to build
  again, `--no-launch` to use the running one), visits the current screen and
  every go_router route without parameters (or `--routes /a,/b`), checks each
  for layout, tap-target, label and contrast problems and errors, and writes
  `flutterpilot/reports/smoke-<time>/report.md` with a screenshot of each
  screen that has findings. Exit code 1 when anything was found. Each screen
  is audited twice — at the app's own text scale and at text scale 2, with the
  scale restored after every screen — and the report keeps the passes apart
  (`--no-text-scale` skips the second). Stops with
  the reason on a phone that is off or locked.
- `flutterpilot doctor` lists the phones plugged in: Android (unauthorized or
  offline, screen off or locked, battery saver, a short screen timeout) and
  iPhones (not connected, Developer Mode off, locked).
- `flutterpilot doctor` fails a config that starts the server by name
  alone (`"command": "fp_server"`) when nothing by that name is
  on the PATH, and reports that before a stale-binary warning.
- `flutterpilot doctor` and `init` read `tool/` and `bin/` as well as
  `lib/`: an app that wires FlutterPilot in a dev-only entrypoint
  (`flutter run -t tool/pilot_main.dart`) was told nothing was wired.
- `flutterpilot doctor` warns when a server binary compiled in a source
  checkout is older than its source, and checks the FlutterPilot server
  Claude Code has for the project in `~/.claude.json` (it wins over the
  project's `.mcp.json`).
- `flutterpilot stats`: how agents used FlutterPilot in this project (tools
  called, failures, timings, what followed what) from the MCP server's call
  log; takes several app folders or log files and combines them, reports the
  tools that were listed but never called and each tool's response size as
  avg/p50/p90, `--json` prints the same data as JSON, and `--clear` deletes
  the log(s).
- `flutterpilot mcp install --tools core` writes the short tool profile into
  the client's server config, for a client that counts tools across every
  server it runs.
- `flutterpilot doctor` says which tool profile a config uses (`--tools core`).
- `flutterpilot init --local` writes POSIX paths into the app's pubspec
  (`../FlutterPilot/packages/...` instead of `..\FlutterPilot\...`), so
  `path_not_posix` no longer fires and analyze stays clean.

## 0.1.0

- First release: `flutterpilot init` (adds the SDK, matching plugins and the
  macOS network entitlement), `mcp install` (MCP config for Claude Code,
  Cursor, VS Code), `dev` (runs the app so the server finds it), `doctor`
  (checks the setup and the running app).
