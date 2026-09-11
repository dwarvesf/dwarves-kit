#!/bin/bash
# Negative control for docs/verification/wavefront-startup-windows.md.
# Restores the PREVIOUS window values and runs the suite under a load comparable to the green
# measurement (1-minute averages of 31 to 91). Expect RED.
#
# Load must be MATCHED or this proves nothing: a first attempt with 8 burners and a 20s ramp only
# reached 11.4 and passed. 16 burners with a 60s ramp reproduces.
# Restores the committed file on every exit path.
# Usage: bash docs/verification/wavefront-startup-windows-negctl.sh [runs] [burners]
cd "$(dirname "$0")/../.." || exit 1
F=tests/test-orchestrate-wavefront.sh
runs="${1:-3}"
burners="${2:-16}"

pids=""
cleanup() {
  for p in $pids; do kill -9 "$p" 2>/dev/null; done
  pkill -f 'claude-longsleep' 2>/dev/null
  git checkout -- "$F"
  echo "restored: $(git status --short "$F" | wc -l | tr -d ' ') dirty"
}
trap cleanup EXIT INT TERM

sed -i '' \
  -e 's/BARRIER_T:-120/BARRIER_T:-20/' \
  -e 's/BARRIER_T=120/BARRIER_T=20/g' \
  -e 's/^sleep 300$/sleep 30/' \
  -e 's/for _i in \$(seq 1 480); do/for _i in $(seq 1 120); do/' \
  "$F"
bash -n "$F" || { echo "revert broke syntax"; exit 1; }
echo "OLD values in place: $(grep -c 'BARRIER_T=20' "$F") barrier sites, poll=$(grep -o 'seq 1 120' "$F" | head -1), mock=$(grep -c '^sleep 30$' "$F")"

for _i in $(seq 1 "$burners"); do ( while :; do :; done ) & pids="$pids $!"; done
sleep 60   # the 1-minute average needs time to reflect the burners
echo "burners up ($burners), load=$(uptime | sed 's/.*averages: //')"

fails=0
for i in $(seq 1 "$runs"); do
  s=$(date +%s)
  out=$(bash "$F" 2>&1)
  d=$(( $(date +%s) - s ))
  echo "negctl run $i: $(printf '%s' "$out" | tail -1) (${d}s) load=$(uptime | sed 's/.*averages: //')"
  if printf '%s' "$out" | grep -qE '^FAIL'; then
    fails=$((fails + 1))
    printf '%s' "$out" | grep -E '^FAIL' | head -3
  fi
done
echo "NEGCTL RESULT: $fails failure(s) in $runs run(s) at OLD values under matched load"
