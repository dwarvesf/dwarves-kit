#!/bin/bash
# mirror leg: the git->Hermes kanban bridge rides every sweep tick instead of
# getting its own timer. `board sweep` runs it after the per-repo syncs as
# `"$BASH" <this script>` (lib/adapters/README.md, legs); it reads the sweep's
# env (SWEEP_*, KIT_LIB) and the MIRROR_* values of the sweep-opt rows.
#
# It is one-way (git->Hermes) and idempotent (an unchanged row is a no-op), so
# re-running it on a cadence costs nothing extra. `--registry`/`--snapshot` are
# passed explicitly so the leg is correct under launchd's arbitrary cwd, not
# just an interactive shell. Observational: it prints its own `mirror rc=<n>`
# line and exits 0 whatever `board mirror` returned; a mirror failure never
# flips the sweep's exit code. Skips cleanly when the `hermes` CLI is absent.
#
# HERMES_HOME is pinned by --mirror-hermes-home. Left unset, the kit's
# env-agnostic `hermes kanban` calls fall back to the CLI's default `~/.hermes`,
# a home no running agent binds to. The snapshot is keyed per store: switching
# homes with the old snapshot would read every row as already-mirrored and mint
# nothing.
#
# Its result goes to the health state from an EXIT trap, only on a normal end
# (exit 0 after the result line). A leg that dies before it has a result leaves
# no record, and the runner records the failure for it.
set -u

BOARDS="$SWEEP_BOARDS"
BOARD_CMD="$SWEEP_BOARD_CMD"
REPO_ROOT="$SWEEP_REPO_ROOT"
DRY_RUN="$SWEEP_DRY_RUN"
HEALTH_BIN="$SWEEP_HEALTH_BIN"
HEALTH_STATE="$SWEEP_HEALTH_STATE"
MIRROR_HERMES_HOME="${MIRROR_HERMES_HOME:-}"
MIRROR_SNAPSHOT="${MIRROR_SNAPSHOT:-}"
[ -n "$MIRROR_SNAPSHOT" ] || MIRROR_SNAPSHOT="$REPO_ROOT/_meta/.board-mirror-snapshot.jsonl"

# Feeds the mirror below. `board mirror` reads each registry row's
# BACKLOG.md straight off disk, so a checkout that lags origin or sits dirty
# mid-branch leaks stale rows into the Hermes board. This rewrites a temp copy
# of the registry so every bridge=on row points at a fresh
# `git show origin/<default>:<path>` snapshot instead of the working-tree file.
# The snapshot is written INSIDE the repo's own root (never an external tmpdir)
# so _repo_root_for still resolves the real repo root and mega-goal extraction
# (_meta/megagoals/*/ROADMAP.md) keeps working; every path written is appended
# to snap_list so the caller can move it back out after the mirror run.
#
# Dropping an unresolved repo's row from the registry does NOT "hold its cards":
# board-mirror.sh's own `plan` treats any prior origin missing from the CURRENT
# extract as removed and ARCHIVEs its card, so one failed fetch would close
# every active card from that repo, and a later good tick would re-create them
# from scratch. This function still records every unresolvable repo's name in
# `failed_list` (4th arg) and drops only that repo's OWN row from `out`, but the
# row-drop is not the safety mechanism: the caller refuses to invoke `board
# mirror` at all for a tick where `failed_list` is non-empty, so a partial
# registry is never fed to the planner. Every drop is a `>&2` line so it lands
# in the sweep's own log, once per repo per tick.
build_origin_mirror_registry() {
  local src="$1" out="$2" snap_list="$3" failed_list="$4"
  : > "$out"
  local line name path bridge rest root relpath prefix base dir branch snap n
  while IFS= read -r line; do
    set -- $line
    name="${1:-}"; path="${2:-}"; bridge="${3:-}"
    case "$name" in ''|\#*) printf '%s\n' "$line" >> "$out"; continue ;; esac
    if [ "$bridge" != "on" ]; then
      printf '%s\n' "$line" >> "$out"
      continue
    fi
    n=$#
    if [ "$n" -gt 3 ]; then shift 3; else shift "$n"; fi
    rest="$*"
    path="${path/#\~/$HOME}"
    dir="$(dirname "$path")"
    root="$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
    if [ -z "$root" ]; then
      echo "  mirror-origin: drop $name (not a git repo at $path)" >&2
      printf '%s\n' "$name" >> "$failed_list"
      continue
    fi
    # show-prefix (not string-stripping $root off $path): macOS resolves
    # $TMPDIR-style paths through a /private symlink, so --show-toplevel's
    # resolved root and the registry's un-resolved $path never share a
    # literal prefix to strip, and letting git compute the repo-relative path
    # from the same cwd sidesteps that entirely.
    prefix="$(cd "$dir" 2>/dev/null && git rev-parse --show-prefix 2>/dev/null)"
    base="$(basename "$path")"
    relpath="${prefix}${base}"
    if ! git -C "$root" fetch origin --quiet 2>/dev/null; then
      echo "  mirror-origin: drop $name (git fetch origin failed, common under launchd on an ssh remote -- kept out of this tick rather than serving a stale ref)" >&2
      printf '%s\n' "$name" >> "$failed_list"
      continue
    fi
    git -C "$root" remote set-head origin -a >/dev/null 2>&1
    branch="$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
    branch="${branch#origin/}"
    if [ -z "$branch" ]; then
      git -C "$root" rev-parse --verify -q origin/main >/dev/null 2>&1 && branch=main
    fi
    if [ -z "$branch" ]; then
      git -C "$root" rev-parse --verify -q origin/master >/dev/null 2>&1 && branch=master
    fi
    if [ -z "$branch" ]; then
      echo "  mirror-origin: drop $name (no resolvable default branch)" >&2
      printf '%s\n' "$name" >> "$failed_list"
      continue
    fi
    snap="$root/.board-mirror-origin.$name.$$.md"
    # register for cleanup BEFORE the attempt: `> "$snap"` creates the file
    # the instant the redirection opens, even when `git show` itself fails,
    # so an unreadable blob must not leave a stray empty file at repo root
    printf '%s\n' "$snap" >> "$snap_list"
    if git -C "$root" show "origin/$branch:$relpath" > "$snap" 2>/dev/null; then
      printf '%s %s %s %s\n' "$name" "$snap" "$bridge" "$rest" >> "$out"
    else
      echo "  mirror-origin: drop $name (origin/$branch:$relpath unreadable)" >&2
      printf '%s\n' "$name" >> "$failed_list"
      continue
    fi
  done < "$src"
}

MIRROR_RESULT_RC=""
MIRROR_RESULT_TEXT=""

if [ -n "$MIRROR_HERMES_HOME" ]; then
  if command -v hermes >/dev/null 2>&1; then
    MIRROR_REGISTRY="$(mktemp "${TMPDIR:-/tmp}/board-mirror-registry.XXXXXX")"
    MIRROR_SNAP_LIST="$(mktemp "${TMPDIR:-/tmp}/board-mirror-snaps.XXXXXX")"
    MIRROR_FAILED="$(mktemp "${TMPDIR:-/tmp}/board-mirror-failed.XXXXXX")"
    MIRROR_DISCARD="$(mktemp -d "${TMPDIR:-/tmp}/board-mirror-discard.XXXXXX")"
    # BEGIN mirror-cleanup-trap (extracted verbatim by
    # tests/test-board-sweep-mirror.sh's trap case)
    #
    # A killed run (launchd timeout, a crash mid `git show`) must not leave an
    # origin-BACKLOG.md copy sitting untracked at a repo root, where a later
    # `git add -A` on that checkout could commit it. mirror_cleanup moves every
    # path build_origin_mirror_registry recorded (per-repo snapshots), plus this
    # tick's own registry/snap-list/failed temp files, into MIRROR_DISCARD; it
    # is idempotent (a file already moved is just a no-op `[ -f ]` miss on the
    # retry), so wiring it to both the normal path and EXIT/INT/TERM is safe to
    # double-fire.
    mirror_cleanup() {
      local f
      if [ -f "${MIRROR_SNAP_LIST:-}" ]; then
        while IFS= read -r f; do
          [ -n "$f" ] && [ -f "$f" ] && mv -f "$f" "$MIRROR_DISCARD/" 2>/dev/null
        done < "$MIRROR_SNAP_LIST"
        mv -f "$MIRROR_SNAP_LIST" "$MIRROR_DISCARD/" 2>/dev/null
      fi
      [ -f "${MIRROR_REGISTRY:-}" ] && mv -f "$MIRROR_REGISTRY" "$MIRROR_DISCARD/" 2>/dev/null
      [ -f "${MIRROR_FAILED:-}" ] && mv -f "$MIRROR_FAILED" "$MIRROR_DISCARD/" 2>/dev/null
    }
    trap 'mirror_cleanup' EXIT
    trap 'mirror_cleanup; exit 130' INT
    trap 'mirror_cleanup; exit 143' TERM
    # END mirror-cleanup-trap
    # The EXIT trap above also records the result. It records on a normal end
    # only (status 0 with a result set), so a crash or a signal records nothing
    # here and the runner's fallback marks the leg failed.
    mirror_exit() {
      local status=$?
      mirror_cleanup
      if [ "$status" -eq 0 ] && [ -n "$MIRROR_RESULT_RC" ]; then
        printf '%s\n' "$MIRROR_RESULT_TEXT" | python3 "$HEALTH_BIN" record --leg mirror --rc "$MIRROR_RESULT_RC" --health-state-file "$HEALTH_STATE" 2>&1 | sed 's/^/    /'
      fi
    }
    trap 'mirror_exit' EXIT
    build_origin_mirror_registry "$BOARDS" "$MIRROR_REGISTRY" "$MIRROR_SNAP_LIST" "$MIRROR_FAILED"
    if [ -s "$MIRROR_FAILED" ]; then
      # board-mirror.sh's `plan` ARCHIVEs any prior origin missing from the
      # CURRENT extract, so feeding it a registry with even one repo silently
      # dropped would close every one of that repo's active cards in Hermes,
      # then a later good tick would re-create them from scratch. Refuse the
      # whole `board mirror` call for this tick instead: every OTHER leg (sync,
      # digest, publish, preflight) keeps running unaffected, and the next tick
      # retries the mirror from scratch once the repo resolves again.
      failed_names="$(tr '\n' ',' < "$MIRROR_FAILED" | sed 's/,$//')"
      echo "  mirror skipped this tick: $failed_names unresolved -- retrying next tick"
      MIRROR_RESULT_RC=0
      MIRROR_RESULT_TEXT="mirror skipped: $failed_names unresolved"
    else
      mirror_flags=()
      [ "$DRY_RUN" -eq 1 ] && mirror_flags+=(--dry-run)
      mout="$(HERMES_HOME="$MIRROR_HERMES_HOME" "$BOARD_CMD" mirror --repo-root "$REPO_ROOT" --registry "$MIRROR_REGISTRY" --snapshot "$MIRROR_SNAPSHOT" ${mirror_flags[@]+"${mirror_flags[@]}"} 2>&1)"; mrc=$?
      echo "  mirror rc=$mrc (home=$MIRROR_HERMES_HOME)"
      printf '%s\n' "$mout" | sed 's/^/    /'
      MIRROR_RESULT_RC="$mrc"
      MIRROR_RESULT_TEXT="$mout"
    fi
    mirror_cleanup
  else
    echo "  mirror skipped: hermes CLI not on PATH"
  fi
fi
exit 0
