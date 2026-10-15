# 14 · `launch_app(relaunch: true)` must not leave the app down (#346)

**Branch:** `fix/relaunch-safety` from `main`, **after** #124 is merged ·
**Depends on:** #124

## Problem

On a machine with more than one device (Windows desktop plus Chrome and
Edge), `launch_app(relaunch: true)` without `device` **stops the running app
first**, then `flutter run` refuses with "More than one device connected".
The agent is left with no app and an error, which is worse than the stale
app it had. Finding #346. Workaround today: pass `device`.

## Fix

1. **Relaunch keeps the device it had.** When `relaunch: true` and no
   `device` is given, use the device of the app being replaced. The server
   knows it (the connected app's platform and device; `list_connected_devices`
   shows it). Say which device was used in the response
   ("Relaunched on windows (the device it was running on)").
2. **Check before stopping.** If the device still can't be decided (fresh
   launch, several devices, nothing running), refuse **before** stopping
   anything, listing the devices (`flutter devices --machine`, already used
   by `test_generation_tools.dart`) and the call to make:
   `launch_app(device: "windows")`. A fresh launch with one device keeps
   working as today.
3. **Never kill on a doomed start.** In general, a relaunch only stops the
   old app once the new command has been resolved (task 10's
   `startCommandFor`) and the device is known. Don't try to keep both
   running; just don't stop the old one for a reason that was knowable
   up front.

## Tests

- Unit: device chosen from the running app; refusal with several devices
  and nothing running, without calling the stop function (inject the stop and
  device-list functions; follow `app_launcher_test.dart`'s style).
- Field, `../fp_lab_shop` with Chrome/Edge also listed:
  `launch_app(relaunch: true)` with no `device` relaunches on windows; with
  the app stopped and no `device`, the call refuses and lists the devices.
- README Definition of done items 1–5, 7; mark #346 fixed in
  `docs/field-test-findings.md`; a CHANGELOG bullet under the server's
  `## Unreleased`.

## Review of PR #128 (2026-10-15): one regression to fix before merging

The order fix is right and the field checks are good. But `prepareLaunch`
now runs **before** the "a launch is already in progress" check, and that
breaks the documented way to wait for a long build:

1. `launch_app(device: "windows", waitSeconds: 30)` returns "Still building
   after 30 s; the launch goes on. Call launch_app again to keep waiting (it
   will not start a second build)."
2. The agent does what it says: `launch_app()` with no arguments.
3. Nothing is connected, so no device comes from the running app; `flutter
   devices` lists windows, chrome and edge (Chrome is listed on almost every
   dev machine) → **refused**: "More than one device is connected … cannot
   tell which one to use; nothing was launched or stopped." That's wrong: a
   launch *is* going on, the call was only meant to wait for it, and it costs
   an extra `flutter devices` run (~1 s) on every waiting call.

On `main` the same second call waited for the build, because `inProgress`
(`!relaunch && runningLaunchPid(root) != null && !connected`) was settled
before any device question.

### Fix

- Work out `inProgress` first. When it is true, skip `prepareLaunch`
  entirely (no device to choose, nothing to stop, no `flutter devices` call)
  and go straight to waiting, as `main` does. Keep using the command of the
  launch that is running for the messages (or say "the launch in progress"
  when it is not known).
- Unit test: a pid file present, nothing connected, `relaunch: false`, no
  `device`, several devices → no refusal, `listDevices` not called, `stop`
  not called. Put the decision in a pure function if `_launchApp` is too hard
  to test directly.
- Field check on `../fp_lab_shop` (Windows, Chrome and Edge listed): stop the
  app, `launch_app(device: "windows", waitSeconds: 5)` → "Still building",
  then `launch_app()` → it waits and connects ("The launch finished: …").
  Paste both responses.

### Optional, if cheap (say in the PR if you skip it)

A fresh launch on a machine with several devices now always refuses unless
`device` is given. If the project's last launch is recorded (the run log or
pid file records the command with `-d <id>`), use that device and say so in
the response ("on windows, the device of the last launch"), the same way a
relaunch reuses the running app's device. Only if the record is reliable;
otherwise leave the refusal, it is correct and says what to pass.

Update PR #128 (same branch), its description's field checks, and the
findings/CHANGELOG lines if the behaviour they describe changes.
