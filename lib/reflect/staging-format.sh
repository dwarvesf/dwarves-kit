#!/usr/bin/env bash
# staging-format.sh -- the bash door to the one staging write path (sourced by
# hooks/backlog-stage.sh and hooks/intake-sweep.sh). The hooks render blocks in jq and cannot
# import staging-format.py, so they pipe the rendered text here.
#
#   sf_append <staging-file> <header-text>   stdin = rendered blocks; exit 0 on success
#
# With python3 the append goes through `staging-format.py append`: the shared staging lock, the
# header written once. Without python3 (the hooks run on bash plus jq alone) it is a plain
# append: such a host has no promote, drain or anomalies run either, so nothing rewrites the
# buffer and the lock has nothing to exclude.

sf_append() {
  local st=$1 header=${2-} here dir
  here=${BASH_SOURCE[0]%/*}
  if command -v python3 >/dev/null 2>&1; then
    python3 "$here/staging-format.py" append "$st" --header "$header" >/dev/null 2>&1
    return $?
  fi
  dir=${st%/*}; [ -n "$dir" ] || dir=/
  { mkdir -p "$dir" && { [ -s "$st" ] || printf '%s' "$header"; cat; } >> "$st"; } 2>/dev/null
}
