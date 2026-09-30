#!/usr/bin/env bash
# kit-verb: recheck-sample decide | decide and record whether an execute run rechecks its end-verifier PASSes, keyed on the rid
# recheck-sample.sh -- decide whether a /kit:execute run rechecks its end-verifier PASSes.
#
#   recheck-sample.sh decide <rid> [N]
#
# Prints `sampled` or `skipped` and records `recheck: sampled|skipped key=<rid>` in the run
# ledger, so anyone can recompute the decision. The key is the rid: the lead creates it
# before the builder dispatches, so no builder commit can move it.
# N defaults to `kit_config_get_root execute.recheck_sample 5` (root-only: a project
# .kit.toml rides inside an untrusted PR and must not lower verification).
#   N=0  never sample (the only way to turn sampling off)
#   N=1  sample every run (every PASS rechecked)
#   N>1  sampled when the first cksum field of the rid is divisible by N
# A non-numeric N falls back to 5. Always exits 0 on a decision; 64 on bad usage.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

decide() {
  local rid="${1:-}" n="${2:-}" sum verdict
  [ -n "$rid" ] || { echo "usage: recheck-sample.sh decide <rid> [N]" >&2; return 64; }
  if [ -z "$n" ]; then
    # shellcheck source=/dev/null
    . "$DIR/../config/kit-config.sh"
    n="$(kit_config_get_root execute.recheck_sample 5)"
  fi
  case "$n" in ''|*[!0-9]*) n=5 ;; esac
  if [ "$n" -eq 0 ]; then
    verdict=skipped
  elif [ "$n" -eq 1 ]; then
    verdict=sampled
  else
    sum="$(printf '%s' "$rid" | cksum | cut -d' ' -f1)"
    if [ $((sum % n)) -eq 0 ]; then verdict=sampled; else verdict=skipped; fi
  fi
  bash "$DIR/gate-ledger.sh" action "$rid" "recheck: $verdict key=$rid" >/dev/null 2>&1 || true
  echo "$verdict"
}

case "${1:-}" in
  decide) shift; decide "$@" ;;
  *) echo "usage: recheck-sample.sh decide <rid> [N]" >&2; exit 64 ;;
esac
