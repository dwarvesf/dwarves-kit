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
#   spec-next.sh reserve      -> atomically claim + print the next free number (SPEC-128)
#
# SPEC-128 closes the CONCURRENCY case SPEC-064 did not: a parallel wave that each calls
# `next` BEFORE any branch/spec exists all scan the same surfaces and get the SAME number.
# The scan is correct; the reservation happens too late. `reserve` claims a number under a
# portable mkdir-mutex and records it in a reservations ledger that `_numbers()` folds in, so
# a reserved number reads as TAKEN by the very next caller. `next`/`check` are unchanged in
# contract: with an empty ledger they behave byte-identically to before.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO="$(basename "$ROOT")"

# Durable reservations ledger under the kit log dir (same root gate-ledger.sh writes to).
# Sourced best-effort: if kit-log-dir.sh is missing (e.g. spec-next copied standalone), fall
# back to a temp-dir ledger so `next`/`check` still work; only `reserve` needs the durable path.
_SPEC_NEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$_SPEC_NEXT_DIR/kit-log-dir.sh" ]; then
  # shellcheck source=lib/kit-log-dir.sh
  source "$_SPEC_NEXT_DIR/kit-log-dir.sh" 2>/dev/null || true
fi
if command -v kit_resolve_log_dir >/dev/null 2>&1; then
  RES_DIR="$(kit_resolve_log_dir)"
else
  RES_DIR="${TMPDIR:-/tmp}/dwarves-kit-spec-reserve"
fi
RES_FILE="${SPEC_RESERVE_FILE:-$RES_DIR/spec-reservations.log}"
RES_LOCK="$RES_FILE.lock"
# Abandoned-reservation TTL: a reservation older than this (worker died before creating its
# branch) stops counting and gets pruned. A stale LOCK dir older than this is reclaimed.
SPEC_RESERVE_TTL="${SPEC_RESERVE_TTL:-86400}"   # 24h in seconds

now_epoch() { date -u +%s; }

# ISO8601 -> epoch seconds, portable across BSD (macOS) and GNU date. Empty on parse failure.
_iso_to_epoch() {
  local iso="$1" e
  e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)" \
    || e="$(date -u -d "$iso" +%s 2>/dev/null)" || e=""
  printf '%s' "$e"
}

# The REAL scan surfaces (specs + branches + commits) , the SPEC-064 union, unchanged. Split
# out so reconciliation can tell a REALIZED reservation (its number now here) from a live one.
_scan_numbers() {
  {
    ls "$ROOT/docs/specs" 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
    git -C "$ROOT" branch -a --format='%(refname:short)' 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
    git -C "$ROOT" log --all --format='%s' -200 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
  } | grep -oE '[0-9]+' | sort -n | uniq
}

# LIVE reservation numbers for THIS repo: repo-scoped AND within TTL (an expired line stops
# counting even before it is physically pruned). Empty when no ledger exists (the common case,
# which keeps `next`/`check` byte-identical to SPEC-064).
_reservations() {
  [ -f "$RES_FILE" ] || return 0
  local cutoff; cutoff=$(( $(now_epoch) - SPEC_RESERVE_TTL ))
  while IFS= read -r line; do
    case "$line" in *"| RESERVE |"*) ;; *) continue;; esac
    case "$line" in *"repo=$REPO"*) ;; *) continue;; esac
    local iso num e
    iso="${line%% | *}"
    num="$(printf '%s' "$line" | grep -oE 'num=[0-9]+' | head -1 | cut -d= -f2)"
    [ -n "$num" ] || continue
    e="$(_iso_to_epoch "$iso")"
    # A line whose timestamp we cannot parse is kept (fail-safe: better to over-reserve than
    # to hand out a number a live sibling may hold).
    if [ -n "$e" ] && [ "$e" -lt "$cutoff" ]; then continue; fi
    printf '%s\n' "$num"
  done < "$RES_FILE"
}

# The full union readers see: the real scan PLUS live reservations. `_scan_numbers` is the
# SPEC-064 body verbatim; folding reservations in is purely additive.
_numbers() {
  { _scan_numbers; _reservations; } | sort -n | uniq
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
    echo "SPEC-$n is TAKEN (seen in specs/, a branch, a recent commit subject, or a live reservation)" >&2
    return 1
  fi
  echo "SPEC-$n is free"
}

# ---- SPEC-128: atomic reservation ---------------------------------------------------------
# Prune dead reservation lines IN PLACE (called only while the lock is held, so the rewrite
# is serialized). Drops lines that are REALIZED (number now in the real scan) or EXPIRED
# (older than TTL). Repo-scoped: lines for OTHER repos are always kept verbatim.
_prune_reservations() {
  [ -f "$RES_FILE" ] || return 0
  local realized cutoff tmp
  realized="$(_scan_numbers)"
  cutoff=$(( $(now_epoch) - SPEC_RESERVE_TTL ))
  tmp="$RES_FILE.tmp.$$"
  : > "$tmp"
  local line iso num e keep
  while IFS= read -r line; do
    keep=1
    if printf '%s' "$line" | grep -q "| RESERVE |" && printf '%s' "$line" | grep -q "repo=$REPO"; then
      iso="${line%% | *}"
      num="$(printf '%s' "$line" | grep -oE 'num=[0-9]+' | head -1 | cut -d= -f2)"
      if [ -n "$num" ]; then
        # realized? (match both the zero-padded and the bare-integer form, as check() does:
        # _scan_numbers emits zero-padded "006" while $((10#$num)) is "6").
        if printf '%s\n' "$realized" | grep -qx "$num" || printf '%s\n' "$realized" | grep -qx "$((10#$num))"; then keep=0; fi
        # expired?
        e="$(_iso_to_epoch "$iso")"
        if [ -n "$e" ] && [ "$e" -lt "$cutoff" ]; then keep=0; fi
      fi
    fi
    [ "$keep" = 1 ] && printf '%s\n' "$line" >> "$tmp"
  done < "$RES_FILE"
  mv -f "$tmp" "$RES_FILE" 2>/dev/null || rm -f "$tmp"
}

# Acquire the mkdir-mutex (portable; macOS has no flock, orchestrate.sh is no-flock by
# contract). Exactly one racer creates the dir; the rest retry with a randomized backoff.
# A lock DIR older than TTL is reclaimed (a dead holder must not wedge the wave). Loud fail
# after a bounded number of tries so a live contender never spins forever silently.
_reserve_lock() {
  mkdir -p "$RES_DIR" 2>/dev/null || true
  local tries=0 max=600   # ~ up to 30s at 50ms; ample for a wave of a few workers
  while ! mkdir "$RES_LOCK" 2>/dev/null; do
    # stale-lock reclaim: if the lock dir is older than TTL, a prior holder died with it held.
    if [ -d "$RES_LOCK" ]; then
      local lockage e
      e="$(_lock_mtime_epoch "$RES_LOCK")"
      if [ -n "$e" ]; then
        lockage=$(( $(now_epoch) - e ))
        if [ "$lockage" -gt "$SPEC_RESERVE_TTL" ]; then
          rmdir "$RES_LOCK" 2>/dev/null || true
          continue
        fi
      fi
    fi
    tries=$((tries + 1))
    [ "$tries" -ge "$max" ] && { echo "spec-next reserve: could not acquire lock after $max tries ($RES_LOCK)" >&2; return 1; }
    # randomized sub-100ms backoff to desynchronize racers
    sleep "0.0$(( (RANDOM % 9) + 1 ))"
  done
  return 0
}

_lock_mtime_epoch() {
  local d="$1"
  stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || printf ''
}

# reserve: atomically claim + print the next free number. acquire -> compute next (folding
# live reservations) -> append the claim -> prune dead lines -> release. Indivisible, so two
# concurrent `reserve` calls serialize and get DISTINCT numbers.
reserve() {
  _reserve_lock || return 1
  # Free the lock on any exit from here (crash-safety: a killed reserve must not wedge).
  trap 'rmdir "$RES_LOCK" 2>/dev/null || true' EXIT INT TERM
  local n
  n="$(next)"
  mkdir -p "$RES_DIR" 2>/dev/null || true
  printf '%s | RESERVE | num=%s repo=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$n" "$REPO" >> "$RES_FILE"
  _prune_reservations
  rmdir "$RES_LOCK" 2>/dev/null || true
  trap - EXIT INT TERM
  printf '%s\n' "$n"
}

main() {
  local sub="${1:-next}"; shift || true
  case "$sub" in
    next)    next ;;
    check)   check "$@" ;;
    reserve) reserve ;;
    *) echo "usage: spec-next.sh {next|check <NNN>|reserve}" >&2; return 64 ;;
  esac
}

main "$@"
