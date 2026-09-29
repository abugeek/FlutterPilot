#!/bin/sh
# The Android e2e on CI's emulator (run from packages/flutterpilot_server).
# Emulators on hosted runners are slow: one visible retry, but only while
# the emulator still answers. On failure it says why: the app's death in
# the emulator's log, or the emulator's own death in the runner's memory.
set -u
device=emulator-5554

run() { dart run tool/e2e_test.dart -d "$device"; }
alive() { timeout 10 adb -s "$device" shell true >/dev/null 2>&1; }

run && exit 0
if alive; then
  echo "::warning::Android e2e failed once on this runner; retrying"
  run && exit 0
fi

echo "::group::Why the Android e2e failed"
if alive; then
  timeout 60 adb -s "$device" logcat -d -b main,system,crash |
    grep -iE 'flutter|fixture|lowmemory|lmkd|am_kill|FATAL|ANR|has died|signal' |
    tail -300
else
  echo "::error::The emulator itself stopped (adb no longer reaches it)."
fi
free -m
sudo dmesg | grep -iE 'out of memory|killed process|oom' | tail -20
ps aux --sort=-rss | head -15
echo "::endgroup::"
exit 1
