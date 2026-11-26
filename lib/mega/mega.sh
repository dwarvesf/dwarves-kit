#!/usr/bin/env bash
# mega.sh -- `mega status <slug>` (kit-modularity sub-goal 08): reconciles a
# mega-goal's ROADMAP.md sub-goal claims against GIT TRUTH instead of trusting the roadmap's
# own prose. Bash + `gh` only -- no DuckDB (a keyed diff over a handful of sub-goals, not
# analytics; DuckDB stays the `stats` exception per the kit-modularity event-sourcing invariant).
#
# Verbs: `status` (roadmap-vs-git reconcile) · `review --html` (the sign-off dashboard) ·
# `report` (the RUN_REPORT telemetry generator: header + gate matrix + callable-stack
# skeleton from the rid ledgers; --out, --rid-map).
#
# A subsystem dir (the "2+-verb modules get a grouped `lib/<x>/<x>.sh`" rule): `mega` has
# two verbs (`status`, `review`) and was promoted into
# `lib/mega/` (`lib/mega/mega.sh` + siblings, stable entry `bin/mega`).
# `review`'s substantial composition logic lives in the sibling `lib/mega/mega-review.py`
# (bash-launcher-to-python, the exact delegation shape `lib/gate/proof-table-gen.sh` ->
# `lib/gate/proof-table-gen.py` already established: bash 3.2 has no associative arrays, which
# the phase/token/PR joins need). Same shape as `lib/board/board.sh` delegating to
# `lib/adapters/hermes/board-mirror.sh` for its own heavier verbs. The single-verb orphans
# (`lib/adopt.sh` / `lib/explain.sh` / `lib/pitch.sh`) stay at root as documented "deliberate
# orphans" pending their own ruling. `lib/precedent.sh` was promoted out of that set into
# `lib/precedent/precedent.sh` (records + inventory surfaces, stable entry
# `bin/precedent`).
#
# WHY THIS EXISTS (provenance): a live session hit the HANDOFF-vs-reality lie by hand --
# HANDOFF.md claimed "running" while the `kitmod-02` worktree sat at 0 commits, empty. A dumb
# reader that only echoes a roadmap's own `[x]`/`[ ]` boxes would have repeated that lie
# verbatim. This verb is the manual reconciliation (grep ROADMAP, walk branches, verify PRs)
# made mechanical: truth beats the roadmap's prose every time, and when they disagree the flag
# names which side is stale. NOT a live-process monitor (whether a `claude` session is running
# RIGHT NOW is the runner's own journal/RUNNER_DONE job); this only ever points at git + gh.
#
# ROADMAP sub-goal line grammar parsed: the boxes and both id forms are declared once in
# lib/mega/box.tsv (read through lib/mega/box.sh). `SG-NN` is what `/kit:mega` scaffolds today
# (commands/mega.md), `NN-slug` is the older form every archived roadmap still carries.
#   - [x] SG-NN Collapse the module , auto , PR #190 merged cb64f15
#   - [x] 01-module-collapse (dwarves-kit), <prose>, PR #190 merged cb64f15 (<prose>)
#   - [ ] 04-install-wire (dwarves-kit), <prose>, PR #
#   - [~] 09-rehomed (dwarves-kit), rehomed into <other mega> (informational, never flagged)
# done = checked, open = unchecked, parked (`[~]`, alias `[-]`) = rehomed/superseded (informational
# only, per DECISIONS.md's own outcome notes -- these are never drift-flagged even when git truth
# disagrees, because the roadmap is explicitly saying "this box means something else now").
#
# Git truth per sub-goal (gathered against --code-root, the repo the sub-goal's OWN branches/
# PRs live in -- for kit-modularity that is dwarves-kit, a DIFFERENT repo from --megagoals-root,
# which is wherever the mega's ROADMAP.md lives, e.g. ops-toolkit):
#   - PR state: `${GH_BIN:-gh} pr view <N> --json state -q .state` (MERGED/OPEN/CLOSED/missing).
#   - Branch: read the sub-goal's own goal file (`<megagoals-root>/<slug>/goals/<sub>.md`)'s
#     `**Branch:** <name>` line -- the authoritative name (no guessing a naming convention).
#     A sub-goal whose goal file is missing or carries no `**Branch:**` line has no git-truth
#     signal beyond the PR check (this is honest, not a failure).
#   - Commit count: `${GIT_BIN:-git} -C <code-root> rev-list --count <base>..<branch>` (base
#     defaults to `master`, `--base` overrides). Uses the BRANCH REF directly, not a worktree
#     path -- a worktree may have been cleaned up after a PR merges/closes while the branch ref
#     (or its remote-tracking counterpart) still exists, and the ref-based count is exactly as
#     valid a "0 commits" signal as walking a worktree directory would be, without depending on
#     the worktree still being present on disk. Tries the local branch ref first, then
#     `origin/<branch>` (a pushed branch with no local worktree at all).
#   - Open PR: `${GH_BIN:-gh} pr list --state open --json number,headRefName` filtered locally
#     by `headRefName == branch` (jq).
#
# Drift classes (the whole value of this tool -- a dumb `[x]`/`[ ]` echo is worthless):
#   ✓                 [x] and its PR#N verified MERGED.
#   CLAIM-UNVERIFIED  [x] but PR#N is NOT merged (open/closed/missing) -- roadmap ahead of
#                     reality, a green-wash. Never silently trusted.
#   MERGED-UNCHECKED  [ ] but its PR#N IS merged -- roadmap lagging reality.
#   STALLED           [ ] and the branch exists with 0 commits vs base AND no open PR -- a
#                     dispatched-but-empty run (the exact HANDOFF-vs-reality lie this verb
#                     exists to catch).
#   WIP               [ ] and the branch has >0 commits vs base, OR an open PR exists for it --
#                     real in-flight work, NOT stalled (a live worker mid-build is not a lie).
#   PENDING           [ ] and there is no branch, no PR at all -- not yet started; informational.
#   INFO              [~] -- rehomed/superseded, always informational, never flagged regardless
#                     of what git truth shows.
#
# Usage:
#   mega.sh labels   the status labels (declared in lib/mega/labels.tsv), one per line
#   mega.sh status <slug> [--megagoals-root <path>] [--code-root <path>] [--base <branch>]
#                          [--rollup-only]
#     <slug>              the mega-goal's directory name under <megagoals-root>/
#     --megagoals-root    where `<slug>/ROADMAP.md` lives. Precedence: this flag >
#                         $MEGAGOALS_ROOT > `${REPO_ROOT}/_meta/megagoals` (REPO_ROOT is the
#                         kit's existing consumer-config env var, same seam `board`/`queue`
#                         already read) > `<git-toplevel-of-cwd>/_meta/megagoals`. The kit
#                         itself never hardcodes a personal path.
#     --code-root         the repo whose branches/worktrees/PRs are git truth for this mega's
#                         sub-goals. Precedence: this flag > $CODE_ROOT > `<git-toplevel-of-cwd>`
#                         (the natural default: you normally run `mega status` FROM the code
#                         repo the sub-goals build in).
#     --base              the PR base branch sub-goal commit counts are measured against.
#                         Default `master`.
#     --rollup-only       print ONLY the final rollup line (`N/M ok  M-N drift: ...`), no
#                         per-sub-goal detail -- the form `board`'s render wires in as a column.
#
#   mega.sh review <slug> --html [--megagoals-root <path>] [--code-root <path>] [--base <branch>]
#                          [--out <path>]
#     Composes ONE self-contained static HTML sign-off page (harness-loop) from
#     THREE read-only sources: this `status` verb's own git-truth reconciliation, the gate/run
#     ledger (GATE/OUTCOME/TOKENS lines), and `gh pr view` (PR/CI/merge state) -- plus a
#     best-effort harness-wide footer (staged candidates, learned-ledger queued, unpaid debt).
#     `--html` is currently the ONLY surface and is required (no live/served variant; scope
#     fence, see the goal file). Default `--out`: `<megagoals-root>/<slug>/REVIEW.html` (next to
#     RUN_REPORT.md). A projection, never a stored source of truth (discipline): safe
#     to re-run any time, nothing cached. The substantial logic lives in the sibling
#     `lib/mega/mega-review.py`; this verb is a thin bash launcher that resolves KIT_LOG_DIR the exact
#     way `lib/gate/proof-table-gen.sh` already does, then execs it.
#
#   mega.sh runs [--registry <path>] [--root <dir>]... [--out <path>]
#                [--max-embed-bytes <n>] [--total-embed-bytes <n>]
#     The ESTATE-WIDE sibling of `review`: ONE self-contained static HTML page of run
#     cards over EVERY registered repo, composed from run reports (`_meta/megagoals/**/
#     RUN_REPORT.md`), proofs of done (`**/docs/proof-of-done.md`), and verification runs
#     (`docs/verification/**/runs/*.md`), with each report's own capture images embedded inline.
#     Same projection discipline as `review`: reads only, caches nothing, safe to re-run.
#     --registry   a `boards.txt`-format registry of repos to scan. Precedence: this flag >
#                  $KIT_BOARDS_REGISTRY > `<git-toplevel-of-cwd>/_meta/boards.txt`. Every row is
#                  scanned, including rows without the `bridge` column -- `bridge` gates a
#                  Hermes WRITE path, not reading a repo's own reports.
#     --root       scan this repo root directly; repeatable, and bypasses the registry entirely.
#     --out        default `runs-dashboard.html` in the cwd.
#     Empty estate is NOT an error: an empty or artifact-free root renders a valid page carrying
#     an explicit empty-state banner and exits 0. Nothing is fabricated to fill it.
#     Logic lives in the sibling `lib/mega/runs-dashboard.py`; this verb is a thin launcher.
#
#   mega.sh tick <mega-slug> <NN-slug> --pr <N> [--note <text> | --keep-note]
#                [--attempt <aid> | --no-attempt] [--branch-override <reason>]
#                [--megagoals-root <path>] [--code-root <path>]
#     The one WRITER in this module: records a merged sub-goal from gh truth. Audits PR <N>
#     through `gh` (MERGED, a merge commit, base = the code repo's default branch), checks the
#     goal file's **Branch:** against the PR head, rewrites the sub-goal's ROADMAP line to
#     `- [x] <NN-slug>, PR #<N>, merged <sha7>[ (<note>)]` (sha from gh only), then records
#     `attempt-state.sh commit-result`. Every refusal writes nothing. Never commits or pushes.
#     Repos that keep megas outside `_meta/megagoals` pass the root, for example:
#       bin/mega tick 01-human-first-upgrade 40-drag-by-labels --pr 96 --megagoals-root docs/megagoals
#     Exits: 0 ticked/unchanged; 1 gh audit refused; 3 line or text refused; 4 ledger checkout
#     on its default branch, detached, or no default; 5 attempt store refused; 6 ROADMAP written
#     but commit-result failed (re-run the same command); 7 lock held; 8 write path refused;
#     64 usage. Env: GH_BIN, ATTEMPT_STATE_BIN, ATTEMPT_REGISTRY_DIR, MEGA_TICK_GH_TIMEOUT_S
#     (default 30, via timeout/gtimeout; unbounded when neither exists), MEGA_TICK_LOCK_WAIT_SECS
#     (default 10, 0 or a decimal, 0.2 s polls). Test-only: MEGA_TICK_TEST=1 with
#     MEGA_TICK_TEST_PAUSE_FILE pauses after the line read while that file exists (max 30 s).
#
# GH_BIN / GIT_BIN override the `gh`/`git` binaries (tests point them at PATH-injected stubs
# that log argv and return canned JSON, per the suite's existing convention -- see
# `lib/adapters/hermes/board-writeback.sh`'s `GH_BIN`). No real network call is ever made by the test
# suite; every gh/git interaction here is a plain, stub-friendly subprocess call.

set -uo pipefail

# shellcheck source=./box.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/box.sh" || exit 1

GH_BIN="${GH_BIN:-gh}"
GIT_BIN="${GIT_BIN:-git}"

_default_repo_root() { "$GIT_BIN" rev-parse --show-toplevel 2>/dev/null || pwd; }

OPT_MEGAGOALS_ROOT=""; OPT_CODE_ROOT=""; OPT_BASE=""; OPT_ROLLUP_ONLY=0
OPT_HTML=0; OPT_OUT=""; OPT_RID_MAP=""
POSITIONAL=()
_parse_flags() {
  OPT_MEGAGOALS_ROOT=""; OPT_CODE_ROOT=""; OPT_BASE=""; OPT_ROLLUP_ONLY=0
  OPT_HTML=0; OPT_OUT=""; OPT_RID_MAP=""
  POSITIONAL=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --megagoals-root) OPT_MEGAGOALS_ROOT="${2:-}"; shift 2 ;;
      --rid-map)        OPT_RID_MAP="${2:-}"; shift 2 ;;
      --code-root)      OPT_CODE_ROOT="${2:-}"; shift 2 ;;
      --base)           OPT_BASE="${2:-}"; shift 2 ;;
      --rollup-only)    OPT_ROLLUP_ONLY=1; shift ;;
      --html)           OPT_HTML=1; shift ;;
      --out)            OPT_OUT="${2:-}"; shift 2 ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
  done
}

_resolve_megagoals_root() {
  if [ -n "$OPT_MEGAGOALS_ROOT" ]; then printf '%s\n' "$OPT_MEGAGOALS_ROOT"; return; fi
  if [ -n "${MEGAGOALS_ROOT:-}" ]; then printf '%s\n' "$MEGAGOALS_ROOT"; return; fi
  if [ -n "${REPO_ROOT:-}" ]; then printf '%s/_meta/megagoals\n' "$REPO_ROOT"; return; fi
  printf '%s/_meta/megagoals\n' "$(_default_repo_root)"
}

_resolve_code_root() {
  if [ -n "$OPT_CODE_ROOT" ]; then printf '%s\n' "$OPT_CODE_ROOT"; return; fi
  if [ -n "${CODE_ROOT:-}" ]; then printf '%s\n' "$CODE_ROOT"; return; fi
  _default_repo_root
}

# _goal_file <megagoals-root> <slug> <sub-slug> -- the sub-goal's goal file, or empty. An NN-slug id
# names its file (`goals/<id>.md`). An SG-NN id has no slug, so the file is `goals/NN-<slug>.md`, the
# scaffold name commands/mega.md writes and orchestrate.sh `_goalfile` resolves (first match).
_goal_file() {
  local mroot="$1" slug="$2" sub="$3" f
  case "$sub" in
    SG-*) for f in "$mroot/$slug/goals/${sub#SG-}-"*.md; do [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }; done ;;
    *) [ -f "$mroot/$slug/goals/$sub.md" ] && printf '%s\n' "$mroot/$slug/goals/$sub.md" ;;
  esac
  return 0
}

# _sub_branch <megagoals-root> <slug> <sub-slug> <code-root> -- the sub-goal's own goal file's
# `**Branch:** <name>` line. An SG-NN sub-goal with no such line falls back to `wave/sg-nn`, the
# branch orchestrate.sh `_sg_branch` names, but only when that branch exists in <code-root> (a name
# nobody created would print a branch that is not there). Empty output = no signal (honest absence,
# not an error): the sub-goal then has no git-truth signal beyond its PR check.
_sub_branch() {
  local mroot="$1" slug="$2" sub="$3" croot="${4:-}" gf br wave
  gf="$(_goal_file "$mroot" "$slug" "$sub")"
  [ -n "$gf" ] && br="$(grep -m1 -E '^\*\*Branch:\*\* ' "$gf" 2>/dev/null | sed -E 's/^\*\*Branch:\*\* *//')"
  if [ -n "${br:-}" ]; then printf '%s\n' "$br"; return 0; fi
  case "$sub" in
    SG-*)
      wave="wave/$(printf '%s' "$sub" | tr '[:upper:]' '[:lower:]')"
      if [ -n "$croot" ] && "$GIT_BIN" -C "$croot" rev-parse --verify --quiet "refs/heads/$wave" >/dev/null 2>&1; then printf '%s\n' "$wave"
      elif [ -n "$croot" ] && "$GIT_BIN" -C "$croot" rev-parse --verify --quiet "refs/remotes/origin/$wave" >/dev/null 2>&1; then printf '%s\n' "$wave"
      fi ;;
  esac
  return 0
}

# _pr_state <pr-number> -- MERGED/OPEN/CLOSED, or empty if unresolvable (missing/deleted PR,
# `gh` failure). Never treated as a hard error: an unresolvable PR# is exactly a
# CLAIM-UNVERIFIED signal for a [x] row (the roadmap cites a PR that can't be confirmed).
_pr_state() {
  local pr="$1"
  "$GH_BIN" pr view "$pr" --json state -q '.state' 2>/dev/null || true # merged-ok: report only, prints one PR number's state and deletes nothing
}

# _commit_count <code-root> <base> <branch> -- commits on <branch> not on <base>. Tries the
# local branch ref, then `origin/<branch>` (a pushed-but-no-local-worktree branch). Empty
# output = branch does not exist anywhere reachable (honest absence).
_commit_count() {
  local root="$1" base="$2" branch="$3"
  if "$GIT_BIN" -C "$root" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
    "$GIT_BIN" -C "$root" rev-list --count "$base..$branch" 2>/dev/null || true
    return
  fi
  if "$GIT_BIN" -C "$root" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null 2>&1; then
    "$GIT_BIN" -C "$root" rev-list --count "$base..origin/$branch" 2>/dev/null || true # merged-ok: commit count for the mega status report, deletes nothing
  fi
}

# _open_pr_for <branch> -- the PR number of an OPEN pr whose head is <branch>, or empty.
_open_pr_for() {
  local branch="$1" out
  out="$("$GH_BIN" pr list --state open --json number,headRefName 2>/dev/null)" || return 0
  printf '%s' "$out" | jq -r --arg b "$branch" '.[] | select(.headRefName == $b) | .number' 2>/dev/null | head -n1
}

# _classify <box-name: open|done|parked> <prnum> <prstate> <commit-count> <open-pr> -- one of:
#   ok | claim-unverified | merged-unchecked | stalled | wip | pending | info
_classify() {
  local box="$1" prnum="$2" prstate="$3" commits="$4" openpr="$5"
  case "$box" in
    done)
      if [ -n "$prnum" ] && [ "$prstate" = "MERGED" ]; then echo "ok"
      else echo "claim-unverified"
      fi
      ;;
    parked)
      echo "info"
      ;;
    *)
      if [ -n "$prnum" ] && [ "$prstate" = "MERGED" ]; then
        echo "merged-unchecked"
      elif [ -n "$commits" ] && [ "$commits" = "0" ] && [ -z "$openpr" ]; then
        echo "stalled"
      elif { [ -n "$commits" ] && [ "$commits" != "0" ]; } || [ -n "$openpr" ]; then
        echo "wip"
      else
        echo "pending"
      fi
      ;;
  esac
}

_LABELS_TSV="$BOX_DIR/labels.tsv"

# _label <class> -- the printed label for a class, from lib/mega/labels.tsv; the fallback row for an unknown class.
_label() {
  # DOWNSTREAM COUPLING: `lib/mega/mega-review.py` builds its status-line parser from the same table,
  # so a label added or renamed there reaches both readers with no second edit.
  awk -F'\t' -v c="$1" '
    /^#/ || NF < 3 { next }
    $1 == c { print $2; found = 1; exit }
    $3 == "fallback" { fb = $2 }
    END { if (!found) print fb }' "$_LABELS_TSV"
}

# cmd_labels -- the status labels, one per line, in table order.
cmd_labels() { awk -F'\t' '!/^#/ && NF >= 3 && $3 == "status" { print $2 }' "$_LABELS_TSV"; }

_symbol() {
  case "$1" in
    ok)                printf '\xe2\x9c\x93' ;;   # checkmark
    claim-unverified)  printf '\xe2\x9a\xa0' ;;    # warning
    merged-unchecked)  printf '\xe2\x9a\xa0' ;;
    stalled)           printf '\xe2\x9a\xa0' ;;
    wip)               printf '~' ;;
    pending)           printf '.' ;;
    info)              printf '-' ;;
    *)                 printf '?' ;;
  esac
}

cmd_status() {
  _parse_flags "$@"
  local slug="${POSITIONAL[0]:-}"
  [ -n "$slug" ] || { echo "mega status: a <slug> is required" >&2; return 64; }

  local mroot croot base
  mroot="$(_resolve_megagoals_root)"
  croot="$(_resolve_code_root)"
  base="${OPT_BASE:-master}"

  local roadmap="$mroot/$slug/ROADMAP.md"
  [ -f "$roadmap" ] || { echo "mega status: no ROADMAP.md at $roadmap" >&2; return 1; }

  local total=0 ok_count=0 drift_count=0 box_any
  box_any="$(box_re)"
  local -a detail_lines=()

  while IFS= read -r line; do
    # Both id forms are live (SG-NN, NN-slug; lib/mega/box.tsv). Matching only the old one made this
    # auditor silently find ZERO rows in a current roadmap and report nothing wrong, which is the
    # worst failure available to a reconciler: a checker that cannot see its input passes.
    [[ "$line" =~ ^${box_any}\ ${BOX_ID_RE} ]] || continue
    local sub="${BASH_REMATCH[1]}" boxname
    boxname="$(box_name "${line:3:1}")"
    total=$((total + 1))

    local prnum="" sha=""
    if [[ "$line" =~ PR\ \#([0-9]+) ]]; then
      prnum="${BASH_REMATCH[1]}"
      if [[ "$line" =~ PR\ \#${prnum}\ merged\ ([0-9a-fA-F]{6,40}) ]]; then
        sha="${BASH_REMATCH[1]}"
      fi
    fi

    local branch commits="" openpr="" prstate=""
    branch="$(_sub_branch "$mroot" "$slug" "$sub" "$croot")"
    [ -n "$prnum" ] && prstate="$(_pr_state "$prnum")"
    if [ -n "$branch" ]; then
      commits="$(_commit_count "$croot" "$base" "$branch")"
      openpr="$(_open_pr_for "$branch")"
    fi

    local cls; cls="$(_classify "$boxname" "$prnum" "$prstate" "$commits" "$openpr")"
    case "$cls" in
      ok) ok_count=$((ok_count + 1)) ;;
      claim-unverified|merged-unchecked|stalled) drift_count=$((drift_count + 1)) ;;
    esac

    local extra=""
    [ -n "$prnum" ] && extra="${extra} PR#${prnum}${prstate:+ (${prstate})}"
    [ -n "$branch" ] && extra="${extra} branch=${branch}"
    [ -n "$commits" ] && extra="${extra} commits=${commits}"
    [ -n "$openpr" ] && extra="${extra} open-PR#${openpr}"
    detail_lines+=("$(printf '  %s %-28s %s%s' "$(_symbol "$cls")" "$sub" "$(_label "$cls")" "$extra")")
  done < <(cat "$roadmap")

  [ "$total" -gt 0 ] || { echo "mega status: no sub-goal lines found in $roadmap" >&2; return 1; }

  local rollup
  if [ "$drift_count" -gt 0 ]; then
    rollup="$(printf '%s: %d/%d ok  \xe2\x9a\xa0 %d drift' "$slug" "$ok_count" "$total" "$drift_count")"
  else
    rollup="$(printf '%s: %d/%d ok' "$slug" "$ok_count" "$total")"
  fi

  if [ "$OPT_ROLLUP_ONLY" -eq 1 ]; then
    printf '%s\n' "$rollup"
    [ "$drift_count" -eq 0 ]
    return
  fi

  printf '%s\n' "${detail_lines[@]}"
  printf '%s\n' "$rollup"
  [ "$drift_count" -eq 0 ]
}

# cmd_review: the bash launcher half of `mega review --html <slug>`. Resolves
# KIT_LOG_DIR the exact way `lib/gate/proof-table-gen.sh` already does (source
# lib/telemetry/kit-log-dir.sh, export the result) so there is ONE resolver, not a second copy,
# then execs the sibling `lib/mega/mega-review.py` (bash 3.2 has no associative arrays, the same
# reason proof-table-gen.sh delegates to its own .py). `--html` is required: it is currently the
# ONLY surface (scope fence -- no live/served variant).
cmd_review() {
  _parse_flags "$@"
  local slug="${POSITIONAL[0]:-}"
  [ -n "$slug" ] || { echo "mega review: a <slug> is required" >&2; return 64; }
  [ "$OPT_HTML" -eq 1 ] || { echo "mega review: --html is required (the only surface today)" >&2; return 64; }

  local mroot croot base
  mroot="$(_resolve_megagoals_root)"
  croot="$(_resolve_code_root)"
  base="${OPT_BASE:-master}"

  local self_dir; self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/telemetry/kit-log-dir.sh
  source "$self_dir/../telemetry/kit-log-dir.sh" || { echo "mega review: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; return 1; }
  export KIT_LOG_DIR; KIT_LOG_DIR="$(kit_resolve_log_dir)" || return 1

  local -a py_args=("$slug" --megagoals-root "$mroot" --code-root "$croot" --base "$base")
  [ -n "$OPT_OUT" ] && py_args+=(--out "$OPT_OUT")
  python3 "$self_dir/mega-review.py" "${py_args[@]}"
}

# cmd_report: the bash launcher half of `mega report <slug>` -- the RUN_REPORT telemetry
# generator. Fold-in gap fix (Han 2026-07-12): the close contract required a gate matrix +
# callable stack "read from the rid ledger", but no code could render them; the presentation
# lived as conductor habit from the pre-fold era and died in the migration (harness-loop's
# matrix got rebuilt by hand). Same delegation shape as cmd_review: resolve KIT_LOG_DIR via
# the ONE resolver, exec the sibling .py. Read-only; --out is the only write, when passed.
cmd_report() {
  _parse_flags "$@"
  local slug="${POSITIONAL[0]:-}"
  [ -n "$slug" ] || { echo "mega report: a <slug> is required" >&2; return 64; }

  local mroot; mroot="$(_resolve_megagoals_root)"
  local self_dir; self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/telemetry/kit-log-dir.sh
  source "$self_dir/../telemetry/kit-log-dir.sh" || { echo "mega report: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; return 1; }
  local log_dir; log_dir="$(kit_resolve_log_dir)" || return 1

  local -a py_args=("$slug" --megagoals-root "$mroot" --log-dir "$log_dir")
  [ -n "$OPT_OUT" ] && py_args+=(--out "$OPT_OUT")
  [ -n "$OPT_RID_MAP" ] && py_args+=(--rid-map "$OPT_RID_MAP")
  python3 "$self_dir/mega-report.py" "${py_args[@]}"
}

# `runs` is estate-wide, so it takes NO <slug> and none of `_parse_flags`'s per-mega flags. Its
# argv forwards straight through to the generator, which owns its own flag grammar.
cmd_runs() {
  local self_dir; self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$self_dir/runs-dashboard.py" "$@"
}

# ---- tick: the one writer (see the usage block above and the spec it names) ----

# shellcheck source=../gate/default-branch-warn.sh
. "$BOX_DIR/../gate/default-branch-warn.sh" || exit 1

_TICK_MAX_TEXT=200

_tick_git() { local dir="$1"; shift; env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" "$@"; }

# _tick_refuse <code> <reason> -- one stderr line, then the code. Callers write `... || return $?`.
_tick_refuse() { local code="$1"; shift; printf 'mega tick: REFUSED %s\n' "$*" >&2; return "$code"; }

# _tick_has_ctl <text> -- exit 0 when <text> holds a control byte (0x01-0x1f or 0x7f). A byte-count
# compare, because a line-based grep never sees an embedded newline.
_tick_has_ctl() {
  local all clean
  all="$(printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' ')"
  clean="$(printf '%s' "$1" | LC_ALL=C tr -d '\001-\037\177' | LC_ALL=C wc -c | tr -d ' ')"
  [ "$all" != "$clean" ]
}

_tick_bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }

# _tick_clean <text> -- printable form of an untrusted string: control bytes stripped, 200 bytes max.
_tick_clean() { printf '%s' "$1" | LC_ALL=C tr -d '\001-\037\177' | LC_ALL=C cut -c1-200; }

# _tick_text_ok <label> <text> -- the note / override-reason rule: no control byte, at most 200 bytes.
_tick_text_ok() {
  if _tick_has_ctl "$2"; then _tick_refuse 3 "$1 holds a control character"; return; fi
  if [ "$(_tick_bytes "$2")" -gt "$_TICK_MAX_TEXT" ]; then _tick_refuse 3 "$1 is longer than $_TICK_MAX_TEXT bytes"; return; fi
  return 0
}

# _tick_branch_norm <raw **Branch:** value> -- CR, a trailing " (...)" group, whitespace, one pair of
# surrounding backticks. Real goal files carry `ci/release-pipeline (existing)`.
_tick_branch_norm() {
  local v="$1" bt='`'
  v="${v%$'\r'}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  case "$v" in *' ('*')') v="${v% (*}" ;; esac
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  case "$v" in "$bt"*"$bt") v="${v#"$bt"}"; v="${v%"$bt"}" ;; esac
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  printf '%s\n' "$v"
}

# _tick_args <argv...> -- sets T_* or refuses (64 usage, 3 for note / reason text).
_tick_args() {
  T_SLUG=""; T_ID=""; T_PR=""; T_NOTE=""; T_HAS_NOTE=0; T_KEEP=0; T_ATTEMPT=""; T_NO_ATTEMPT=0
  T_OVERRIDE=""; T_HAS_OVERRIDE=0; OPT_MEGAGOALS_ROOT=""; OPT_CODE_ROOT=""
  local -a pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr|--note|--attempt|--branch-override|--megagoals-root|--code-root)
        [ $# -ge 2 ] || { _tick_refuse 64 "$1 needs a value"; return; }
        case "$1" in
          --pr) T_PR="$2" ;;
          --note) T_NOTE="$2"; T_HAS_NOTE=1 ;;
          --attempt) T_ATTEMPT="$2"; [ -n "$2" ] || { _tick_refuse 64 "--attempt needs an id"; return; } ;;
          --branch-override) T_OVERRIDE="$2"; T_HAS_OVERRIDE=1 ;;
          --megagoals-root) OPT_MEGAGOALS_ROOT="$2" ;;
          --code-root) OPT_CODE_ROOT="$2" ;;
        esac
        shift 2 ;;
      --keep-note) T_KEEP=1; shift ;;
      --no-attempt) T_NO_ATTEMPT=1; shift ;;
      -*) _tick_refuse 64 "unknown flag $(_tick_clean "$1")"; return ;;
      *) pos+=("$1"); shift ;;
    esac
  done
  [ "${#pos[@]}" -eq 2 ] || { _tick_refuse 64 "usage: mega tick <mega-slug> <NN-slug> --pr <N> (see mega.sh --help)"; return; }
  T_SLUG="${pos[0]}"; T_ID="${pos[1]}"
  if ! [[ "$T_SLUG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$T_SLUG" == *..* ]]; then
    _tick_refuse 64 "mega slug '$(_tick_clean "$T_SLUG")' is not a plain directory name"; return
  fi
  if [[ "$T_ID" =~ ^${BOX_SG_RE}$ ]]; then _tick_refuse 64 "SG-NN ids are not supported; tick takes an NN-slug id"; return; fi
  [[ "$T_ID" =~ ^$(box_id_re slug)$ ]] || { _tick_refuse 64 "'$(_tick_clean "$T_ID")' is not an NN-slug sub-goal id"; return; }
  [[ "$T_PR" =~ ^[1-9][0-9]{0,8}$ ]] || { _tick_refuse 64 "--pr wants a PR number (1 to 9 digits, no leading zero)"; return; }
  [ "$T_HAS_NOTE" -eq 1 ] && [ "$T_KEEP" -eq 1 ] && { _tick_refuse 64 "--note and --keep-note are exclusive"; return; }
  [ "$T_HAS_NOTE" -eq 0 ] || [ -n "$T_NOTE" ] || { _tick_refuse 64 "--note needs non-empty text"; return; }
  [ -n "$T_ATTEMPT" ] && [ "$T_NO_ATTEMPT" -eq 1 ] && { _tick_refuse 64 "--attempt and --no-attempt are exclusive"; return; }
  if [ "$T_HAS_NOTE" -eq 1 ]; then _tick_text_ok "--note" "$T_NOTE" || return; fi
  if [ "$T_HAS_OVERRIDE" -eq 1 ]; then
    [ -n "$T_OVERRIDE" ] || { _tick_refuse 64 "--branch-override needs a reason"; return; }
    _tick_text_ok "--branch-override reason" "$T_OVERRIDE" || return
  fi
  return 0
}

# _tick_ledger <roadmap> -- the ROADMAP is a regular file (8) in a checkout on a named, non-default branch (4).
_tick_ledger() {
  local rm="$1" dir br def
  { [ -f "$rm" ] && [ ! -L "$rm" ]; } || { _tick_refuse 8 "$rm is missing, a symlink, or not a regular file"; return; }
  dir="$(dirname -- "$rm")"
  br="$(_tick_git "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" || br=""
  [ -n "$br" ] || { _tick_refuse 4 "the ROADMAP checkout has a detached HEAD; check out a work branch first"; return; }
  def="$(kit_default_branch_here "$dir")"
  [ -n "$def" ] || { _tick_refuse 4 "no default branch resolves for the ROADMAP checkout (kit_default_branch_here: origin/HEAD, origin/main, origin/master); fix: git -C $(printf '%q' "$dir") remote set-head origin -a"; return; }
  [ "$br" != "$def" ] || { _tick_refuse 4 "the ROADMAP checkout is on its default branch ($def); a tick there cannot land through a PR"; return; }
  T_LEDGER_TOP="$(_tick_git "$dir" rev-parse --show-toplevel 2>/dev/null)"
  return 0
}

# _tick_audit <code-root> <pr> -- gh truth for one PR. Sets T_REPO T_BASE T_HEAD T_OID or refuses (1).
_tick_audit() {
  local croot="$1" pr="$2" def tmo="" secs out rc errf err state oid url f
  command -v jq >/dev/null 2>&1 || { _tick_refuse 1 "jq is not installed"; return; }
  command -v "$GH_BIN" >/dev/null 2>&1 || { _tick_refuse 1 "gh ($(_tick_clean "$GH_BIN")) is not installed"; return; }
  def="$(kit_default_branch_here "$croot")"
  [ -n "$def" ] || { _tick_refuse 1 "no default branch resolves for the code root (kit_default_branch_here: origin/HEAD, origin/main, origin/master); fix: git -C $(printf '%q' "$croot") remote set-head origin -a"; return; }
  secs="${MEGA_TICK_GH_TIMEOUT_S:-30}"; case "$secs" in ''|*[!0-9]*) secs=30 ;; esac
  command -v timeout >/dev/null 2>&1 && tmo=timeout
  [ -z "$tmo" ] && command -v gtimeout >/dev/null 2>&1 && tmo=gtimeout
  errf="$(mktemp "${TMPDIR:-/tmp}/mega-tick-gh.XXXXXX")" || { _tick_refuse 1 "mktemp failed"; return; }
  out="$(cd "$croot" && GH_PROMPT_DISABLED=1 ${tmo:+$tmo "$secs"} "$GH_BIN" pr view "$pr" --json state,mergeCommit,baseRefName,headRefName,url </dev/null 2>"$errf")"; rc=$? # merged-ok: reads one PR number the caller names, the tick audit; deletes nothing
  err="$(head -n1 "$errf" 2>/dev/null)"; rm -f "$errf"
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then _tick_refuse 1 "gh pr view $pr failed (exit $rc): $(_tick_clean "$err")"; return; fi
  printf '%s' "$out" | jq -e 'type == "object"' >/dev/null 2>&1 || { _tick_refuse 1 "gh pr view $pr returned JSON jq cannot parse"; return; }
  state="$(printf '%s' "$out" | jq -j '.state // ""')"
  oid="$(printf '%s' "$out" | jq -j '.mergeCommit.oid // ""')"
  T_BASE="$(printf '%s' "$out" | jq -j '.baseRefName // ""')"
  T_HEAD="$(printf '%s' "$out" | jq -j '.headRefName // ""')"
  url="$(printf '%s' "$out" | jq -j '.url // ""')"
  for f in "$state" "$oid" "$T_BASE" "$T_HEAD" "$url"; do
    if _tick_has_ctl "$f" || [ "$(_tick_bytes "$f")" -gt 255 ]; then _tick_refuse 1 "gh returned a PR string over 255 bytes or with a control character"; return; fi
  done
  [ "$state" = "MERGED" ] || { _tick_refuse 1 "PR #$pr is $(_tick_clean "${state:-unknown}"), not MERGED"; return; }
  [ -n "$oid" ] || { _tick_refuse 1 "PR #$pr is merged but gh has no merge commit yet; retry shortly"; return; }
  [[ "$oid" =~ ^[0-9a-f]{40}$ ]] || { _tick_refuse 1 "PR #$pr merge commit '$(_tick_clean "$oid")' is not a 40-hex oid"; return; }
  [ "$T_BASE" = "$def" ] || { _tick_refuse 1 "PR #$pr merged into '$(_tick_clean "$T_BASE")', not the code root's default branch '$def' (kit_default_branch_here)"; return; }
  [[ "$url" =~ ^https://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+)$ ]] || { _tick_refuse 1 "gh url '$(_tick_clean "$url")' is not a PR url"; return; }
  [ "${BASH_REMATCH[3]}" = "$pr" ] || { _tick_refuse 1 "gh url names PR #${BASH_REMATCH[3]}, not #$pr"; return; }
  T_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; T_OID="$oid"
  return 0
}

_tick_as() { bash "${ATTEMPT_STATE_BIN:-$BOX_DIR/../goal/attempt-state.sh}" "$@"; }

# _tick_store <id> <code-root> <ledger-top> -- find the attempt record and pick the attempt, before any
# write. Sets T_STORE (empty = no record), T_AID, T_AS_LINE (the line to print when no record), T_WIN_REF.
_tick_store() {
  local id="$1" croot="$2" ltop="$3" d root found="" n=0 any_dir=0 dirs="" st line w k v
  local -a cands=()
  T_STORE=""; T_AID=""; T_AS_LINE=""; T_WIN_REF=""
  if [ -n "${ATTEMPT_REGISTRY_DIR:-}" ]; then
    cands=("$ATTEMPT_REGISTRY_DIR")
  else
    for root in "$croot" "$ltop"; do
      d="$(cd "$root" 2>/dev/null && _tick_as dir 2>/dev/null)" && [ -n "$d" ] || { _tick_refuse 5 "the attempt store does not resolve from $(_tick_clean "$root")"; return; }
      local seen=0 c
      for c in "${cands[@]:-}"; do [ "$c" = "$d" ] && seen=1; done
      [ "$seen" -eq 1 ] || cands+=("$d")
    done
  fi
  for d in "${cands[@]}"; do
    dirs="${dirs:+$dirs, }$d"
    [ -d "$d" ] && any_dir=1
    if [ -f "$d/$id.task" ]; then found="$d"; n=$((n + 1)); fi
  done
  [ "$n" -le 1 ] || { _tick_refuse 5 "a record for $id sits in more than one store ($dirs); settle one with attempt-state.sh"; return; }
  if [ "$n" -eq 0 ]; then
    [ -z "$T_ATTEMPT" ] || { _tick_refuse 5 "--attempt $(_tick_clean "$T_ATTEMPT") given, but no record for $id in $dirs"; return; }
    if [ "$T_NO_ATTEMPT" -eq 1 ]; then T_AS_LINE="ATTEMPT skipped $id (--no-attempt)"; return 0; fi
    [ "$any_dir" -eq 1 ] || { _tick_refuse 5 "no attempt store dir exists ($dirs); pass --no-attempt if this mega never dispatched through attempt-state"; return; }
    T_AS_LINE="ATTEMPT none $id (no $id.task in $dirs)"; return 0
  fi
  [ "$T_NO_ATTEMPT" -eq 0 ] || { _tick_refuse 5 "--no-attempt given, but $found holds a record for $id"; return; }
  T_STORE="$found"
  st="$(ATTEMPT_REGISTRY_DIR="$T_STORE" _tick_as status "$id" 2>&1)" || { _tick_refuse 5 "attempt-state.sh status $id failed: $(_tick_clean "$st")"; return; }
  local tstate="" winner="" live="" nlive=0 named_state="" summary=""
  local -a ws
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local a_id="" a_state=""
    read -r -a ws <<<"$line"
    for w in "${ws[@]}"; do
      k="${w%%=*}"; v="${w#*=}"
      case "$line" in
        task=*) [ "$k" = state ] && tstate="$v" ;;
        winner=*) case "$k" in winner) winner="$v" ;; ref) T_WIN_REF="$v" ;; esac ;;
        attempt=*) case "$k" in attempt) a_id="$v" ;; state) a_state="$v" ;; esac ;;
      esac
    done
    if [ -n "$a_id" ]; then
      summary="${summary:+$summary, }$a_id=$a_state"
      [ "$a_id" = "$T_ATTEMPT" ] && named_state="$a_state"
      if [ "$a_state" = running ] || [ "$a_state" = disconnected ]; then live="${live:+$live }$a_id"; nlive=$((nlive + 1)); fi
    fi
  done <<EOF
$st
EOF
  local why="task $id is ${tstate:-unknown} ($summary); pass --attempt <aid> for an eligible attempt, or settle the record with attempt-state.sh first"
  if [ -n "$T_ATTEMPT" ]; then
    if [ "$tstate" = dispatched ] && { [ "$named_state" = running ] || [ "$named_state" = disconnected ]; }; then T_AID="$T_ATTEMPT"
    elif [ "$tstate" = done ] && [ "$T_ATTEMPT" = "$winner" ]; then T_AID="$T_ATTEMPT"
    else _tick_refuse 5 "attempt $(_tick_clean "$T_ATTEMPT") is not eligible: $why"; return
    fi
  elif [ "$tstate" = dispatched ] && [ "$nlive" -eq 1 ]; then T_AID="$live"
  elif [ "$tstate" = dispatched ] && [ "$nlive" -gt 1 ]; then _tick_refuse 5 "task $id has $nlive live attempts ($live); name one with --attempt"; return
  elif [ "$tstate" = done ] && [ -n "$winner" ]; then T_AID="$winner"
  else _tick_refuse 5 "no eligible attempt: $why"; return
  fi
  return 0
}

# _tick_lock <megadir> -- MIRRORS orchestrate.sh _lock / _lock_stale / _lock_reclaim / _unlock (lines 336 to
# 393): same path, same pid file, same dead-pid reclaim (pid file moved aside, then rmdir). Change it with them.
# Sets T_LOCK. Refuses 7 (held past the wait) or 8 (cannot create). `.orchestrate/` is kept after release:
# the driver owns that dir.
_tick_lock() {
  local mdir="$1" odir lk wait polls i=0 pid pid2 aside
  odir="$mdir/.orchestrate"; lk="$odir/flip.lock"
  { mkdir -p "$odir" 2>/dev/null && [ -d "$odir" ]; } || { _tick_refuse 8 "cannot create $odir"; return; }
  wait="${MEGA_TICK_LOCK_WAIT_SECS:-10}"
  polls="$(awk -v w="$wait" 'BEGIN { if (w !~ /^[0-9]+(\.[0-9]+)?$/) w = 10; p = w / 0.2; n = int(p); if (n < p) n++; print n }')"
  while :; do
    if mkdir "$lk" 2>/dev/null; then
      printf '%s\n' "$$" > "$lk/pid" || { rmdir "$lk" 2>/dev/null; _tick_refuse 8 "cannot write $lk/pid"; return; }
      T_LOCK="$lk"; return 0
    fi
    [ -d "$lk" ] || { _tick_refuse 8 "cannot create $lk (and it does not exist)"; return; }
    pid="$(_tick_lock_pid "$lk")"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      pid2="$(_tick_lock_pid "$lk")"
      if [ "$pid2" = "$pid" ]; then
        aside="$(mktemp "${TMPDIR:-/tmp}/mega-tick-pid.XXXXXX")" && mv -f "$lk/pid" "$aside" 2>/dev/null
        rmdir "$lk" 2>/dev/null && continue
      fi
      # A reclaim that could not complete counts as a poll, so the wait stays bounded.
      [ "$i" -ge "$polls" ] && { _tick_refuse 7 "$lk holds dead pid $pid and could not be reclaimed; once no driver is running: rmdir $(printf '%q' "$lk")"; return; }
      sleep 0.2; i=$((i + 1)); continue
    fi
    if [ "$i" -ge "$polls" ]; then
      if [ -n "$pid" ]; then _tick_refuse 7 "$lk is held by live pid $pid; retry once pid $pid exits"
      else _tick_refuse 7 "$lk is held with no pid file; once no driver is running: rmdir $(printf '%q' "$lk")"
      fi
      return
    fi
    sleep 0.2; i=$((i + 1))
  done
}

_tick_lock_pid() { local p; p="$(head -n1 "$1/pid" 2>/dev/null)"; [[ "$p" =~ ^[0-9]+$ ]] && printf '%s' "$p"; return 0; }

_tick_unlock() {
  local aside
  [ -n "${T_LOCK:-}" ] && [ -d "$T_LOCK" ] || { T_LOCK=""; return 0; }
  if [ "$(_tick_lock_pid "$T_LOCK")" = "$$" ]; then
    aside="$(mktemp "${TMPDIR:-/tmp}/mega-tick-pid.XXXXXX")" && mv -f "$T_LOCK/pid" "$aside" 2>/dev/null
    rmdir "$T_LOCK" 2>/dev/null
  fi
  T_LOCK=""
}

_tick_aside_tmp() {
  local aside
  [ -n "${T_TMP:-}" ] && [ -e "$T_TMP" ] || { T_TMP=""; return 0; }
  aside="$(mktemp "${TMPDIR:-/tmp}/mega-tick-tmp.XXXXXX")" && mv -f "$T_TMP" "$aside" 2>/dev/null
  T_TMP=""
}

_tick_cleanup() { _tick_aside_tmp; _tick_unlock; }

# _tick_line <roadmap> <id> <pr> <sha7> -- under the lock. Sets T_NR, T_OLD, T_NEW or refuses (3).
_tick_line() {
  local rm="$1" id="$2" pr="$3" sha7="$4" box_any done_re line nr=0 n=0 lid prim cr=$'\r' ann="" shape
  box_any="$(box_re)"; done_re="$(box_re done)"
  T_NR=""; T_OLD=""; T_NEW=""
  local other=""
  while IFS= read -r line || [ -n "$line" ]; do
    nr=$((nr + 1))
    [[ "$line" =~ ^${box_any}\ ${BOX_ID_RE} ]] || continue
    lid="${BASH_REMATCH[1]}"
    if [ "$lid" = "$id" ]; then n=$((n + 1)); T_NR="$nr"; T_OLD="$line"; continue; fi
    [ "$(box_name "${line:3:1}")" = done ] || continue
    if [[ "$line" =~ PR\ \#([0-9]+) ]] && [ "${BASH_REMATCH[1]}" = "$pr" ]; then other="$lid"; fi
  done < "$rm"
  [ "$n" -gt 0 ] || { _tick_refuse 3 "no ROADMAP line for $id"; return; }
  [ "$n" -eq 1 ] || { _tick_refuse 3 "$n ROADMAP lines carry $id; fix the duplicates by hand"; return; }
  case "$T_OLD" in *"$cr") _tick_refuse 3 "the $id line ends in CR (a CRLF file); convert the file to LF first"; return ;; esac
  local bx; bx="$(box_name "${T_OLD:3:1}")"
  [ "$bx" != parked ] || { _tick_refuse 3 "$id is parked; un-park it by hand before ticking"; return; }
  if [ "$bx" = done ]; then
    if [[ "$T_OLD" =~ PR\ \#([0-9]+) ]]; then
      prim="${BASH_REMATCH[1]}"
      [ "$prim" = "$pr" ] || { _tick_refuse 3 "$id is already ticked with PR #$prim, not #$pr; a wrong tick is fixed by git revert or a hand edit"; return; }
    fi
    shape="^${done_re} ${id}, PR #${pr}(, merged( [^ (]+)?)?( \\((.*)\\))? *\$"
    [[ "$T_OLD" =~ $shape ]] || { _tick_refuse 3 "the ticked $id line is not in the repairable shape '<box> $id, PR #N, merged <sha> (<note>)'; fix it by hand first"; return; }
    ann="${BASH_REMATCH[4]:-}"
  fi
  [ -z "$other" ] || { _tick_refuse 3 "PR #$pr already closes sub-goal $other; one PR closes one sub-goal"; return; }
  if [ -n "$ann" ] && [ "$T_HAS_NOTE" -eq 0 ] && [ "$T_KEEP" -eq 0 ]; then
    _tick_refuse 3 "the $id line carries an annotation; pass --keep-note to keep it or --note to replace it"; return
  fi
  T_NEW="- $(box_token done) $id, PR #$pr, merged $sha7"
  if [ "$T_KEEP" -eq 1 ]; then
    [ -n "$ann" ] || { _tick_refuse 3 "--keep-note given, but the $id line has no annotation to keep"; return; }
    if _tick_has_ctl "$ann"; then _tick_refuse 3 "the kept annotation holds a control character"; return; fi
    T_NEW="$T_NEW ($ann)"
  elif [ "$T_HAS_NOTE" -eq 1 ]; then
    T_NEW="$T_NEW ($T_NOTE)"
  fi
  return 0
}

# _tick_test_pause -- tests only: hold the lock after the line read while the pause file exists (30 s max).
_tick_test_pause() {
  [ "${MEGA_TICK_TEST:-}" = 1 ] && [ -n "${MEGA_TICK_TEST_PAUSE_FILE:-}" ] || return 0
  local i=0
  while [ -e "$MEGA_TICK_TEST_PAUSE_FILE" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
}

# _tick_write <roadmap> <megadir> -- temp + awk(ENVIRON) + chmod + mv. Refuses 8; the original stays intact.
# The note reaches awk through ENVIRON only: `awk -v` would expand a `\n` in it into a forged second line.
_tick_write() {
  local rm="$1" mdir="$2" mode
  T_TMP="$(mktemp "$mdir/.roadmap.tick.XXXXXX" 2>/dev/null)" || { T_TMP=""; _tick_refuse 8 "mktemp in $mdir failed"; return; }
  mode="$(stat -c %a "$rm" 2>/dev/null || stat -f %Lp "$rm" 2>/dev/null)"
  if ! TICK_NR="$T_NR" TICK_OLD="$T_OLD" TICK_LINE="$T_NEW" awk '
      NR == ENVIRON["TICK_NR"] + 0 { if ($0 != ENVIRON["TICK_OLD"]) bad = 1; else $0 = ENVIRON["TICK_LINE"] }
      { print }
      END { if (NR < ENVIRON["TICK_NR"] + 0) bad = 1; exit bad }' "$rm" > "$T_TMP"; then
    _tick_aside_tmp; _tick_refuse 8 "the $T_ID line changed between the read and the write; re-run"; return
  fi
  { [ -n "$mode" ] && chmod "$mode" "$T_TMP" && mv -f "$T_TMP" "$rm"; } || { _tick_aside_tmp; _tick_refuse 8 "writing $rm failed (chmod or mv)"; return; }
  T_TMP=""
  return 0
}

cmd_tick() {
  _tick_args "$@" || return $?
  local mroot croot mdir rm sha7 ref out rc
  mroot="$(_resolve_megagoals_root)"; croot="$(_resolve_code_root)"
  mdir="$mroot/$T_SLUG"; rm="$mdir/ROADMAP.md"
  T_LOCK=""; T_TMP=""; T_LEDGER_TOP=""
  trap _tick_cleanup EXIT

  _tick_ledger "$rm" || return $?
  _tick_audit "$croot" "$T_PR" || return $?
  sha7="${T_OID:0:7}"; ref="PR#$T_PR@$sha7"
  local audit="AUDIT $T_REPO PR #$T_PR MERGED base=$T_BASE head=$T_HEAD merge=$T_OID"
  local gb_raw gb branch_line
  gb_raw="$(_sub_branch "$mroot" "$T_SLUG" "$T_ID" "$croot")"
  gb="$(_tick_branch_norm "$gb_raw")"
  if [ -z "$gb" ]; then
    branch_line="BRANCH unverified $T_ID (no **Branch:** line in goals/$T_ID.md)"
  elif [ "$gb" = "$T_HEAD" ]; then
    branch_line="BRANCH ok $gb"
  elif [ "$T_HAS_OVERRIDE" -eq 1 ]; then
    branch_line="BRANCH override $(_tick_clean "$gb") != $T_HEAD"
    audit="$audit branch-override=$(printf '%q' "$T_OVERRIDE")"
    printf 'mega tick: branch-override %s != %s: %s\n' "$(_tick_clean "$gb")" "$T_HEAD" "$T_OVERRIDE" >&2
  else
    _tick_refuse 3 "goals/$T_ID.md names branch '$(_tick_clean "$gb")' but PR #$T_PR's head is '$T_HEAD'; check --pr, or pass --branch-override <reason>"
    return $?
  fi

  _tick_store "$T_ID" "$croot" "${T_LEDGER_TOP:-$(dirname -- "$rm")}" || return $?
  _tick_lock "$mdir" || return $?
  _tick_line "$rm" "$T_ID" "$T_PR" "$sha7" || { rc=$?; _tick_unlock; return "$rc"; }
  _tick_test_pause

  printf '%s\n%s\n' "$audit" "$branch_line"
  if [ "$T_NEW" = "$T_OLD" ]; then
    printf 'UNCHANGED %s\n' "$T_ID"
  else
    _tick_write "$rm" "$mdir" || { rc=$?; _tick_unlock; return "$rc"; }
    printf 'TICKED %s: %s\n' "$T_ID" "$T_NEW"
  fi
  _tick_unlock

  if [ -z "$T_STORE" ]; then printf '%s\n' "$T_AS_LINE"; return 0; fi
  if [ -n "$T_WIN_REF" ] && [ "$T_WIN_REF" != "$ref" ]; then
    printf 'ATTEMPT ref-mismatch %s recorded=%s now=%s\n' "$T_ID" "$(_tick_clean "$T_WIN_REF")" "$ref" >&2
  fi
  out="$(ATTEMPT_REGISTRY_DIR="$T_STORE" _tick_as commit-result "$T_ID" "$T_AID" "$ref" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'mega tick: REFUSED ROADMAP written; attempt-state.sh commit-result failed: %s\n' "$(_tick_clean "$out")" >&2
    printf 'mega tick: settle the record: re-run the same command with the same flags, or run: ATTEMPT_REGISTRY_DIR=%q bash %q commit-result %q %q %q\n' \
      "$T_STORE" "${ATTEMPT_STATE_BIN:-$BOX_DIR/../goal/attempt-state.sh}" "$T_ID" "$T_AID" "$ref" >&2
    return 6
  fi
  printf '%s\n' "$(_tick_clean "$out")"
  return 0
}

usage() { sed -n '2,140p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local first="${1:-}"
  case "$first" in
    status) shift; cmd_status "$@" ;;
    review) shift; cmd_review "$@" ;;
    report) shift; cmd_report "$@" ;;
    runs)   shift; cmd_runs "$@" ;;
    labels) shift; cmd_labels ;;
    tick)   shift; cmd_tick "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "mega.sh: unknown subcommand '$first'" >&2; usage >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
