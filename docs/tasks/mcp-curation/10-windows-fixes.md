# 10 · Windows fixes: launch_app, init --local paths, the failing tests

**Branch:** `fix/windows` · **Base:** `integration/mcp-curation` (task 09)
until that merges, then `main` · **Depends on:** 09

Round 1 found that FlutterPilot's own setup and launch paths are broken on
Windows (field-test findings #326, #327), and two unit tests have always
failed on Windows. Every developer on Windows hits these first.

## 1. `launch_app` can't start `flutter` on Windows (#327)

`lib/src/app_launcher.dart` (~line 244) runs `Process.start(args[1],
args.sublist(2), workingDirectory: ...)` with no shell. On Windows `flutter`
and `dart` are `.bat` files, which `Process.start` can't run without a shell:
`Could not start "flutter": The system cannot find the file specified`.
Line ~200 has another `Process.start`; check every `Process.start` /
`Process.run` / `Process.runSync` in `packages/flutterpilot_server/lib` and
`packages/flutterpilot_cli/lib` that can start `flutter`, `dart`, or a
command from `flutterpilot/launch.json`.

Fix: on Windows, resolve the executable the way a shell would (PATH +
`PATHEXT`: `.exe`, `.bat`, `.cmd`) and, for `.bat`/`.cmd`, start it through
`runInShell: true`. Watch for:

- **Argument quoting** under `cmd.exe`: dart-defines with spaces, `&`, `^`,
  `%`, quotes. Write a test with such an argument (e.g.
  `--dart-define=GREETING=a b&c`) and check what the child process receives.
- **The PID file and stopping the app**: with a shell, `process.pid` is the
  shell's PID, not flutter's. Check how a relaunch stops the old app
  (`flutterpilot_run.pid`, kill logic) and make sure it still kills the
  whole tree on Windows (`taskkill /T /F /PID`), or the old app keeps running.
- `flutterpilot/launch.json` custom commands (`./scripts/run.sh` won't exist
  on Windows; a `.bat`/`.ps1` command must work).

Tests: unit tests for executable resolution (fake PATH/PATHEXT) and the
kill-tree command on Windows. Field check: `launch_app` on `../fp_lab_shop`
from the bridge (fresh, then `relaunch: true` with an app running, then
`mode: "profile"`), pasted. Then the eval runner's `--launch` works too
(remove the "broken on Windows" note in `tool/eval/run_evals.dart` and its
README).

## 2. `init --local` writes backslash paths (#326)

`packages/flutterpilot_cli/lib/src/commands/init_command.dart` (~line 188)
writes `p.relative(...)` into `pubspec.yaml`. On Windows that gives
`..\FlutterPilot\packages\...`, which the `path_not_posix` lint flags. Pub
accepts forward slashes on every OS: write `p.posix`-style paths (convert the
relative path's separators). Check every other place the CLI writes a path
into a file meant to be committed (`pubspec.yaml`, `pubspec_overrides.yaml`,
MCP configs where the client expects POSIX, `launch.json`). MCP config files
for Windows clients may legitimately need Windows paths for the server
command; don't change those, only paths that pub or Dart tooling reads.

Tests: CLI test that `init --local` output has no backslash on Windows-style
input (use `p.Context(style: p.Style.windows)` if the code takes a context,
or test the conversion function directly). Field check: re-run `init --local`
on a fresh `flutter create` app on this machine; `flutter analyze` clean.

## 3. `code_freshness_test.dart` fails on Windows

Two tests expect `lib/f5.dart` and get `lib\f5.dart`. Decide which is right
**for the agent reading it**: the message names files for an agent that may
then open them. Forward slashes work in every tool on every OS and match
`inspect_widget`'s `lib/...` locations. So fix the **code**
(`lib/src/code_freshness.dart`) to report POSIX-style relative paths, not the
test. Check other tool outputs that print app file paths
(`inspect_widget`, `get_errors` frames, `audit_screen_health` "Code:" lines,
reload failures) for the same mix; list what you find, fix the ones that are
one-line changes, and leave the rest listed in the PR.

After this, `dart test` in `packages/flutterpilot_server` must pass with
**zero** failures on Windows. Update task 09's/README's "2 known failures"
wording if this lands after them.

## Done when

- [ ] `launch_app` works on Windows (fresh, relaunch, profile), tests for
      resolution, quoting and kill-tree.
- [ ] `init --local` writes POSIX paths; analyze clean on a fresh app.
- [ ] Server tests: 0 failures on Windows.
- [ ] e2e `-d windows` passes; README Definition of done items 1–5, 7.
- [ ] Findings #326/#327 marked fixed in `docs/field-test-findings.md`
      (follow how earlier rounds mark a fixed finding).
