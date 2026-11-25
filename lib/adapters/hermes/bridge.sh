#!/bin/bash
# bridge.sh -- the `board mirror`, `board status` and `board writeback` verbs, the git to Hermes kanban bridge's
# read-mirror, staleness and writeback legs. The manifest (adapter.tsv) maps each verb to this script with the
# verb as its first argument (`verb mirror bridge.sh mirror`), and `board.sh` runs it with the caller's flags
# after that. The heavy logic lives in board-mirror.sh (extract, diff, plan, apply) and board-writeback.sh
# (diff, validate, apply, PR) beside this file; this file resolves config, runs them and prints the summary.
#
# Moved out of lib/board/board.sh without a change to the functions below: same flags, same output, same exit
# codes. KIT_LIB comes from this file's own location and never from the environment, so a stale or hostile
# inherited value redirects nothing and a direct call works.
set -euo pipefail

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"  # physical: the adapter directory may be a symlink
KIT_LIB="$(cd "$BRIDGE_DIR/../.." && pwd)"  # lib/, two levels up; script-local, never read from the environment
export KIT_LIB
BOARD_MIRROR_SH="$BRIDGE_DIR/board-mirror.sh"
BOARD_WRITEBACK_SH="$BRIDGE_DIR/board-writeback.sh"
# shellcheck source=../../board/board-lib.sh
. "$KIT_LIB/board/board-lib.sh" || exit 1

# ---------------------------------------------------------------------------
# mirror -- git<->Hermes kanban bridge, read-mirror leg.
# Delegates ALL substantial logic (extract/diff/plan/apply) to board-mirror.sh, exactly the
# way `board queue` delegates parsing to lib/board/parse-board.sh; this function is the thin,
# human-facing wrapper: resolve config, get a plan, apply it (locally or over one `ssh` call),
# persist the snapshot incrementally as results stream back, print a summary. Never mutates any
# BACKLOG.md (mirror is one-way: git -> Hermes; writeback owns the reverse leg).
# ---------------------------------------------------------------------------
cmd_mirror() {
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-${KIT_BOARDS_REGISTRY:-$repo_root/_meta/boards.txt}}"
  local snapshot="${OPT_SNAPSHOT:-$repo_root/_meta/.board-mirror-snapshot.jsonl}"

  _legacy_bridge_note
  [ -f "$registry" ] || { echo "mirror: no registry at $registry" >&2; return 1; }

  local plan_args=(plan --registry "$registry" --snapshot "$snapshot")
  [ -n "$OPT_MEGA_BOARD" ]   && plan_args+=(--mega-board "$OPT_MEGA_BOARD")
  [ -n "$OPT_BOARD_PREFIX" ] && plan_args+=(--board-prefix "$OPT_BOARD_PREFIX")

  local plan; plan="$(mktemp "${TMPDIR:-/tmp}/board-mirror-plan.XXXXXX")"
  bash "$BOARD_MIRROR_SH" "${plan_args[@]}" > "$plan"

  if [ "$OPT_DRY_RUN" -eq 1 ]; then
    cat "$plan"
    rm -f "$plan"
    return 0
  fi

  if [ ! -s "$plan" ]; then
    echo "mirror: 0 changes" >&2
    rm -f "$plan"
    return 0
  fi

  local results
  if [ -n "$OPT_REMOTE" ]; then
    # ONE ssh call: the remote host execs its OWN copy of board-mirror.sh's apply-plan (argv
    # vectors decoded from the piped plan JSON, never a templated shell string -- card text stays
    # opaque data end to end). The remote host is expected to already have a dwarves-kit checkout
    # reachable at --remote-kit-path (default matches the existing DWARVES_KIT convention used by
    # ops-toolkit's own board-all shim); provisioning that checkout is a separate, later step.
    local remote_kit="${OPT_REMOTE_KIT_PATH:-\$HOME/.claude/dwarves-kit}"
    # shellcheck disable=SC2029  # intentional: ${remote_kit} expands client-side (it names the
    # remote path as a local variable); the remote command itself has no other variables to expand.
    results="$(ssh "$OPT_REMOTE" "bash ${remote_kit}/lib/adapters/hermes/board-mirror.sh apply-plan" < "$plan")"
  else
    results="$(bash "$BOARD_MIRROR_SH" apply-plan < "$plan")"
  fi
  rm -f "$plan"

  local created=0 changed=0 moved=0 archived=0 errors=0
  local rline op origin hermes_id hermes_status status err
  while IFS= read -r rline; do
    [ -n "$rline" ] || continue
    status="$(printf '%s' "$rline" | jq -r '.status')"
    origin="$(printf '%s' "$rline" | jq -r '.origin')"
    op="$(printf '%s' "$rline" | jq -r '.op')"
    if [ "$status" != "ok" ]; then
      errors=$((errors+1))
      err="$(printf '%s' "$rline" | jq -r '.error // empty')"
      echo "mirror: ERROR $origin ($op): $err" >&2
      continue
    fi
    case "$op" in
      create)  created=$((created+1)) ;;
      change)  changed=$((changed+1)) ;;
      move)    moved=$((moved+1)) ;;
      archive) archived=$((archived+1)) ;;
    esac
    hermes_id="$(printf '%s' "$rline" | jq -r '.hermes_id')"
    hermes_status="$(printf '%s' "$rline" | jq -r '.hermes_status')"
    echo "mirror: ${op} ${origin} -> ${hermes_id} (${hermes_status})" >&2
    # Persisted PER LINE, as results arrive (a mid-sync crash never loses a completed row).
    printf '%s' "$rline" | bash "$BOARD_MIRROR_SH" snapshot-upsert "$snapshot"
  done <<< "$results"

  echo "mirror: applied ${created} create, ${changed} change, ${moved} move, ${archived} archive, ${errors} error(s)" >&2
  [ "$errors" -eq 0 ]
}

# ---------------------------------------------------------------------------
# status -- mirror staleness report. Compares the snapshot's newest `seen_at` per
# opted-in repo against that repo's BACKLOG.md's own last git-log touch time; never touches
# Hermes or the snapshot file (read-only).
# ---------------------------------------------------------------------------
cmd_status() {
  _legacy_bridge_note
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-${KIT_BOARDS_REGISTRY:-$repo_root/_meta/boards.txt}}"
  local snapshot="${OPT_SNAPSHOT:-$repo_root/_meta/.board-mirror-snapshot.jsonl}"
  [ -f "$registry" ] || { echo "status: no registry at $registry" >&2; return 1; }

  local snap_tsv; snap_tsv="$(mktemp "${TMPDIR:-/tmp}/board-mirror-status.XXXXXX")"
  bash "$BOARD_MIRROR_SH" snapshot-read "$snapshot" > "$snap_tsv"

  local name path bridge rroot last_mirror last_touch changed=0 total_bridged=0 newest=""
  while read -r name path bridge _rest; do  # _rest: a 4th column (rail=) must not slurp into bridge
    [ -n "${name:-}" ] || continue
    case "$name" in \#*) continue ;; esac
    [ "${bridge:-}" = "on" ] || continue
    total_bridged=$((total_bridged+1))
    path="${path/#\~/$HOME}"
    if [ ! -f "$path" ]; then
      echo "status: ${name}: never mirrored (BACKLOG.md missing at $path)" >&2
      changed=$((changed+1))
      continue
    fi
    rroot="$(_repo_root_for "$path")"
    # Match by ORIGIN prefix ("<repo>:"), not by recorded board name: the board name can carry a
    # --board-prefix the registry's repo name never does, so origin is the robust join key.
    last_mirror="$(awk -F'\t' -v r="${name}:" 'index($1, r)==1{print $6}' "$snap_tsv" | sort | tail -n1)"
    last_touch="$(git -C "$rroot" log -1 --format=%cI -- "$path" 2>/dev/null || true)"
    [ -n "$last_touch" ] && last_touch="$(_iso_to_utc_z "$last_touch")"
    if [ -n "$last_mirror" ] && [ -n "$newest" ] && [ "$last_mirror" '>' "$newest" ]; then newest="$last_mirror"; fi
    [ -z "$newest" ] && [ -n "$last_mirror" ] && newest="$last_mirror"
    if [ -z "$last_mirror" ]; then
      echo "status: ${name}: never mirrored" >&2
      changed=$((changed+1))
    elif [ -n "$last_touch" ] && [ "$last_touch" '>' "$last_mirror" ]; then
      echo "status: ${name}: changed since last mirror (touched ${last_touch}, mirrored ${last_mirror})" >&2
      changed=$((changed+1))
    else
      echo "status: ${name}: up to date (mirrored ${last_mirror})" >&2
    fi
  done < "$registry"
  rm -f "$snap_tsv"

  echo "${changed} repos changed since last mirror, last synced ${newest:-never}"

  # --with-mega (OPT-IN, kit-modularity sub-goal 08): a trailing MEGA ROLLUP section, one line
  # per ACTIVE mega per registry repo. Off by default (real `gh` calls per sub-goal; must never
  # fire inside test-board-mirror.sh's fixture registry, which never passes this flag).
  if [ "$OPT_WITH_MEGA" -eq 1 ]; then
    echo ""
    echo "MEGA ROLLUP:"
    while read -r name path _rest; do
      [ -n "${name:-}" ] || continue
      case "$name" in \#*) continue ;; esac
      path="${path/#\~/$HOME}"
      [ -f "$path" ] || continue
      local mrepo_root mcode_root mrollups
      mrepo_root="$(_repo_root_for "$path")"
      mcode_root="${OPT_MEGA_CODE_ROOT:-$mrepo_root}"
      mrollups="$(_mega_rollups "$mrepo_root" "$mcode_root")"
      [ -n "$mrollups" ] && printf '%s\n' "$mrollups"
    done < "$registry"
  fi
}

# ---------------------------------------------------------------------------
# writeback -- git<->Hermes bridge, the WRITEBACK leg.
# Delegates ALL substantial logic (diff/validate/apply/PR) to board-writeback.sh, the same
# thin-wrapper shape `mirror` above has with board-mirror.sh: resolve config, get a validated
# changeset, apply it (branch+commit+push+PR per affected repo), refresh the snapshot per applied
# origin, print a summary. `--dry-run` computes the changeset (which DOES read Hermes -- that read
# is exactly what a preview needs) but applies nothing: no branch, no commit, no push, no PR, no
# snapshot write.
# ---------------------------------------------------------------------------
cmd_writeback() {
  _legacy_bridge_note
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-${KIT_BOARDS_REGISTRY:-$repo_root/_meta/boards.txt}}"
  local snapshot="${OPT_SNAPSHOT:-$repo_root/_meta/.board-mirror-snapshot.jsonl}"
  local branch="${OPT_BRANCH:-chore/board-sync}"
  [ -f "$registry" ] || { echo "writeback: no registry at $registry" >&2; return 1; }

  local diff_args=(diff --registry "$registry" --snapshot "$snapshot")
  [ -n "$OPT_BOARD_PREFIX" ] && diff_args+=(--board-prefix "$OPT_BOARD_PREFIX")

  local changeset; changeset="$(mktemp "${TMPDIR:-/tmp}/board-writeback-plan.XXXXXX")"
  # `if cmd; then rc=0; else rc=$?; fi` (NOT `if ! cmd; then rc=$?; fi`): bash sets `$?` to the
  # NEGATED (`!`-inverted) status inside an `if ! cmd; then` block, not cmd's own exit code (a real
  # bug this build's own smoke test caught -- `rc` always read back as 0). This is the same
  # command-substitution/exit-code gotcha board-mirror.sh's `cmd_apply_plan` already documents
  # for its own `if out=$(...); then rc=0; else rc=$?; fi` pattern.
  local rc
  if bash "$BOARD_WRITEBACK_SH" "${diff_args[@]}" > "$changeset"; then rc=0; else rc=$?; fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$changeset"
    return "$rc"
  fi

  if [ ! -s "$changeset" ]; then
    echo "writeback: 0 changes" >&2
    rm -f "$changeset"
    return 0
  fi

  if [ "$OPT_DRY_RUN" -eq 1 ]; then
    cat "$changeset"
    rm -f "$changeset"
    return 0
  fi

  local apply_args=(apply --branch "$branch")
  [ -n "$OPT_PR_BASE" ] && apply_args+=(--pr-base "$OPT_PR_BASE")

  local results
  results="$(bash "$BOARD_WRITEBACK_SH" "${apply_args[@]}" < "$changeset")"
  rm -f "$changeset"

  local rline
  while IFS= read -r rline; do
    [ -n "$rline" ] || continue
    printf '%s' "$rline" | bash "$BOARD_MIRROR_SH" snapshot-upsert "$snapshot"
  done <<< "$results"

  return 0
}

# mirror/status/writeback run one engine, the cockpit bridge (board-mirror.sh and
# board-writeback.sh). The per-repo spoke sync is a separate job: `board sync`.
_legacy_bridge_note() {
  echo "note: mirror/status/writeback are the cockpit bridge engine (board-mirror.sh);" >&2
  echo "      the per-repo spoke sync is \`board sync\`, a separate engine." >&2
}

main() {
  local verb="${1:-}"
  [ $# -eq 0 ] || shift
  case "$verb" in
    mirror) cmd_mirror "$@" ;;
    status) cmd_status "$@" ;;
    writeback) cmd_writeback "$@" ;;
    *) echo "bridge.sh: unknown verb '$verb' (mirror|status|writeback)" >&2; return 64 ;;
  esac
}

main "$@"
