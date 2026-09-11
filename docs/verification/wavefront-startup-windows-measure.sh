#!/bin/bash
# Green measurement for docs/verification/wavefront-startup-windows.md.
# Runs the wavefront suite under INDUCED load, the condition that broke the previous windows.
# Burners are killed on every exit path so none outlive the measurement.
# Usage: bash docs/verification/wavefront-startup-windows-measure.sh [runs] [burners]
cd "$(dirname "$0")/../.." || exit 1
runs="${1:-3}"
burners="${2:-8}"

pids=""
cleanup() {
  for p in $pids; do kill -9 "$p" 2>/dev/null; done
  pkill -f 'claude-longsleep' 2>/dev/null
  echo "burners stopped"
}
trap cleanup EXIT INT TERM

for _i in $(seq 1 "$burners"); do
  ( while :; do :; done ) &
  pids="$pids $!"
done
sleep 20   # let the load average climb before the first run
echo "burners up ($burners), load=$(uptime | sed 's/.*averages: //')"

fails=0
for i in $(seq 1 "$runs"); do
  s=$(date +%s)
  out=$(bash tests/test-orchestrate-wavefront.sh 2>&1)
  d=$(( $(date +%s) - s ))
  echo "run $i: $(printf '%s' "$out" | tail -1) (${d}s) load=$(uptime | sed 's/.*averages: //')"
  if printf '%s' "$out" | grep -qE '^FAIL'; then
    fails=$((fails + 1))
    printf '%s' "$out" | grep -E '^FAIL' | head -3
  fi
done
echo "RESULT: $fails failure(s) in $runs run(s) under induced load"
