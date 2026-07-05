#!/usr/bin/env bash
# board-writeback.sh -- git<->Hermes kanban bridge, the WRITEBACK leg (SPEC-149, runner-fastpath
# sub-goal 08). Consumes SPEC-147's mirror snapshot as its bearing surface; reuses
# lib/board-mirror.sh's extract/hash/native-state machinery by SOURCING it (not re-forking),
# the same delegation discipline board-mirror.sh itself uses for lib/parse-board.sh.
#
# v1 scope (per the sub-goal contract): STATUS MOVES ONLY, BACKLOG.md rows only (no mega-goal
# cards, no new-card writeback, no note edits). A Hermes-side card move applies to git ONLY if the
# row's row_hash still equals the value recorded at mirror time -- otherwise the edit is SKIPPED,
# reported, and the row is left for the next `board mirror` run to refresh from git (CONFLICT
# RULE, load-bearing: git wins, always). Every apply lands on a fresh `chore/board-sync` branch
# (built in an ISOLATED `git worktree`, never the caller's own checkout -- see "Why a worktree"
# below) as one attributed commit (`actor=hermes` in the body), pushed, and opened as a HELD PR via
# `gh pr create` (never auto-merged by this tool). NO direct BACKLOG.md write ever happens on the
# caller's own working tree or branch.
#
# Subcommands (internal plumbing; `board.sh writeback` is the human-facing surface):
#   reverse-native <hermes-status>                              -> git target status on stdout,
#                                                                    or empty + exit 1 if unmapped
#   diff --registry <path> --snapshot <path> [--board-prefix <p>]
#                                                                -> NDJSON changeset (one line per
#                                                                    VALID, applyable row) on
#                                                                    stdout; summary + every skip
#                                                                    reason to stderr. Missing OR
#                                                                    corrupt --snapshot REFUSES
#                                                                    ALL edits: prints an explicit
#                                                                    error, exits nonzero, emits
#                                                                    ZERO stdout (never degrades to
#                                                                    "no conflicts, apply
#                                                                    everything" -- this guard is
#                                                                    the whole reason this design
#                                                                    exists).
#   apply [--branch <name>] [--pr-base <branch>]                -> reads the NDJSON changeset on
#                                                                    stdin, groups by
#                                                                    (repo_root, backlog_file),
#                                                                    and for each group with >=1
#                                                                    row: worktree+branch+edit+
#                                                                    commit+push+`gh pr create`.
#                                                                    Emits one NDJSON
#                                                                    "board-mirror.sh
#                                                                    snapshot-upsert"-SHAPED result
#                                                                    line per applied origin on
#                                                                    stdout (see "Snapshot refresh"
#                                                                    below), and one summary line
#                                                                    per repo group to stderr.
#
# Changeset format (one NDJSON object per row `diff` validated):
#   {"origin":"ops-toolkit:ID-042","repo":"ops-toolkit","id":"ID-042","hermes_id":"t_...",
#    "board":"ops-toolkit","backlog_file":"/abs/path/_meta/BACKLOG.md","repo_root":"/abs/path",
#    "current_status":"queued","target_status":"claimed","hermes_status":"ready",
#    "row_hash":"<sha256, PASSED THROUGH from the snapshot, unchanged>"}
# `row_hash` here is NOT recomputed from the (future, post-merge) target status -- it is the
# EXISTING value the mirror snapshot already recorded for this origin, carried through unchanged.
# See "Snapshot refresh" below for why.
#
# Reverse state mapping (git target status <- Hermes live native status). The FORWARD map
# (board-mirror.sh's `_target_native`) is many-to-one (claimed/speccing/validated/executing all
# collapse to `ready`), so the reverse cannot recover the original git-side nuance -- this is a
# DOCUMENTED, ACCEPTED lossy mapping, not a bug:
#   triage  -> queued   (the exact inverse; triage is 1:1 with queued on the forward map too)
#   ready   -> claimed  (the honest nearest-available "picked up" state -- NOT speccing/validated/
#                        executing; a writeback cannot know which of those four the operator
#                        "meant", and `claimed` is the least presumptuous of the four)
#   blocked -> parked   (the exact inverse; parked is 1:1 with blocked on the forward map too)
#   done    -> shipped  (the safe default over `dropped`: a card marked done in Hermes is read as
#                        "finished", not "abandoned"; `dropped` has no writeback path in v1)
#   (todo, running, or any other value hermes reports) -> UNMAPPED (empty), rejected as an illegal
#     target status. These two are never write-targets in the forward direction either (see
#     board-mirror.sh's Hermes-CLI-reality header note), so seeing one live would mean either a
#     manual out-of-band Hermes edit or a future CLI/version change -- either way, writeback must
#     not guess, so it refuses that ONE row (not the whole run) with a named reason.
#
# Why a worktree, not the caller's own checkout: the operator's real BACKLOG.md checkout must
# never be silently switched to a `chore/board-sync` branch mid-session, and the sub-goal's own
# worker-hygiene rule (never `git checkout -B`/commit inside a real, non-throwaway checkout for
# anything other than THIS repo's own feature branch) generalizes to the tool's own runtime
# design: `git -C <repo_root> worktree add -B <branch> <scratch-dir> HEAD` builds the sync branch
# from the CURRENT HEAD (resolved fresh at call time, never a cached/stale ref -- this is also
# what keeps a concurrent append-only writer's row safe, see the NC6 test) in a throwaway
# directory, edits/commits/pushes THERE, then removes the worktree. `repo_root`'s own working
# directory and current branch are never touched.
#
# Snapshot refresh (after a successful apply): ONLY `hermes_status` is updated in the snapshot,
# to the live value writeback just observed; `row_hash` is passed through UNCHANGED. This is
# deliberate, not an oversight: the writeback commit lands on a HELD, unmerged PR -- the actual
# git SoT (the default branch the next `board mirror` run reads) has not changed yet. Refreshing
# `hermes_status` stops writeback from re-diffing (and re-PR-ing) the SAME Hermes-side move on a
# second run before the PR merges. Leaving `row_hash` untouched keeps `board mirror`'s own
# idempotence correct: mirror compares the CURRENT git extract's hash against the snapshot's
# row_hash, which still (correctly) reflects the not-yet-merged git content, so mirror does not
# think anything changed until the PR actually merges -- at which point mirror's own normal CHANGE
# path fires once, posts a Hermes comment noting the new content, and upserts the row_hash itself.
# Known limitation (documented, not fixed here -- explicitly out of this sub-goal's scope): if the
# operator instead CLOSES the held PR without merging, the snapshot has already "forgotten" the
# delta (hermes_status now matches live), so writeback will not re-propose it. Recovery requires
# moving the Hermes card again (any further live-status change re-triggers a fresh diff).
#
# GH_BIN overrides the `gh` binary (tests point it at a stub that logs argv and returns a canned
# PR URL; NO real `gh` API call happens in the automated suite or in this sub-goal's own
# fixtures-only round-trip demo, per the sub-goal contract). HERMES_BIN (inherited from
# board-mirror.sh) overrides the `hermes` binary the same way.
set -euo pipefail

BW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOARD_MIRROR_SH="$BW_DIR/board-mirror.sh"
BACKLOG_SH="$BW_DIR/backlog.sh"
[ -f "$BOARD_MIRROR_SH" ] || { echo "board-writeback: lib/board-mirror.sh not found at $BOARD_MIRROR_SH" >&2; exit 1; }
[ -f "$BACKLOG_SH" ]      || { echo "board-writeback: lib/backlog.sh not found at $BACKLOG_SH" >&2; exit 1; }
# shellcheck source=/dev/null
source "$BOARD_MIRROR_SH"

GH_BIN="${GH_BIN:-gh}"

# Legal backlog.sh states, duplicated as a literal list (not shelled out to `backlog.sh states`
# per validation call -- this runs per-row in a diff loop, and the vocabulary is static/small; see
# lib/backlog.sh's own `STATES` for the source of truth this must be kept in sync with).
LEGAL_STATES="queued claimed speccing validated executing shipped parked dropped"
_is_legal_state() {
  case " $LEGAL_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# _reverse_native <hermes-live-status> -- see the header comment's Reverse state mapping table.
# Empty output (+ exit 1) = no legal git target for this Hermes status; the caller rejects the row.
_reverse_native() {
  case "$1" in
    triage)  printf 'queued\n' ;;
    ready)   printf 'claimed\n' ;;
    blocked) printf 'parked\n' ;;
    done)    printf 'shipped\n' ;;
    *)       return 1 ;;
  esac
}

# _wb_skip <origin> <reason> -- uniform skip-log line to stderr (mirrors parse-board.sh's
# `_pb_skip` convention: reasons go to stderr only, never mixed into the stdout NDJSON stream).
_wb_skip() { echo "writeback: skip $1: $2" >&2; }

# ---------------------------------------------------------------------------
# diff -- builds the validated changeset. Never touches git-write or Hermes-write; the ONLY
# Hermes call here is a read (`kanban --board <board> list --json`, once per board).
# ---------------------------------------------------------------------------
cmd_diff() {
  local registry="" snapshot="" board_prefix=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --registry)     registry="$2"; shift 2 ;;
      --snapshot)     snapshot="$2"; shift 2 ;;
      --board-prefix) board_prefix="$2"; shift 2 ;;
      *) echo "diff: unknown flag '$1'" >&2; return 64 ;;
    esac
  done
  [ -n "$registry" ] || { echo "diff: --registry is required" >&2; return 64; }
  [ -f "$registry" ]  || { echo "diff: no registry at $registry" >&2; return 1; }
  [ -n "$snapshot" ]  || { echo "diff: --snapshot is required" >&2; return 64; }

  # --- THE guard: missing or corrupt snapshot refuses ALL edits (NC5). A truly absent snapshot
  # (never mirrored) is an outright refusal, distinct from a PRESENT-but-EMPTY snapshot (a real,
  # valid "zero rows mirrored yet" state, which legitimately produces zero changes below, not a
  # refusal). ---
  if [ ! -f "$snapshot" ]; then
    echo "writeback: REFUSING all edits: no mirror snapshot at $snapshot (never mirrored -- run 'board mirror' first)" >&2
    return 1
  fi
  if [ -s "$snapshot" ] && ! jq -e 'true' "$snapshot" >/dev/null 2>&1; then
    echo "writeback: REFUSING all edits: corrupt mirror snapshot at $snapshot (invalid JSON found)" >&2
    return 1
  fi

  # repo -> "path\tbridge" map, ONLY registry rows (the opted-in source of truth `diff` checks
  # every row against below -- defense in depth on top of board-mirror.sh's own mirror-time
  # filter: a snapshot can outlive a registry edit, e.g. a repo flipped from bridge=on to off, or
  # a stray/spoofed line, so `diff` re-validates independently rather than trusting the snapshot).
  local reg_tsv; reg_tsv="$(mktemp "${TMPDIR:-/tmp}/board-writeback-reg.XXXXXX")"
  awk '{ if ($1 !~ /^#/ && $1 != "") print }' "$registry" > "$reg_tsv"

  local snap_json; snap_json="$(mktemp "${TMPDIR:-/tmp}/board-writeback-snap.XXXXXX")"
  [ -s "$snapshot" ] && cat "$snapshot" > "$snap_json" || : > "$snap_json"

  # Repos actually present in the snapshot (BACKLOG.md rows only -- `megagoals:` origins are
  # explicitly OUT OF SCOPE for writeback v1, see the sub-goal contract's Scope edges; they are
  # dropped here, silently, same as `queue`/`mirror` treat any row shape they don't own).
  local repos; repos="$(jq -r 'select(.repo != "megagoals") | .repo' "$snap_json" 2>/dev/null | sort -u)"

  local n_changes=0 n_skipped=0
  local repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue

    local reg_line path bridge
    reg_line="$(awk -v r="$repo" '$1==r{print; exit}' "$reg_tsv")"
    if [ -z "$reg_line" ]; then
      _n_skip_repo "$repo" "$snap_json" "repo '$repo' not opted in (absent from registry $registry)"
      n_skipped=$((n_skipped + $(_n_count_repo "$repo" "$snap_json")))
      continue
    fi
    path="$(printf '%s\n' "$reg_line" | awk '{print $2}')"; path="${path/#\~/$HOME}"
    # Canonicalize to the PHYSICAL path (pwd -P): `_repo_root_for` below resolves via `git
    # rev-parse --show-toplevel`, which git itself always returns as a physical path (symlinks
    # resolved). On macOS, $TMPDIR (and therefore a fixture's registry path) sits under the
    # `/var -> /private/var` symlink, so a logical-vs-physical mismatch here would silently break
    # every downstream string-prefix operation keyed on repo_root (e.g. `_apply_group`'s `rel=
    # ${backlog_file#"$repo_root"/}`), a real bug this build's own smoke test caught.
    if [ -f "$path" ]; then
      path="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
    fi
    bridge="$(printf '%s\n' "$reg_line" | awk '{print $3}')"
    if [ "${bridge:-}" != "on" ]; then
      _n_skip_repo "$repo" "$snap_json" "repo '$repo' not opted in (bridge='${bridge:-off}' in registry $registry)"
      n_skipped=$((n_skipped + $(_n_count_repo "$repo" "$snap_json")))
      continue
    fi
    if [ ! -f "$path" ]; then
      _n_skip_repo "$repo" "$snap_json" "BACKLOG.md missing at $path"
      n_skipped=$((n_skipped + $(_n_count_repo "$repo" "$snap_json")))
      continue
    fi

    local repo_root board
    repo_root="$(_repo_root_for "$path")"
    board="${board_prefix}${repo}"

    # ONE read call per board (batched, not per-row): `hermes kanban --board <board> list --json`.
    local live_json rc
    if live_json="$("$HERMES_BIN" kanban --board "$board" list --json 2>&1)"; then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ]; then
      _n_skip_repo "$repo" "$snap_json" "'hermes kanban --board $board list --json' failed: $live_json"
      n_skipped=$((n_skipped + $(_n_count_repo "$repo" "$snap_json")))
      continue
    fi
    local live_tsv; live_tsv="$(printf '%s' "$live_json" | jq -r '.[] | [.id, .status] | @tsv' 2>/dev/null)"

    # Current git-side extraction for this repo's BACKLOG.md (id -> current status, current hash).
    local cur_tsv; cur_tsv="$(extract_rows "$path" "$repo" "$repo_root" 2>/dev/null)"

    local origin id hermes_id row_hash hermes_status_snap
    while IFS=$'\t' read -r origin _repo_col id _board_col hermes_id row_hash hermes_status_snap _seen_at; do
      [ -n "$origin" ] || continue
      [ "$repo" = "$(printf '%s' "$origin" | cut -d: -f1)" ] || continue

      local live_status
      live_status="$(printf '%s\n' "$live_tsv" | awk -F'\t' -v h="$hermes_id" '$1==h{print $2; exit}')"
      if [ -z "$live_status" ]; then
        _wb_skip "$origin" "hermes card $hermes_id not found on board '$board' (deleted/renamed out of band)"
        n_skipped=$((n_skipped + 1)); continue
      fi
      if [ "$live_status" = "$hermes_status_snap" ]; then
        continue   # no Hermes-side move at all; not noteworthy, not a skip
      fi

      local target_status
      if ! target_status="$(_reverse_native "$live_status")" || [ -z "$target_status" ]; then
        _wb_skip "$origin" "hermes status '$live_status' has no legal backlog.sh mapping (illegal target status)"
        n_skipped=$((n_skipped + 1)); continue
      fi
      if ! _is_legal_state "$target_status"; then
        _wb_skip "$origin" "mapped target '$target_status' is not a legal backlog.sh state (illegal target status)"
        n_skipped=$((n_skipped + 1)); continue
      fi

      local cur_line cur_status cur_hash
      cur_line="$(printf '%s\n' "$cur_tsv" | awk -F'\t' -v i="$id" '$3==i{print; exit}')"
      if [ -z "$cur_line" ]; then
        _wb_skip "$origin" "row not present in current extraction (shipped/dropped/removed since mirror)"
        n_skipped=$((n_skipped + 1)); continue
      fi
      cur_status="$(printf '%s' "$cur_line" | awk -F'\t' '{print $6}')"
      cur_hash="$(printf '%s' "$cur_line" | awk -F'\t' '{print $8}')"

      # --- THE conflict rule (load-bearing, NC1): a Hermes-side edit applies ONLY if the row's
      # row_hash still equals the mirror-snapshot value. Git wins, always. ---
      if [ "$cur_hash" != "$row_hash" ]; then
        _wb_skip "$origin" "row_hash mismatch: git changed since the last mirror (git wins; refreshed on the next 'board mirror' run)"
        n_skipped=$((n_skipped + 1)); continue
      fi

      if [ "$cur_status" = "$target_status" ]; then
        continue   # already at the target status on the git side; nothing to change
      fi

      jq -nc --arg origin "$origin" --arg repo "$repo" --arg id "$id" --arg hermes_id "$hermes_id" \
        --arg board "$board" --arg backlog_file "$path" --arg repo_root "$repo_root" \
        --arg current_status "$cur_status" --arg target_status "$target_status" \
        --arg hermes_status "$live_status" --arg row_hash "$row_hash" \
        '{origin:$origin, repo:$repo, id:$id, hermes_id:$hermes_id, board:$board, backlog_file:$backlog_file, repo_root:$repo_root, current_status:$current_status, target_status:$target_status, hermes_status:$hermes_status, row_hash:$row_hash}'
      n_changes=$((n_changes + 1))
    done < <(jq -r --arg r "$repo" 'select(.repo==$r) | [.origin, .repo, .id, .board, .hermes_id, .row_hash, .hermes_status, .seen_at] | @tsv' "$snap_json" 2>/dev/null)
  done <<< "$repos"

  rm -f "$reg_tsv" "$snap_json"
  echo "writeback: ${n_changes} change(s), ${n_skipped} skipped" >&2
}

# _n_count_repo / _n_skip_repo -- helper pair for the "whole repo not opted in" rejection path:
# logs one skip line PER ROW so the operator sees every affected origin, not just a repo-level
# summary (matches the per-row skip granularity used everywhere else in this file).
_n_count_repo() {
  jq -r --arg r "$1" 'select(.repo==$r) | .origin' "$2" 2>/dev/null | grep -c . || true
}
_n_skip_repo() {
  local repo="$1" snap_json="$2" reason="$3" o
  while IFS= read -r o; do
    [ -n "$o" ] || continue
    _wb_skip "$o" "$reason"
  done < <(jq -r --arg r "$repo" 'select(.repo==$r) | .origin' "$snap_json" 2>/dev/null)
}

# ---------------------------------------------------------------------------
# apply -- reads the NDJSON changeset on stdin, groups by (repo_root, backlog_file), and for each
# non-empty group: builds a fresh chore/board-sync branch in an isolated worktree off the CURRENT
# HEAD, edits the Status column of ONLY the matched IDs (via lib/backlog.sh's own `set`, so the
# same legal-state validation + annotation-preserving edit this codebase already trusts is reused,
# not re-forked), commits (actor=hermes in the body), pushes, and opens a HELD PR via
# `${GH_BIN:-gh} pr create` (never auto-merged; never a templated shell string -- every value is a
# discrete argv element, and every value here is drawn from this bridge's own closed vocabulary --
# IDs matched against BACKLOG_ID_RE, statuses from LEGAL_STATES -- never raw card title/notes
# text). Emits one board-mirror.sh-snapshot-upsert-SHAPED result line per applied origin to
# stdout (op:"writeback", row_hash PASSED THROUGH unchanged, hermes_status refreshed -- see the
# header comment's "Snapshot refresh" section for why), and one human summary line per repo group
# to stderr.
# ---------------------------------------------------------------------------
cmd_apply() {
  local branch="chore/board-sync" pr_base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)  branch="$2"; shift 2 ;;
      --pr-base) pr_base="$2"; shift 2 ;;
      *) echo "apply: unknown flag '$1'" >&2; return 64 ;;
    esac
  done

  local changeset; changeset="$(mktemp "${TMPDIR:-/tmp}/board-writeback-cs.XXXXXX")"
  cat > "$changeset"
  if [ ! -s "$changeset" ]; then
    rm -f "$changeset"
    return 0
  fi

  local groups; groups="$(mktemp "${TMPDIR:-/tmp}/board-writeback-groups.XXXXXX")"
  jq -r '[.repo_root, .backlog_file] | @tsv' "$changeset" | awk -F'\t' '!seen[$0]++' > "$groups"

  local repo_root backlog_file
  while IFS=$'\t' read -r repo_root backlog_file; do
    [ -n "$repo_root" ] || continue
    _apply_group "$repo_root" "$backlog_file" "$changeset" "$branch" "$pr_base"
  done < "$groups"

  rm -f "$changeset" "$groups"
}

_apply_group() {
  local repo_root="$1" backlog_file="$2" changeset="$3" branch="$4" pr_base="$5"

  local rows; rows="$(jq -c --arg rr "$repo_root" --arg bf "$backlog_file" \
    'select(.repo_root==$rr and .backlog_file==$bf)' "$changeset")"
  [ -n "$rows" ] || return 0

  local rel="${backlog_file#"$repo_root"/}"
  local base="$pr_base"
  [ -n "$base" ] || base="$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || echo master)"

  # Isolated worktree off the CURRENT HEAD (resolved fresh, right here -- never a cached/stale
  # ref). This is what keeps a concurrent append-only writer's row safe (NC6): whatever HEAD is
  # at THIS instant already carries any append committed after the mirror snapshot was taken, and
  # the sync branch is built ON TOP of that HEAD, never a remembered older one.
  local wt; wt="$(mktemp -d "${TMPDIR:-/tmp}/board-writeback-wt.XXXXXX")"
  if ! git -C "$repo_root" worktree add -q -B "$branch" "$wt" HEAD 2>"$wt.err"; then
    echo "writeback: ERROR $repo_root: could not create worktree/branch '$branch': $(cat "$wt.err")" >&2
    rm -f "$wt.err"
    return 0
  fi
  rm -f "$wt.err"

  local n=0 body; body="$(mktemp "${TMPDIR:-/tmp}/board-writeback-msg.XXXXXX")"
  {
    echo "chore(board): sync status move(s) from hermes"
    echo ""
    echo "actor=hermes"
  } > "$body"

  local line id target current origin
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="$(printf '%s' "$line" | jq -r '.id')"
    target="$(printf '%s' "$line" | jq -r '.target_status')"
    current="$(printf '%s' "$line" | jq -r '.current_status')"
    origin="$(printf '%s' "$line" | jq -r '.origin')"
    BACKLOG_FILE="$wt/$rel" bash "$BACKLOG_SH" set "$id" "$target" >/dev/null
    echo "origin: ${origin} -> ${target} (was ${current})" >> "$body"
    n=$((n + 1))
  done <<< "$rows"

  git -C "$wt" add -- "$rel"
  if ! git -C "$wt" commit -q -F "$body" 2>"$wt.commit-err"; then
    echo "writeback: ERROR $repo_root: commit failed: $(cat "$wt.commit-err")" >&2
    rm -f "$body" "$wt.commit-err"
    git -C "$repo_root" worktree remove --force "$wt" 2>/dev/null || true
    return 0
  fi
  rm -f "$wt.commit-err"
  local commit_sha; commit_sha="$(git -C "$wt" rev-parse HEAD)"

  local pushed=0 push_err
  if push_err="$(git -C "$wt" push -u origin "$branch" 2>&1)"; then pushed=1; else pushed=0; fi

  local pr_out="(no PR: push failed)"
  if [ "$pushed" -eq 1 ]; then
    local title="chore(board): sync ${n} status move(s) from hermes"
    if pr_out="$(cd "$wt" && "$GH_BIN" pr create --base "$base" --head "$branch" --title "$title" --body-file "$body" 2>&1)"; then
      :
    else
      echo "writeback: WARNING $repo_root: 'gh pr create' failed: $pr_out" >&2
    fi
  else
    echo "writeback: WARNING $repo_root: git push failed, PR not opened (commit ${commit_sha} exists on local branch '$branch'): $push_err" >&2
  fi

  echo "writeback: ${repo_root}: ${n} row(s) synced on branch '${branch}' (base ${base}), commit ${commit_sha}: ${pr_out}" >&2

  # Snapshot refresh (see header comment): row_hash PASSED THROUGH unchanged, hermes_status set
  # to the live value just observed. Only emitted for origins we actually committed (n>0 guards
  # this whole block already ran, but emit per-row regardless of push/PR outcome -- the conflict
  # rule + legal-state validation already happened in `diff`; the commit is real and local even
  # if the push/PR step degraded, so the snapshot should reflect that the git-side row now differs
  # from the last mirror in a way writeback itself already accounted for).
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    jq -c '{origin, board, hermes_id, row_hash, hermes_status, status:"ok", op:"writeback"}' <<< "$line"
  done <<< "$rows"

  rm -f "$body"
  git -C "$repo_root" worktree remove --force "$wt" 2>/dev/null \
    || echo "writeback: WARNING $repo_root: could not remove scratch worktree $wt (left in place, harmless)" >&2
}

usage() { sed -n '2,90p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    reverse-native)   _reverse_native "$@" ;;
    diff)             cmd_diff "$@" ;;
    apply)            cmd_apply "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "board-writeback.sh: unknown subcommand '$sub'" >&2; usage >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
