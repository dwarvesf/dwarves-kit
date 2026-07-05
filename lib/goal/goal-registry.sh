#!/usr/bin/env bash
# goal-registry.sh -- the cross-session running-goal registry (ADR-0022, SPEC-036).
#
# The substrate that lets ONE operator run several Claude sessions on ONE machine
# (one goal per session) without the goals colliding, and lets a human see every
# running goal in one place. It is the cross-session complement to /kit:dispatch's
# single-lead in-session fan-out (SPEC-032): there is no shared lead across sessions,
# so the disjointness moat and the monitor both move onto disk.
#
# It RECORDS and COMPARES; it never launches a session, sequences goals, or merges.
# No daemon, no lock server, no scheduler, no durability state machine (that is L5 /
# Nimbalyst, ADR-0022). Pure bash + flat files.
#
# Registry root: $(git rev-parse --git-common-dir)/kit-goals/ -- the git common dir,
# shared by every worktree of one repo on one machine and inherently untracked. The
# location IS the boundary: a different machine has a different .git, so cross-machine
# coordination is structurally impossible here (it stays L5). Override with
# GOAL_REGISTRY_DIR for tests.
#
# Each goal is ONE file (single-writer: only that goal's session writes it):
#   <slug>.goal      key=value claim record (slug/lane/status/branch/worktree/touches/...)
#   <slug>.attempts  append-only, timestamped, human-legible "what it tried" log
#
# The disjointness rule is REUSED from dispatch-gate.sh (gate_normalize_glob +
# prefix_overlap), not re-implemented: one source for the one safety-critical compare.
#
# Subcommands:
#   claim <slug> <lane> <glob...>   gate vs active goals; on clear, write the record (exit 0);
#                                   on overlap, name the colliding goal (exit 1)
#   list                            print a table of every active goal (the monitor)
#   log <slug> <message...>         append one timestamped line to <slug>.attempts
#   status <slug> <state>           update the record's status= (running|blocked|ready|done)
#   release <slug>                  remove the goal's files (call on completion)
#   dir                             print the resolved registry root

set -euo pipefail

REG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$REG_SELF_DIR/.." && pwd)"  # the lib/ dir; cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
# Reuse the gate's normalize + overlap functions (single source for disjointness).
# shellcheck source=lib/gate/dispatch-gate.sh
. "$LIB_ROOT/gate/dispatch-gate.sh"

# Empty globs expand to nothing instead of staying literal (safe iteration under set -e).
shopt -s nullglob

# --- registry root ----------------------------------------------------------

registry_dir() {
  if [ -n "${GOAL_REGISTRY_DIR:-}" ]; then
    printf '%s\n' "$GOAL_REGISTRY_DIR"
    return 0
  fi
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
    echo "goal-registry: not a git repository (the registry lives under .git)" >&2
    return 3
  }
  # git-common-dir may be relative (".git" from the main checkout); make it absolute.
  case "$common" in
    /*) : ;;
    *)  common="$(cd "$common" && pwd)" ;;
  esac
  printf '%s/kit-goals\n' "$common"
}

# --- slug guard -------------------------------------------------------------

# A slug names a single file (<slug>.goal); a slash would create a subdirectory and
# split the registry. Reject slashes and path-traversal; require a clean kebab/word slug.
_reg_check_slug() {
  local slug="$1"
  case "$slug" in
    ""|*/*|*..*)
      echo "goal-registry: invalid slug '$slug' (no slashes; use the bare spec slug, not goal/<slug>)" >&2
      return 64;;
  esac
  return 0
}

# --- record read ------------------------------------------------------------

# Print the value of one key from a .goal file. Missing file/key -> empty, exit 0
# (kept exit-0 so it is safe inside command substitution under set -e).
reg_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$file"
}

# --- disjointness against active goals --------------------------------------

# Do raw glob list $1 and raw glob list $2 overlap? Overlap if any cross pair of
# normalized prefixes overlaps, OR either side has an unprovable glob (conservative).
_reg_overlap() {
  local a_raw="$1" b_raw="$2" a b na nb
  # Split on whitespace WITHOUT pathname expansion: the globs contain `**`, and with
  # nullglob set an unquoted `for a in $a_raw` would glob-expand them to nothing.
  local -a alist blist
  IFS=' ' read -r -a alist <<< "$a_raw"
  IFS=' ' read -r -a blist <<< "$b_raw"
  for a in "${alist[@]}"; do
    [ -n "$a" ] || continue
    na="$(gate_normalize_glob "$a")"
    case "$na" in '?'*) return 0;; esac
    for b in "${blist[@]}"; do
      [ -n "$b" ] || continue
      nb="$(gate_normalize_glob "$b")"
      case "$nb" in '?'*) return 0;; esac
      if prefix_overlap "$na" "$nb"; then
        return 0
      fi
    done
  done
  return 1
}

# Name the first ACTIVE goal (other than $1) whose stored globs overlap $2 (raw globs).
# Empty output = no collision.
_reg_first_collision() {
  local self="$1" raw="$2" dir f other ot
  dir="$(registry_dir)" || return $?
  for f in "$dir"/*.goal; do
    other="$(reg_get "$f" slug)"
    [ "$other" = "$self" ] && continue
    ot="$(reg_get "$f" touches)"
    if _reg_overlap "$raw" "$ot"; then
      printf '%s\n' "$other"
      return 0
    fi
  done
  return 0
}

# --- subcommands ------------------------------------------------------------

reg_claim() {
  local slug="${1:-}" lane="${2:-}"
  shift 2 2>/dev/null || true
  local globs=("$@")
  if [ -z "$slug" ] || [ -z "$lane" ] || [ "${#globs[@]}" -eq 0 ]; then
    echo "usage: goal-registry claim <slug> <lane> <glob...>" >&2
    return 64
  fi
  _reg_check_slug "$slug" || return $?
  local dir; dir="$(registry_dir)" || return $?
  mkdir -p "$dir"

  # Gate this goal's declared globs against every active registered goal.
  local collision
  collision="$(_reg_first_collision "$slug" "${globs[*]}")"
  if [ -n "$collision" ]; then
    echo "REFUSED: goal '$slug' overlaps running goal '$collision' (declared globs not disjoint). Serialize or repick." >&2
    return 1
  fi

  # Write my record. Single-writer: only this session writes <slug>.goal.
  local now branch worktree
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  worktree="$(git rev-parse --show-toplevel 2>/dev/null || echo '?')"
  {
    printf 'slug=%s\n' "$slug"
    printf 'lane=%s\n' "$lane"
    printf 'status=running\n'
    printf 'branch=%s\n' "$branch"
    printf 'worktree=%s\n' "$worktree"
    printf 'touches=%s\n' "${globs[*]}"
    printf 'started=%s\n' "$now"
    printf 'updated=%s\n' "$now"
  } > "$dir/$slug.goal"

  # Last-writer-loud re-read (SPEC-036 edge case 1): if a conflicting active goal
  # appeared between the gate and the write, back out and fail loud.
  collision="$(_reg_first_collision "$slug" "${globs[*]}")"
  if [ -n "$collision" ]; then
    rm -f "$dir/$slug.goal"
    echo "REFUSED (race): goal '$slug' overlaps '$collision' on re-read; re-run." >&2
    return 1
  fi

  echo "CLAIMED $slug (lane=$lane)"
}

reg_list() {
  local dir; dir="$(registry_dir)" || return $?
  local files=()
  [ -d "$dir" ] && files=("$dir"/*.goal)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "(no running goals)"
    return 0
  fi
  printf '%-22s %-9s %-9s %-22s %s\n' SLUG LANE STATUS BRANCH STARTED
  local f
  for f in "${files[@]}"; do
    printf '%-22s %-9s %-9s %-22s %s\n' \
      "$(reg_get "$f" slug)" \
      "$(reg_get "$f" lane)" \
      "$(reg_get "$f" status)" \
      "$(reg_get "$f" branch)" \
      "$(reg_get "$f" started)"
  done
}

reg_log() {
  local slug="${1:-}"; shift 2>/dev/null || true
  local msg="$*"
  if [ -z "$slug" ] || [ -z "$msg" ]; then
    echo "usage: goal-registry log <slug> <message...>" >&2
    return 64
  fi
  _reg_check_slug "$slug" || return $?
  local dir; dir="$(registry_dir)" || return $?
  mkdir -p "$dir"
  printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$dir/$slug.attempts"
}

reg_status() {
  local slug="${1:-}" new="${2:-}"
  if [ -z "$slug" ] || [ -z "$new" ]; then
    echo "usage: goal-registry status <slug> <state>" >&2
    return 64
  fi
  _reg_check_slug "$slug" || return $?
  local dir; dir="$(registry_dir)" || return $?
  local file="$dir/$slug.goal"
  [ -f "$file" ] || { echo "goal-registry: no such goal '$slug'" >&2; return 1; }
  local now tmp; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; tmp="$file.tmp.$$"
  awk -F= -v s="$new" -v u="$now" '
    $1=="status"  {print "status=" s; next}
    $1=="updated" {print "updated=" u; next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  echo "STATUS $slug -> $new"
}

reg_release() {
  local slug="${1:-}"
  [ -n "$slug" ] || { echo "usage: goal-registry release <slug>" >&2; return 64; }
  _reg_check_slug "$slug" || return $?
  local dir; dir="$(registry_dir)" || return $?
  rm -f "$dir/$slug.goal" "$dir/$slug.attempts"
  echo "RELEASED $slug"
}

# --- dispatch ---------------------------------------------------------------

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    claim)   reg_claim "$@";;
    list)    reg_list "$@";;
    log)     reg_log "$@";;
    status)  reg_status "$@";;
    release) reg_release "$@";;
    dir)     registry_dir;;
    *) echo "usage: goal-registry.sh {claim|list|log|status|release|dir} ..." >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
