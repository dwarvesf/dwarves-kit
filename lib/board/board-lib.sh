#!/bin/bash
# board-lib.sh -- helpers shared by board.sh and by the verb scripts it runs (flag parsing, repo-root
# resolution, the mega rollup, the ISO-to-UTC conversion). Sourced, never executed. The caller sets
# KIT_LIB (the absolute lib/ directory) first; the mega paths derive from it.

: "${KIT_LIB:?board-lib.sh: KIT_LIB must be set before sourcing}"
MEGA_SH="$KIT_LIB/mega/mega.sh"  # lib/mega/mega.sh
# shellcheck source=../mega/box.sh
. "$KIT_LIB/mega/box.sh" || exit 1

# ---------------------------------------------------------------------------
# Flag parsing (shared): extracts --backlog-file / --repo-root / --registry / --dry-run plus the
# mirror-only flags (--snapshot / --mega-board / --board-prefix / --remote / --remote-kit-path)
# from anywhere in argv, leaving the rest in POSITIONAL in order. Re-callable per subcommand (each
# resets its own OPT_* vars first). The mirror-only flags are harmless no-ops for every OTHER
# subcommand (board/next/set/states/priority/all/queue never read them), so folding them into the
# one shared parser costs nothing and keeps a single flag-parsing surface (by design).
# ---------------------------------------------------------------------------
OPT_BACKLOG_FILE=""; OPT_REPO_ROOT=""; OPT_REGISTRY=""; OPT_DRY_RUN=0
OPT_SNAPSHOT=""; OPT_MEGA_BOARD=""; OPT_BOARD_PREFIX=""; OPT_REMOTE=""; OPT_REMOTE_KIT_PATH=""
OPT_BRANCH=""; OPT_PR_BASE=""; OPT_WITH_MEGA=0; OPT_MEGA_CODE_ROOT=""
POSITIONAL=()
_parse_flags() {
  OPT_BACKLOG_FILE=""; OPT_REPO_ROOT=""; OPT_REGISTRY=""; OPT_DRY_RUN=0
  OPT_SNAPSHOT=""; OPT_MEGA_BOARD=""; OPT_BOARD_PREFIX=""; OPT_REMOTE=""; OPT_REMOTE_KIT_PATH=""
  OPT_BRANCH=""; OPT_PR_BASE=""; OPT_WITH_MEGA=0; OPT_MEGA_CODE_ROOT=""
  POSITIONAL=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --backlog-file)    OPT_BACKLOG_FILE="${2:-}"; shift 2 ;;
      --repo-root)       OPT_REPO_ROOT="${2:-}"; shift 2 ;;
      --registry)        OPT_REGISTRY="${2:-}"; shift 2 ;;
      --dry-run)         OPT_DRY_RUN=1; shift ;;
      --snapshot)        OPT_SNAPSHOT="${2:-}"; shift 2 ;;
      --mega-board)      OPT_MEGA_BOARD="${2:-}"; shift 2 ;;
      --board-prefix)    OPT_BOARD_PREFIX="${2:-}"; shift 2 ;;
      --remote)          OPT_REMOTE="${2:-}"; shift 2 ;;
      --remote-kit-path) OPT_REMOTE_KIT_PATH="${2:-}"; shift 2 ;;
      --branch)          OPT_BRANCH="${2:-}"; shift 2 ;;
      --pr-base)         OPT_PR_BASE="${2:-}"; shift 2 ;;
      --with-mega)       OPT_WITH_MEGA=1; shift ;;
      --mega-code-root)  OPT_MEGA_CODE_ROOT="${2:-}"; shift 2 ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
  done
}

# _mega_rollups <repo-root> <code-root> -- one `mega status <slug> --rollup-only` line per
# ACTIVE mega under <repo-root>/_meta/megagoals/*/ROADMAP.md (>=1 open sub-goal box, same
# activeness convention lib/board/board-mirror.sh's own extract_megas already uses). Silent no-op
# (empty output) when there is no megagoals dir, no mega.sh, or a mega's status call errors --
# this is an OPT-IN surfacing feature (--with-mega), never a hard requirement of board render.
_mega_rollups() {  # <repo-root> <code-root>
  local repo_root="$1" code_root="$2" mg_root dir slug rf out
  mg_root="$repo_root/_meta/megagoals"
  [ -d "$mg_root" ] || return 0
  [ -f "$MEGA_SH" ] || return 0
  for dir in "$mg_root"/*/; do
    [ -d "$dir" ] || continue
    slug="$(basename "$dir")"
    rf="$dir/ROADMAP.md"
    [ -f "$rf" ] || continue
    grep -qE "^$(box_re open)" "$rf" 2>/dev/null || continue   # skip fully-shipped / parked-only / non-checkbox megas
    out="$(bash "$MEGA_SH" status "$slug" --megagoals-root "$mg_root" --code-root "$code_root" --rollup-only 2>/dev/null)" || true
    [ -n "$out" ] && printf '  %s\n' "$out"
  done
}

_default_repo_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

_resolve_repo_root() {
  if [ -n "$OPT_REPO_ROOT" ]; then printf '%s\n' "$OPT_REPO_ROOT"; return; fi
  if [ -n "${REPO_ROOT:-}" ]; then printf '%s\n' "$REPO_ROOT"; return; fi
  _default_repo_root
}

# _repo_root_for <path-to-backlog-md> -- the git top-level containing that file, else its dir.
_repo_root_for() {
  local dir; dir="$(cd "$(dirname "$1")" && pwd)"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$dir"
}

# _iso_to_utc_z <ISO8601-with-offset> -- normalizes `git log --format=%cI`'s local-offset
# timestamp ("2026-07-05T04:42:21+07:00") to a UTC "Z" timestamp, so `status`'s string
# comparison against the snapshot's own UTC `seen_at` values is an apples-to-apples same-instant
# check, not a same-INSTANT-but-different-clock-face false positive. BSD `date -j -f '...%z'`
# (macOS) requires the offset WITHOUT a colon ("+0700"); git's ISO8601 format always has one, so
# it is stripped before parsing (verified empirically: BSD date rejects "+07:00" outright and,
# with `set -e` off, silently falls through, which is exactly the false-positive this function
# exists to prevent). GNU `date -d` (Linux/CI) accepts the colon form natively and is tried as a
# second path. If BOTH conversions fail, the original string is returned unmodified rather than
# aborting `status` (an honestly-imprecise staleness read beats no read at all).
_iso_to_utc_z() {
  local raw="$1" nocolon
  nocolon="$(printf '%s' "$raw" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')"
  date -u -j -f '%Y-%m-%dT%H:%M:%S%z' "$nocolon" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "$raw" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf '%s\n' "$raw"
}
