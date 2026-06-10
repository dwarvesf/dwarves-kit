#!/usr/bin/env bash
# spec-next.sh -- collision-proof next SPEC number (SPEC-064 / ID-052).
#
# SPEC numbers collided twice in one week (SPEC-047, SPEC-041) because "max of
# docs/specs/ + 1" goes stale the moment a numbered spec ages inside an unmerged
# branch. This scans EVERY visible surface: docs/specs/ filenames, local branch
# names, remote branch names (after a fetch), and SPEC-NNN mentions in recent
# commit subjects, then prints max+1.
#
# Usage:
#   spec-next.sh next         -> the next free number (e.g. "064")
#   spec-next.sh check <NNN>  -> exit 0 if free, exit 1 (+ where seen) if taken
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

_numbers() {
  {
    ls "$ROOT/docs/specs" 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
    git -C "$ROOT" branch -a --format='%(refname:short)' 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
    git -C "$ROOT" log --all --format='%s' -200 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
  } | grep -oE '[0-9]+' | sort -n | uniq
}

next() {
  local max
  max="$(_numbers | tail -1)"
  [ -n "$max" ] || { echo "001"; return 0; }
  printf '%03d\n' "$((10#$max + 1))"
}

check() {
  local n="${1:-}"; [ -n "$n" ] || { echo "usage: check <NNN>" >&2; return 64; }
  n="$(printf '%03d' "$((10#$n))")"
  if _numbers | grep -qx "$((10#$n))" || _numbers | grep -qx "$n"; then
    echo "SPEC-$n is TAKEN (seen in specs/, a branch, or a recent commit subject)" >&2
    return 1
  fi
  echo "SPEC-$n is free"
}

main() {
  local sub="${1:-next}"; shift || true
  case "$sub" in
    next)  next ;;
    check) check "$@" ;;
    *) echo "usage: spec-next.sh {next|check <NNN>}" >&2; return 64 ;;
  esac
}

main "$@"
