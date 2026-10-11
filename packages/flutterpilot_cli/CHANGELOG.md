## Unreleased

- `flutterpilot doctor` warns when a server binary compiled in a source
  checkout is older than its source, and checks the FlutterPilot server
  Claude Code has for the project in `~/.claude.json` (it wins over the
  project's `.mcp.json`).
- `flutterpilot stats`: how agents used FlutterPilot in this project (tools
  called, failures, timings, what followed what) from the MCP server's call
  log; `--clear` deletes the log.

## 0.1.0

- First release: `flutterpilot init` (adds the SDK, matching plugins and the
  macOS network entitlement), `mcp install` (MCP config for Claude Code,
  Cursor, VS Code), `dev` (runs the app so the server finds it), `doctor`
  (checks the setup and the running app).
