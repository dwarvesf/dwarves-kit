#!/usr/bin/env bash
# test-lanes-data.sh -- lanes as data: the lane reader, the light default classifier, the
# hard-path floor, and the ship-gate wiring. Each case prints `PASS <name>` or
# `FAIL <name>: <why>`; the file exits nonzero on any FAIL.
#
# Run: bash tests/test-lanes-data.sh [case ...]   (no args = every case)
#      bash tests/test-lanes-data.sh baseline     (rewrites docs/verification/lanes-as-data/baseline.txt)
#
# Isolation: every case builds temp repos and a temp DWARVES_KIT_LOG_DIR; the real ledger
# corpus and the operator overlay are never read or written.

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
LC="$KIT_DIR/lib/classify/lane-classify.sh"
GP="$KIT_DIR/lib/gate/gate-policy.sh"
HOOK="$KIT_DIR/hooks/ship-gate.sh"
BASELINE="$KIT_DIR/docs/verification/lanes-as-data/baseline.txt"
LANES="tiny normal full bug backfill"

FAILS=0
TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS+1)); }

# Every gate-ledger call in this file runs on a temp log dir with no operator overlay.
LOGD=""
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" KIT_CONFIG_OPERATOR=/nonexistent bash "$GL" "$@"; }

# ---------------------------------------------------------------------------
# capture: plan + required for all five lanes, plus progress + descent against a canned
# fixture ledger (fixed rid; ran, skipped, bare skip, override, one out-of-order record).
# ---------------------------------------------------------------------------
capture() {
  new_log
  local rid=fixture-rid l
  {
    printf '%s\n' "2026-01-01T00:00:00Z | START | lane=normal classified=normal type=spec-feature repo=fx"
    printf '%s\n' "2026-01-01T00:00:01Z | GATE | grill | ran | fixture"
    printf '%s\n' "2026-01-01T00:00:02Z | GATE | build | ran | out of order on purpose"
    printf '%s\n' "2026-01-01T00:00:03Z | GATE | spec | ran | fixture"
    printf '%s\n' "2026-01-01T00:00:04Z | GATE | think | skipped | fixture reason"
    printf '%s\n' "2026-01-01T00:00:05Z | GATE | review | skipped | "
    printf '%s\n' "2026-01-01T00:00:06Z | GATE | validate | override | fixture override"
  } > "$LOGD/runs/$rid.log"
  for l in $LANES; do
    echo "== plan $l";     gl plan "$l" 2>&1
    echo "== required $l"; gl required "$l" 2>&1
    echo "== progress $l"; gl progress "$rid" "$l" 2>&1
    echo "== descent $l";  gl descent "$rid" "$l" 2>&1
  done
}

case_baseline() { mkdir -p "$(dirname "$BASELINE")"; capture > "$BASELINE"; echo "wrote $BASELINE ($(wc -l < "$BASELINE") lines)"; }

case_parity() {
  local d; d="$(diff "$BASELINE" <(capture))" && pass parity || fail parity "reader output differs from the baseline: $(printf '%s' "$d" | head -6 | tr '\n' '~')"
}

# After the normal-lane flip only normal's validate and review may differ from the baseline.
# Each output line is prefixed with its section header so a changed line names its lane.
_annotate() { awk '/^== /{sec=$2" "$3; next} {print sec ": " $0}'; }
case_parity_after_flip() {
  local d bad
  d="$(diff <(_annotate < "$BASELINE") <(capture | _annotate) | grep -E '^[<>]' || true)"
  [ -n "$d" ] || { fail parity-after-flip "no difference: the flip did not land"; return; }
  bad="$(printf '%s\n' "$d" | grep -vE '^[<>] (plan|required|progress|descent) normal: .*(validate|review)' || true)"
  if [ -z "$bad" ]; then pass parity-after-flip
  else fail parity-after-flip "unexpected changed lines: $(printf '%s' "$bad" | head -4 | tr '\n' '~')"; fi
}
case_plan_flip() {
  local out; new_log
  out="$(gl required normal | tr '\n' ' ')"
  [ "$out" = "spec validate build review ship " ] && pass plan-flip || fail plan-flip "required normal = '$out'"
}

# ---------------------------------------------------------------------------
run_case() {
  local fn="case_${1//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else fail "$1" "no such case"; fi
}
# `parity` (byte-identical against the baseline) holds only at the refactor commit; after the
# flip the standing check is parity-after-flip.
ALL="parity-after-flip plan-flip"
if [ "$#" -eq 0 ]; then set -- $ALL; fi
for c in "$@"; do run_case "$c"; done
[ "$FAILS" -eq 0 ]
