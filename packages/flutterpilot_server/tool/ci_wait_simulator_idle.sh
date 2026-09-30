#!/bin/sh
# Waits until a freshly booted iOS simulator has finished its first-boot work
# before the e2e drives an app on it (run from any folder).
#
# A new simulator indexes for minutes after boot (on a CI runner: Shortcuts
# actions for Spotlight, "Indexed: 1097 ... Finished in 331s", starting ~5 min
# after boot). Checks that ran meanwhile timed out or lost the VM service.
#
# The simulator's processes run on the host from its runtime root, so their
# CPU is measurable here. Quiet means under $QUIET % for $CALM samples in a
# row, and at least $MIN_WAIT s after boot: on the runner the indexing
# started ~4.7 min after boot. (A fresh simulator on a 10-core Mac: busy for
# ~2.5 min after boot, then quiet but for single-sample spikes.)
#
#   sh tool/ci_wait_simulator_idle.sh <udid> [booted-at-epoch-seconds]
set -u
udid=$1
booted=${2:-$(date +%s)}
QUIET=${QUIET:-60}
CALM=${CALM:-6}
STEP=${STEP:-5}
MIN_WAIT=${MIN_WAIT:-300}
MAX_WAIT=${MAX_WAIT:-900}

busy() {
  ps -A -o %cpu=,args= | grep -F 'RuntimeRoot' | grep -v grep
}

calm=0
while :; do
  now=$(date +%s)
  since=$((now - booted))
  cpu=$(busy | awk '{s+=$1} END {printf "%.0f", s}')
  if [ "$cpu" -lt "$QUIET" ]; then calm=$((calm + 1)); else calm=0; fi
  if [ $((since % 30)) -lt "$STEP" ] || [ "$calm" -eq 0 ]; then
    top=$(busy | sort -rn | head -3 |
      awk '{sub(/.*RuntimeRoot/, ""); split($0, w, " "); n=split(w[1], a, "/"); printf "%s ", a[n]}')
    echo "simulator $udid: ${since}s after boot, ${cpu}% CPU${top:+ ($top)}"
  fi
  if [ "$calm" -ge "$CALM" ] && [ "$since" -ge "$MIN_WAIT" ]; then
    echo "simulator quiet ${since}s after boot"
    exit 0
  fi
  if [ "$since" -ge "$MAX_WAIT" ]; then
    echo "::warning::simulator still busy ${since}s after boot (${cpu}% CPU); running the e2e anyway"
    exit 0
  fi
  sleep "$STEP"
done
