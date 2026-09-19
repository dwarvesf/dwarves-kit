#!/usr/bin/env bash
# board-run.sh -- `board run <ID>`: the single-board-row dispatch path.
#
# The gap this closes: lib/queue/orchestrate.sh already drives one fresh `claude -p`
# worker per sub-goal out of a mega-goal dir (ROADMAP.md + POINTER_PROMPT.md +
# goals/), but a single backlog row has no megadir, so it cannot ride that
# machinery -- a session that wants to dispatch one row ends up hand-writing a
# brief instead. This verb scaffolds the MINIMAL megadir for one row (one
# `- [ ] SG-01 <item> , auto` ROADMAP line, a POINTER_PROMPT seeded from the
# row's Item + Notes, and the goals/ plumbing orchestrate expects), then prints
# the exact `orchestrate.sh run <dir>` command. It NEVER launches a session
# itself; the operator (or the calling agent) runs the printed command.
# `--exec` composes the launch when a caller really wants it.
#
# Row content is read through `backlog.sh row` (the board's own parser: same
# no-row / duplicate-id refusals as `get`). The row is OPERATOR-AUTHORED input
# (same trust boundary as queue.sh's hand-authored tsv), so no sanitization
# pass; it lands verbatim in the prompt files.
#
# Megadir resolution order (mirroring the scaffold-root rule commands/mega.md
# names: explicit override > megagoal_root: CLAUDE.md hint > auto-detect by
# repo shape > default):
#   1. --dir <path>                       explicit megadir, verbatim
#   2. megagoal_root: <path>              in <repo>/CLAUDE.md
#   3. first megagoals root already in use (a root holding >=1 */ROADMAP.md),
#      probed in canonical order: _meta/megagoals, docs/megagoals,
#      tools/*/docs/megagoals, experiments/*/megagoals, .claude/goals
#   4. <repo-root>/_meta/megagoals        the default
# The megadir itself is <root>/<id-slug> where <id-slug> is the lowercased row
# id plus up to four slug words of the item title (id-902-board-run-row), so
# the dir sorts and greps by row yet still says what it is.
#
# Files written (idempotent -- an existing file is reported `kept`, never
# overwritten; `board init` uses the same created/kept convention):
#   ROADMAP.md            one `- [ ] SG-01 <item> , auto` line under `## Sub-goals`
#   POINTER_PROMPT.md     objective + the row's Item + Notes verbatim
#   goals/01-<slug>.md    minimal goal contract (Model: sonnet cheap-first,
#                         **Branch:** feat/<id-slug> so orchestrate's rid
#                         telemetry resolves, a restated Done =)
#   HANDOFF.md            empty stub (orchestrate's hot feed-forward)
#   DECISIONS.md          empty stub (the warm ledger)
#
# Usage:
#   board-run.sh <ID> [--backlog-file <path>] [--dir <megadir>] [--exec] [-- <orchestrate-args>]
#     --backlog-file <path>   board file (default: BACKLOG_FILE env, else
#                             $PWD/_meta/BACKLOG.md -- the capture/publish/sync default)
#     --dir <megadir>         scaffold into this exact dir (resolution step 1)
#     --exec                  exec `orchestrate.sh run <dir>` after scaffolding
#                             instead of only printing it; args after `--`
#                             forward verbatim (e.g. `-- --dry-run --step`)
#
# Exit: 1 no such row / duplicate id / no board file; 64 usage.
set -euo pipefail

RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_SH="${BACKLOG_SH:-$RUN_DIR/backlog.sh}"
ORCHESTRATE_SH="${ORCHESTRATE_SH:-$RUN_DIR/../queue/orchestrate.sh}"

usage() { sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# _repo_root_for <path-to-backlog-md> -- git top-level containing the file, else
# the board's parent when it is a _meta/ dir, else the board's own dir.
_repo_root_for() {
  local dir; dir="$(cd "$(dirname "$1")" && pwd)"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null && return 0
  if [ "$(basename "$dir")" = "_meta" ]; then (cd "$dir/.." && pwd); else printf '%s\n' "$dir"; fi
}

# _slugify <text> -- lowercase [a-z0-9-] slug, squeeze runs, trim dashes.
_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

# _title_slug <item> -- up to the first four slug-words of the title (hash tags
# dropped first so "#u-hi" never lands in a dir name), empty for an empty item.
_title_slug() {
  local no_tags; no_tags="$(printf '%s' "$1" | sed -E 's/#[A-Za-z0-9_-]+//g')"
  _slugify "$no_tags" | cut -d- -f1-4
}

# _megagoal_root <repo> -- the repo's megagoals root by the resolution order in
# the header: megagoal_root: hint, then first in-use root in canonical order,
# then the _meta/megagoals default.
_megagoal_root() {
  local repo="$1" hint root
  if [ -f "$repo/CLAUDE.md" ]; then
    hint="$(grep -E '^megagoal_root:[[:space:]]*' "$repo/CLAUDE.md" | head -1 \
      | sed -E 's/^megagoal_root:[[:space:]]*//; s/[[:space:]]+$//')"
    if [ -n "$hint" ]; then
      case "$hint" in /*) printf '%s\n' "$hint" ;; *) printf '%s/%s\n' "$repo" "$hint" ;; esac
      return 0
    fi
  fi
  for root in \
    "$repo/_meta/megagoals" \
    "$repo/docs/megagoals" \
    "$repo"/tools/*/docs/megagoals \
    "$repo"/experiments/*/megagoals \
    "$repo/.claude/goals"; do
    # "in use" = the root exists AND already holds >=1 megadir-shaped child
    # (a */ROADMAP.md), so an empty .claude/goals/ of single-goal drafts does
    # not claim the convention.
    [ -d "$root" ] || continue
    for d in "$root"/*/ROADMAP.md; do
      [ -f "$d" ] && { printf '%s\n' "$root"; return 0; }
    done
  done
  printf '%s\n' "$repo/_meta/megagoals"
}

# _write_once <path> -- write stdin to <path> only when it does not exist;
# prints "created" or "kept" for the report.
_write_once() {
  local path="$1"
  if [ -f "$path" ]; then
    cat >/dev/null   # drain the heredoc so the caller's pipeline stays simple
    printf 'kept    %s\n' "$path"
  else
    cat >"$path"
    printf 'created %s\n' "$path"
  fi
}

main() {
  local id="" backlog="" dir="" do_exec=0
  local -a extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --backlog-file) [ $# -ge 2 ] || { echo "board run: --backlog-file needs a value" >&2; return 64; }
                      backlog="$2"; shift 2 ;;
      --dir)          [ $# -ge 2 ] || { echo "board run: --dir needs a value" >&2; return 64; }
                      dir="$2"; shift 2 ;;
      --exec)         do_exec=1; shift ;;
      --)             shift; extra=("$@"); break ;;
      -h|--help|help) usage; return 0 ;;
      --*)            echo "board run: unknown flag '$1'" >&2; return 64 ;;
      *)              if [ -z "$id" ]; then id="$1"; else echo "board run: unexpected arg '$1'" >&2; return 64; fi
                      shift ;;
    esac
  done
  [ -n "$id" ] || { echo "usage: board run <ID> [--backlog-file <path>] [--dir <megadir>] [--exec] [-- <orchestrate-args>]" >&2; return 64; }

  backlog="${backlog:-${BACKLOG_FILE:-$PWD/_meta/BACKLOG.md}}"
  [ -f "$backlog" ] || { echo "board run: no BACKLOG.md at $backlog (run \`board init\` or pass --backlog-file)" >&2; return 1; }
  backlog="$(cd "$(dirname "$backlog")" && pwd)/$(basename "$backlog")"

  # 1. read the row through the board's own parser (no-row / duplicate refusals
  #    land here verbatim).
  local row item notes status
  row="$(BACKLOG_FILE="$backlog" bash "$BACKLOG_SH" row "$id")" || return 1
  item="$(printf '%s' "$row" | cut -f1)"
  notes="$(printf '%s' "$row" | cut -f2)"
  status="$(printf '%s' "$row" | cut -f3)"
  [ -n "$item" ] || { echo "board run: row $id carries no item text; nothing to dispatch" >&2; return 1; }
  case "${status%% *}" in
    shipped|dropped|parked)
      echo "board run: WARN row $id is '${status%% *}'; scaffolding anyway (the run, not the board, is your call)" >&2 ;;
  esac

  # 2. resolve the megadir.
  local repo_root; repo_root="$(_repo_root_for "$backlog")"
  if [ -z "$dir" ]; then
    local slug; slug="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
    local tslug; tslug="$(_title_slug "$item")"
    [ -n "$tslug" ] && slug="$slug-$tslug"
    dir="$(_megagoal_root "$repo_root")/$slug"
  fi

  # The SG title must not contain " , ": orchestrate's _sg_title cuts the
  # display title at the first " , " and the policy split is comma-based, so a
  # literal one in the item would silently rename the sub-goal.
  local sg_title; sg_title="$(printf '%s' "$item" | sed 's/ , /, /g')"
  local goal_slug; goal_slug="$(_slugify "$(printf '%s' "$item" | sed -E 's/#[A-Za-z0-9_-]+//g')" | cut -c1-40 | sed 's/-*$//')"
  [ -n "$goal_slug" ] || goal_slug="row"
  local id_lower; id_lower="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
  local goal_file="goals/01-${goal_slug}.md"
  local branch_slug; branch_slug="$(basename "$dir")"

  # 3. scaffold (idempotent: existing files are kept, never overwritten).
  mkdir -p "$dir/goals"
  _write_once "$dir/ROADMAP.md" <<EOF
# Mega-goal: $id $item

> Scaffolded by \`board run $id\` from ${backlog}. One board row, one sub-goal.
> ROADMAP.md is the canonical done-ledger: the worker session flips the box,
> the orchestrator advances only then (grounded completion, never self-claim).

## Sub-goals

- [ ] SG-01 $sg_title , auto
EOF
  _write_once "$dir/POINTER_PROMPT.md" <<EOF
Objective: $item

Board row $id (status \`$status\` when scaffolded).

## Item

$item

## Notes

${notes:-(the row carries no notes)}
EOF
  _write_once "$dir/$goal_file" <<EOF
# Sub-goal 01: $item

Model: sonnet
**Branch:** feat/$branch_slug

## Scope

Board row $id (status \`$status\` when scaffolded by \`board run\`).

**Item:** $item

**Notes:**

${notes:-(the row carries no notes)}

**Done =** the row's work is implemented and verified per its notes, one PR
open, and the SG-01 box in ROADMAP.md flipped.
EOF
  _write_once "$dir/HANDOFF.md" </dev/null
  _write_once "$dir/DECISIONS.md" </dev/null

  # 4. print what was scaffolded + the exact run command (the deliverable).
  printf '\nrun it:\n  bash %s run %s\n' "$ORCHESTRATE_SH" "$dir"

  if [ "$do_exec" -eq 1 ]; then
    [ -f "$ORCHESTRATE_SH" ] || { echo "board run: orchestrate.sh not found at $ORCHESTRATE_SH" >&2; return 1; }
    exec bash "$ORCHESTRATE_SH" run "$dir" ${extra[@]+"${extra[@]}"}
  fi
}

main "$@"
