#!/usr/bin/env bash
# board.sh -- the kit's cockpit board command. A verb that no case in main() names is looked up in the
# adapter manifests (lib/adapters/*/adapter.tsv, lib/adapters/README.md); the first adapter that declares it
# runs it. That is how the kanban bridge's verbs reach their scripts.
#
# The SOLE cockpit board command: it ABSORBS the render logic that used to live in ops-toolkit's
# `_meta/board` (the `priority` quadrant awk, single-repo) and `_meta/board-all` (the `boards.txt`
# registry walk + `priority matrix` cross-repo pivot), and ADDS a `queue` subcommand that emits an
# allow-listed overnight-runner queue. Base kanban render
# (board/next/set/states) is UNCHANGED and still delegates to `lib/board/backlog.sh` -- this file never
# reimplements it. `queue` delegates parsing to `lib/board/parse-board.sh`.
#
# The kit itself carries NO personal data: the consumer registry (`boards.txt`), the repo it
# describes, and any future bridge opt-ins are CONSUMER config this tool reads at runtime via
# `--repo-root <path>` / the `REPO_ROOT` env var (the kit's existing consumer pattern -- see
# lib/reflect/weekend-batch.sh's `_repo_root()` / `--repo-root`, lib/goal/mega-merge.sh's env-override
# precedent). Never invents a `CONSUMER_ROOT` var.
#
# Usage:
#   board.sh board  [--backlog-file <path>]                    single-repo kanban render
#   board.sh next   [--backlog-file <path>]                    first queued ID
#   board.sh get <ID> [--backlog-file <path>]                  one row's full status cell
#   board.sh set <ID> <state> [note] [--backlog-file <path>]   flip a row's state
#   board.sh dedupe <ID> [--backlog-file <path>]               collapse duplicate rows sharing
#                                                               one id down to one
#   board.sh lint [--backlog-file <path>]                      enumerate malformed board rows
#                                                               (cell count, dup ids, `\|`
#                                                               escapes, bad statuses); an
#                                                               enumerator, exits 0
#   board.sh add <title> [--notes T] [--mid V]... [--status S] [--section H] [--backlog-file <path>]
#                                                               file ONE new row: the next id is
#                                                               minted and written under the board
#                                                               lock, in the target table's own
#                                                               column count; prints the id. The
#                                                               one row-minting verb (capture and
#                                                               promote call it too).
#   board.sh normalize [--check] <board.md>                     pad short rows to their table's own
#                                                               column count (one-shot repair; keeps
#                                                               every id, idempotent)
#   board.sh states [--backlog-file <path>]                    legal state names
#   board.sh run <ID> [--backlog-file <path>] [--dir <megadir>] [--exec] [-- <orchestrate-args>]
#                                                               the single-row dispatch path:
#                                                               scaffold a minimal mega-goal dir
#                                                               (one `SG-<NN> , auto` ROADMAP line,
#                                                               POINTER_PROMPT seeded from the
#                                                               row's Item + Notes, the goals/
#                                                               plumbing) under the repo's
#                                                               megagoals convention, then print
#                                                               the exact `orchestrate.sh run
#                                                               <dir>` command. Never launches a
#                                                               session itself; --exec composes
#                                                               the launch. Forwards to
#                                                               lib/board/board-run.sh verbatim.
#   board.sh work [--json] [--idle-min N] [--code-root D] [--backlog-file <path>]  who is on what: board x mega x git x orca x ledger, read-only
#   board.sh priority [counts|brief|overview|full] [all|work|learn] [--backlog-file <path>]
#                                                               single-repo urgency x fit quadrant
#   board.sh promote [<n>... | all | reject <n>...]             review + flush backlog-stage's
#                                                               staged candidates onto the board
#                                                               (the human gate; absorbed the
#                                                               retired `add-backlog` entry per
#                                                               the kit naming decision, no alias).
#                                                               Forwards to lib/board/bin/add-backlog
#                                                               verbatim, behavior unchanged.
#
#   board.sh all board|next|states [--repo-root <path>] [--registry <path>]
#                                                               cross-repo render, grouped by repo
#   board.sh all priority [counts|brief|overview|full] [all|work|learn] [--repo-root <path>] [--registry <path>]
#                                                               each repo's quadrant, grouped by repo
#   board.sh all priority matrix [--repo-root <path>] [--registry <path>]
#                                                               cross-repo urgency x repo pivot table
#
# STALENESS WARNING (every `all` mode): each render reads a repo's BACKLOG.md out of a LOCAL
# checkout. A checkout behind its upstream returns rows that already shipped, and before this
# check nothing in the output said so. `_behind_count` now probes each registered checkout, marks
# a lagging repo's header `[STALE: N behind upstream]`, and prints one trailer naming every
# lagging repo. See `_behind_count` for the never-fetch, fail-open contract and its blind spot.
#
#   board.sh queue [--dry-run] [--repo-root <path>] [--registry <path>]
#                                                               walk the registry, parse every
#                                                               repo's BACKLOG.md via
#                                                               lib/board/parse-board.sh, emit
#                                                               slug<TAB>repo-path<TAB>pointer-path
#                                                               for every allow-listed `#queue{}`
#                                                               token on a `queued` row. `slug` is
#                                                               `<repo-name>__<ID>` (globally
#                                                               unique even though ID-NNN prefixes
#                                                               collide across some repos, see
#                                                               CLAUDE.md's dwarves-kit/ops-toolkit
#                                                               ID- note). `--dry-run` is accepted
#                                                               for forward-compat with a future
#                                                               write-capable extension; `queue`
#                                                               itself never mutates any BACKLOG.md
#                                                               regardless of the flag, so it is
#                                                               currently a documented no-op.
#
#   board.sh board  --with-mega [--mega-code-root <path>] [--backlog-file <path>]
#                                                               OPT-IN (kit-modularity sub-goal
#                                                               08): appends a trailing
#                                                               "MEGA ROLLUP" section listing, for
#                                                               every ACTIVE mega under
#                                                               <repo-root>/_meta/megagoals/*/
#                                                               (>=1 unchecked sub-goal box), the
#                                                               `lib/mega/mega.sh status <slug>
#                                                               --rollup-only` line (roadmap-vs-git
#                                                               reconciliation, drift-flagged --
#                                                               never a re-render of the roadmap's
#                                                               own `[x]`/`[ ]` prose). DEFAULT OFF
#                                                               on `board`: it
#                                                               makes real `gh` calls per
#                                                               sub-goal, so it must never run
#                                                               inside the byte-identical render
#                                                               non-regression NC (test-board.sh's
#                                                               NC-e) or slow down a plain render.
#                                                               `--mega-code-root <path>` overrides
#                                                               where the megas' OWN branches/PRs
#                                                               live (default: the same repo
#                                                               `--backlog-file`/`--repo-root`
#                                                               resolves to -- override it when a
#                                                               mega's ROADMAP.md lives in one repo
#                                                               but its sub-goals build in a
#                                                               DIFFERENT one, e.g. kit-modularity:
#                                                               ROADMAP in ops-toolkit, PRs/
#                                                               branches in dwarves-kit).
#
#   board.sh sweep --registry <path> [--poster <cmd>] [--preflight <cmd>] [--on-clean <cmd>]
#                   [--dry-run] ...
#                                                               one scheduled pass over every
#                                                               registry board: per-repo
#                                                               `sync`, change-only digest,
#                                                               `publish`, each adapter's legs,
#                                                               one digest post
#                                                               per cluster through the operator's
#                                                               --poster. Forwards to
#                                                               lib/sync/sweep/board-sweep; every
#                                                               flag is documented there.
#   board.sh sweep verify --registry <path> --run <cmd> | --last-tick [<repo>]
#                                                               prove a sweep wrote no board, or
#                                                               read what the newest tick did.
#   board.sh state-check --all [--strict] | --staged | --fix [--repo-root <dir>] [--states-file <path>]
#                                                               check the state values a repo stores in
#                                                               its own registry (default <repo>/_meta/states.toml):
#                                                               --all reports, --strict exits 1 on undeclared
#                                                               values or drift; --staged blocks NEW drift at
#                                                               commit (ALLOW_STATE_CHANGE="<reason>" lets one
#                                                               through); --fix rewrites drifted projection
#                                                               tokens. Exit 0 clean, 1 blocked, 2 internal
#                                                               error. Forwards to lib/board/state_check.py.
#   board.sh health run --registry <path> [--poster <cmd>] [--dry-run] [--force] ...
#   board.sh health record --repo <name> --rc <n>               the periodic board health digest per
#                                                               cluster (open, stale, archived since
#                                                               the last run, sync health per spoke);
#                                                               `sweep --health` runs it every tick.
#                                                               Forwards to lib/sync/sweep/board-health.
#   board.sh brief run --registry <path> [--poster <cmd>] [--dry-run] [--force] ...
#                                                               ONE message per cluster per day built on
#                                                               `health`: what needs the operator's decision,
#                                                               open incidents (from an --incidents hook),
#                                                               the boards every third day, one line of what
#                                                               the bots did; details follow as a second
#                                                               message. Forwards to lib/sync/sweep/board-brief.
#                                                               `health run` and `brief run` read their flags
#                                                               from --config FILE, $DWARVES_BOARD_CONFIG, or
#                                                               the board.json that `config data path config board.json` prints.
#
# Registry location: `--registry F` > $KIT_BOARDS_REGISTRY > `<repo-root>/_meta/boards.txt`.
# Registry format (`boards.txt`): whitespace-delimited `<name> <path-to-BACKLOG.md> [bridge]`
# rows, `#` comments, `~` expands to $HOME. A THIRD field, `bridge`, opts a repo into `mirror`:
# exactly the literal token `on` opts in; absent, `off`, or any other value stays OUT (default
# OFF -- a repo must explicitly opt in; sensitive repos like `trading`/`family-office` must never
# be `on`). `board`/`next`/`priority`/`states`/`queue` never read this field (they only ever
# consumed the first two columns, per this command's own forward-compat design), so adding it is a
# zero-code-change, non-regressing registry format extension.
#
# --repo-root resolution precedence (cross-repo `all`/`queue`/`mirror`/`status` modes only): the
# `--repo-root` flag, else the `REPO_ROOT` env var, else `git rev-parse --show-toplevel` of the
# CURRENT cwd, else cwd itself. The single-repo subcommands never need --repo-root; the shim that
# calls them always passes an explicit --backlog-file instead.
#
# DWARVES_KIT overrides where lib/board/backlog.sh + lib/board/parse-board.sh are found
# relative to this file (they are always siblings in lib/, so this only matters if board.sh is
# copied standalone).

set -euo pipefail

BOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_SH="$BOARD_DIR/backlog.sh"
PARSE_BOARD_SH="$BOARD_DIR/parse-board.sh"
BOARD_RUN_SH="$BOARD_DIR/board-run.sh"
BOARD_SWEEP_SH="$(cd "$BOARD_DIR/.." && pwd)/sync/sweep/board-sweep"                  # lib/sync/sweep/
BOARD_SWEEP_VERIFY_SH="$(cd "$BOARD_DIR/.." && pwd)/sync/sweep/board-sweep-verify"
BOARD_STATE_CHECK_PY="$BOARD_DIR/state_check.py"
BOARD_HEALTH_PY="$(cd "$BOARD_DIR/.." && pwd)/sync/sweep/board-health"
BOARD_BRIEF_PY="$(cd "$BOARD_DIR/.." && pwd)/sync/sweep/board-brief"
KIT_LIB="$(cd "$BOARD_DIR/.." && pwd)"  # lib/, one level up from lib/board/; script-local, never read from the environment
export KIT_LIB
# shellcheck source=board-lib.sh
. "$BOARD_DIR/board-lib.sh" || exit 1

[ -f "$BACKLOG_SH" ]         || { echo "board: lib/board/backlog.sh not found at $BACKLOG_SH" >&2; exit 1; }
[ -f "$PARSE_BOARD_SH" ]     || { echo "board: lib/board/parse-board.sh not found at $PARSE_BOARD_SH" >&2; exit 1; }
[ -f "$BOARD_RUN_SH" ]       || { echo "board: lib/board/board-run.sh not found at $BOARD_RUN_SH" >&2; exit 1; }

# _behind_count <path-to-backlog-md> -- how many commits that file's checkout trails its upstream.
#
# NEVER fetches. A cockpit render runs many times a day, so one network round trip per registered
# repo per render is a cost the operator would pay constantly for a check that helps rarely. This
# compares HEAD against the upstream ref the clone ALREADY holds. The blind spot that leaves is
# real and deliberate: a clone nobody has fetched reports 0 behind and renders clean, however far
# origin has moved. Only a fetch can close that, and a fetch is what this check refuses to do.
#
# Fails open. No upstream, a detached HEAD, a path outside any git repo, or any other git error
# all yield NOTHING, and the caller then renders that repo exactly as it did before. An odd
# checkout must never break the render of the other sixteen.
#
# Prints the count only when the checkout is behind. A current repo prints nothing, so the caller
# treats "behind" and "unknown" the same way, and a fully current estate renders byte for byte as
# it did before this check existed.
_behind_count() {
  local dir="${1%/*}" n
  [ "$dir" = "$1" ] && dir="."
  n="$(git -C "$dir" rev-list --count "HEAD..@{u}" 2>/dev/null)" || return 0
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  [ "$n" -gt 0 ] && printf '%s' "$n"
  return 0
}

# _stale_marker <behind-count-or-empty> -- the per-repo header suffix, empty when nothing is wrong.
_stale_marker() {
  [ -n "${1:-}" ] || return 0
  printf ' [STALE: %s behind upstream]' "$1"
}

# _stale_trailer <name(N)>... -- one summary line naming every lagging checkout.
#
# The per-repo marker and this trailer both ship, and each answers a question the other cannot.
# The marker sits on the header a reader is already looking at, so a single repo's rows can never
# be read as current by accident. The trailer sits at the end, so an operator skimming seventeen
# repos learns which ones to distrust without scrolling back through the whole render. Neither
# prints when the estate is current.
# Callers pass "${stale[@]:-}", which under `set -u` on bash 3.2 hands this one EMPTY argument
# rather than none, so the guard tests the joined string instead of the argument count.
_stale_trailer() {
  local joined="$*"
  [ -n "$joined" ] || return 0
  printf '\nSTALE CHECKOUTS, rows above may be out of date: %s\n' "$joined"
}

# ---------------------------------------------------------------------------
# Priority render (single repo) -- verbatim port of the awk program from ops-toolkit's
# `_meta/board` `priority` branch. Byte-identical output is the load-bearing non-regression
# contract (see this module's proof-of-done); do not "clean up" this awk without re-running that proof.
# ---------------------------------------------------------------------------
_priority_render() {  # <backlog-file> <mode> [class]
  local file="$1" mode="${2:-overview}" class="${3:-all}"
  case "$mode" in counts|brief|overview|full) ;; *) mode="overview" ;; esac
  # class: `all` (default) renders every queued row; `work` hides learn-side rows
  # (Item cell tagged #eval/#triage/#absorb/#learning); `learn` shows only them.
  # IN FLIGHT is never filtered -- it reports what is running, not what to pick.
  case "$class" in all|work|learn) ;; *) class="all" ;; esac
  awk -F'|' -v mode="$mode" -v cls="$class" '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    function shorten(t){ if(length(t)>52) return substr(t,1,49)"..."; return t }
    $0 ~ /^\| *[A-Z]+-[0-9]+ *\|/ {
      id=trim($2); title=shorten(trim($3)); status=trim($(NF-1)); line=$0
      split(status,a,/[ \[(]/); lead=a[1]
      if (lead=="executing"||lead=="claimed"||lead=="speccing"||lead=="validated"){
        inflight[++nf]=sprintf("  %-8s %s  [%s]", id, title, lead); next }
      if (lead!="queued") next
      lcls=(trim($3) ~ /#(eval|triage|absorb|learning)([^a-z0-9-]|$)/)
      if(cls=="work"&&lcls){ hidden++; next }
      if(cls=="learn"&&!lcls){ hidden++; next }
      u=(line~/#u-hi/)?"hi":(line~/#u-mid/)?"mid":(line~/#u-lo/)?"lo":"?"
      f=(line~/#f-hi/)?"hi":(line~/#f-mid/)?"mid":(line~/#f-lo/)?"lo":"?"
      stripped=line; gsub(/#[uf]-(hi|mid|lo)/,"",stripped)
      wt=""; if(match(stripped,/#[a-z][a-z0-9-]*/)) wt="  "substr(stripped,RSTART,RLENGTH)
      dl=""; if(tolower(line)~/deadline/) dl="  [deadline]"
      row=sprintf("  %-8s %s%s%s", id, title, wt, dl)
      if(u=="hi"&&f=="hi") t1[++n1]=row
      else if(u=="hi")     t2[++n2]=row
      else if(f=="hi")     t3[++n3]=row
      else                 t4[++n4]=row
      if(u=="?"||f=="?") unclass++
    }
    END{
      C=(mode=="counts"); B=(mode=="brief"); F=(mode=="full")
      if(nf>0){ printf "IN FLIGHT        %d\n", nf; if(!C){ for(i=1;i<=nf;i++) print inflight[i]; print "" } }
      printf "DO NOW           (u-hi  f-hi)         %d\n", n1+0; if(!C) for(i=1;i<=n1;i++) print t1[i]
      printf "URGENT, HARDER   (u-hi  f-mid|lo)     %d\n", n2+0; if(!C) for(i=1;i<=n2;i++) print t2[i]
      printf "QUICK WINS       (u-lo|mid  f-hi)     %d\n", n3+0; if(!C&&!B) for(i=1;i<=n3;i++) print t3[i]
      printf "THE REST         (other queued)       %d\n", n4+0
      if(!C&&!B){ cap=(F?0:15); lim=(cap>0&&n4>cap)?cap:n4
        for(i=1;i<=lim;i++) print t4[i]
        if(cap>0&&n4>cap) printf "  +%d more  (board priority full)\n", n4-cap }
      if(unclass>0&&!C) printf "\n(%d queued row(s) missing #u/#f -- classify them)\n", unclass
      if(hidden>0&&!C) printf "\n(%d %s row(s) hidden -- priority %s %s shows them)\n", hidden, (cls=="work"?"learn-class":"work-class"), mode, (cls=="work"?"learn":"all")
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Priority matrix (cross-repo) -- verbatim port of `_meta/board-all`'s `priority matrix` branch.
# ---------------------------------------------------------------------------
_priority_matrix() {  # <registry-file>
  local registry="$1"
  {
    while read -r name path _rest; do
      [ -z "${name:-}" ] && continue
      case "$name" in \#*) continue ;; esac
      path="${path/#\~/$HOME}"
      [ -f "$path" ] || continue
      awk -F'|' -v repo="$name" '
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
        function letter(x){ return (x=="hi")?"h":(x=="mid")?"m":(x=="lo")?"l":"?" }
        $0 ~ /^\| *[A-Z]+-[0-9]+ *\|/ {
          id=trim($2); title=trim($3); status=trim($(NF-1)); line=$0
          split(status,a,/[ \[(]/); lead=a[1]
          if(lead=="executing"||lead=="claimed"||lead=="speccing"||lead=="validated"){ exec++; next }
          if(lead!="queued") next
          u=(line~/#u-hi/)?"hi":(line~/#u-mid/)?"mid":(line~/#u-lo/)?"lo":"?"
          f=(line~/#f-hi/)?"hi":(line~/#f-mid/)?"mid":(line~/#f-lo/)?"lo":"?"
          if(u=="hi") hi++; else if(u=="mid") mid++; else if(u=="lo") lo++; else unt++
          if(u!="?") printf "I\t%s\t%s\t%s\t[%s/%s]\t%s\n", repo, u, id, letter(u), letter(f), title
        }
        END{ printf "C\t%s\t%d\t%d\t%d\t%d\t%d\n", repo, hi+0,mid+0,lo+0,unt+0,exec+0 }
      ' "$path"
    done < "$registry"
  } | awk -F'\t' '
    $1=="C" { repo[++nr]=$2; H[$2]=$3; M[$2]=$4; L[$2]=$5; U[$2]=$6; X[$2]=$7
              tH+=$3; tM+=$4; tL+=$5; tU+=$6; tX+=$7
              if(length($2)>w) w=length($2)
              if($3+$4+$5+$6+$7>0) shown[$2]=1 ; next }
    $1=="I" { key=$2 SUBSEP $3; items[key]=items[key] sprintf("  %-8s %s  %s\n",$4,$5,$6) }
    END {
      if(w<6) w=6
      # --- matrix table ---
      printf "Priority matrix (queued rows, all repos) -- urgency x repo\n\n"
      printf "%-*s  %6s %6s %6s %9s %10s\n", w,"repo","HIGH u","MID u","LOW u","untagged","executing"
      for(i=1;i<=nr;i++){ r=repo[i]; if(!shown[r]) continue
        printf "%-*s  %6d %6d %6d %9d %10d\n", w,r,H[r],M[r],L[r],U[r],X[r] }
      printf "%-*s  %6d %6d %6d %9d %10d\n", w,"total queued",tH,tM,tL,tU,tX
      printf "\nLegend: [u/f] = urgency / fit. h=high, m=mid, l=low.\n"
      # --- lists by urgency tier ---
      split("hi mid lo",order," "); split("HIGH MID LOW",label," ")
      for(o=1;o<=3;o++){ tier=order[o]
        # tier total
        tot=0; for(i=1;i<=nr;i++){ r=repo[i]; tot += (tier=="hi"?H[r]:tier=="mid"?M[r]:L[r]) }
        printf "\n--\n%s urgency (%d rows)\n", label[o], tot
        for(i=1;i<=nr;i++){ r=repo[i]; key=r SUBSEP tier
          if(items[key]!=""){ printf "\n%s\n%s", r, items[key] } }
      }
    }
  '
}

# ---------------------------------------------------------------------------
# Single-repo dispatch (mirrors ops-toolkit's old `_meta/board`).
# ---------------------------------------------------------------------------
cmd_board_single() {
  _parse_flags "$@"
  local args=("${POSITIONAL[@]}")
  [ ${#args[@]} -gt 0 ] || args=(board)
  [ -n "$OPT_BACKLOG_FILE" ] || { echo "board: --backlog-file is required for single-repo commands" >&2; return 64; }
  [ -f "$OPT_BACKLOG_FILE" ] || { echo "board: no BACKLOG.md at $OPT_BACKLOG_FILE" >&2; return 1; }

  if [ "${args[0]}" = "priority" ]; then
    local pmode="${args[1]:-overview}" pclass="${args[2]:-all}"
    case "$pmode" in all|work|learn) pclass="$pmode"; pmode="overview" ;; esac
    _priority_render "$OPT_BACKLOG_FILE" "$pmode" "$pclass"
    return 0
  fi
  local rc
  if BACKLOG_FILE="$OPT_BACKLOG_FILE" bash "$BACKLOG_SH" "${args[@]}"; then rc=0; else rc=$?; fi
  # --with-mega is OPT-IN and only fires for the default `board` render (never `next`/`set`/
  # `states`), so the byte-identical render non-regression NC (test-board.sh's NC-e, which never
  # passes --with-mega) is untouched by construction.
  if [ "$OPT_WITH_MEGA" -eq 1 ] && [ "${args[0]}" = "board" ]; then
    local repo_root; repo_root="$(_repo_root_for "$OPT_BACKLOG_FILE")"
    local code_root="${OPT_MEGA_CODE_ROOT:-$repo_root}"
    local rollups; rollups="$(_mega_rollups "$repo_root" "$code_root")"
    [ -n "$rollups" ] && printf '\nMEGA ROLLUP:\n%s\n' "$rollups"
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# Cross-repo dispatch (mirrors ops-toolkit's old `_meta/board-all`).
# ---------------------------------------------------------------------------
cmd_all() {
  _parse_flags "$@"
  local args=("${POSITIONAL[@]}")
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-${KIT_BOARDS_REGISTRY:-$repo_root/_meta/boards.txt}}"
  [ -f "$registry" ] || { echo "board all: no registry at $registry" >&2; return 1; }

  local sub="${args[0]:-board}"
  local mode="${args[1]:-overview}"
  local class="${args[2]:-all}"
  case "$mode" in all|work|learn) class="$mode"; mode="overview" ;; esac
  local stale=()   # "<name>(<N> behind)" per lagging checkout, feeds _stale_trailer

  if [ "$sub" = "priority" ] && [ "$mode" = "matrix" ]; then
    _priority_matrix "$registry"
    # The matrix pivots rows from the same checkouts, so it owes the same warning. It renders one
    # table rather than per-repo headers, so the trailer is the only place the warning fits.
    local mname mpath mbehind
    while read -r mname mpath _rest; do
      [ -z "${mname:-}" ] && continue
      case "$mname" in \#*) continue ;; esac
      mpath="${mpath/#\~/$HOME}"
      [ -f "$mpath" ] || continue
      mbehind="$(_behind_count "$mpath")"
      [ -n "$mbehind" ] && stale+=("${mname}(${mbehind} behind)")
    done < "$registry"
    _stale_trailer "${stale[@]:-}"
    return 0
  fi

  if [ "$sub" = "priority" ]; then
    while read -r name path _rest; do
      [ -z "${name:-}" ] && continue
      case "$name" in \#*) continue ;; esac
      path="${path/#\~/$HOME}"
      if [ ! -f "$path" ]; then
        printf '\n=== %s ===\n(MISSING: %s)\n' "$name" "$path"
        continue
      fi
      local behind; behind="$(_behind_count "$path")"
      [ -n "$behind" ] && stale+=("${name}(${behind} behind)")
      local out; out="$(_priority_render "$path" "$mode" "$class" 2>&1 || true)"
      printf '\n=== %s%s ===\n%s\n' "$name" "$(_stale_marker "$behind")" "$out"
    done < "$registry"
    _stale_trailer "${stale[@]:-}"
    return 0
  fi

  while read -r name path _rest; do
    [ -z "${name:-}" ] && continue
    case "$name" in \#*) continue ;; esac
    path="${path/#\~/$HOME}"
    if [ ! -f "$path" ]; then
      printf '\n=== %s ===\n(MISSING: %s)\n' "$name" "$path"
      continue
    fi
    local behind; behind="$(_behind_count "$path")"
    [ -n "$behind" ] && stale+=("${name}(${behind} behind)")
    local out; out="$(BACKLOG_FILE="$path" bash "$BACKLOG_SH" "$sub" 2>&1 || true)"
    if [ "$sub" = "next" ]; then
      printf '%-14s %s%s\n' "$name" "$out" "$(_stale_marker "$behind")"
    else
      printf '\n=== %s%s ===\n%s\n' "$name" "$(_stale_marker "$behind")" "$out"
    fi
  done < "$registry"
  _stale_trailer "${stale[@]:-}"
}

# ---------------------------------------------------------------------------
# queue -- the new overnight-runner feed. Never mutates any BACKLOG.md.
# ---------------------------------------------------------------------------
cmd_queue() {
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-${KIT_BOARDS_REGISTRY:-$repo_root/_meta/boards.txt}}"
  [ -f "$registry" ] || { echo "queue: no registry at $registry" >&2; return 1; }

  # `queue` is read-only by construction (it never writes to any BACKLOG.md, unlike `set`), so
  # --dry-run has no additional effect today; it is accepted now as forward-compat surface for a
  # future write-capable extension (e.g. flipping a picked row to `claimed`), documented rather
  # than silently ignored.
  if [ "$OPT_DRY_RUN" -eq 1 ]; then
    echo "queue: --dry-run has no additional effect (queue never mutates any BACKLOG.md)" >&2
  fi

  local total=0
  while read -r name path _rest; do
    [ -z "${name:-}" ] && continue
    case "$name" in \#*) continue ;; esac
    path="${path/#\~/$HOME}"
    if [ ! -f "$path" ]; then
      echo "queue: skip repo '$name': registered BACKLOG.md missing at $path" >&2
      continue
    fi
    local rroot; rroot="$(_repo_root_for "$path")"
    while IFS=$'\t' read -r id rr resolved; do
      [ -n "$id" ] || continue
      printf '%s\t%s\t%s\n' "${name}__${id}" "$rr" "$resolved"
      total=$((total+1))
    done < <(bash "$PARSE_BOARD_SH" queue-rows "$path" "$name" "$rroot")
  done < "$registry"

  echo "queue: ${total} rows" >&2
  return 0
}

# board sync [--dry-run] [--sources a,b] ... -- two-way spoke sync (the `sync`
# module, lib/sync/). Consumer shims append --backlog-file; translate it to the
# engine's --backlog. Config resolution happens HERE, per the kit's stage-taxonomy decision: a command
# reads [sync] keys via the ONE resolver at invocation and hands the python
# init: scaffold the board files adopt does not cover. `kit adopt` seeds
# .kit.toml and wires modules; the board itself (_meta/BACKLOG.md + the _meta/
# board shim) was a copy-by-hand step, which is exactly how a new repo ends up
# half-registered. Idempotent: existing files are never touched.
cmd_init() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local meta="$root/_meta"
  mkdir -p "$meta"
  if [ ! -f "$meta/BACKLOG.md" ]; then
    printf '# BACKLOG\n\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n' \
      > "$meta/BACKLOG.md"
    echo "created _meta/BACKLOG.md (empty board; \`board sync\` intakes open issues as rows)"
  else
    echo "kept existing _meta/BACKLOG.md"
  fi
  if [ ! -f "$meta/board" ]; then
    cat > "$meta/board" <<'SHIM'
#!/usr/bin/env bash
# _meta/board -- one-line shim exec'ing the dwarves-kit `board` command against
# THIS repo's own BACKLOG.md. Scaffolded by `board init`; logic lives in the kit.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
exec bash "${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/bin/board" "${@:-board}" --backlog-file "$here/BACKLOG.md"
SHIM
    chmod +x "$meta/board"
    echo "created _meta/board shim"
  else
    echo "kept existing _meta/board"
  fi
  [ -f "$root/.kit.toml" ] && grep -q '^\[sync\]' "$root/.kit.toml" 2>/dev/null || {
    echo "next: add a [sync] section to .kit.toml, e.g."
    printf '  [sync]\n  apps = "github"\n'
  }
}

# capture: file ONE item from a working session -- a queued row on the board,
# pushed to the configured spokes immediately, and (when the github app is on)
# the new issue's URL printed and put on the clipboard. This is the
# harness-agnostic "file this" verb: Claude Code, Codex and pi all just
# run `board capture "<title>" [-b <notes>]`.
cmd_capture() {
  local backlog="" title="" notes="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --backlog-file) backlog="${2:-}"; shift 2 ;;
      -b|--notes) notes="${2:-}"; shift 2 ;;
      *) if [ -z "$title" ]; then title="$1"; else title="$title $1"; fi; shift ;;
    esac
  done
  [ -n "$title" ] || { echo "usage: board capture \"<title>\" [-b <notes>]" >&2; exit 2; }
  backlog="${backlog:-$PWD/_meta/BACKLOG.md}"
  [ -f "$backlog" ] || { echo "board capture: no board at $backlog (run \`board init\`)" >&2; exit 2; }
  # The mint and the write run in the one row-minting verb (`backlog.sh add`), under the
  # shared per-board lock (sync_core.board_lock, the same file promote/sync/set flock), so two
  # sessions capturing at once serialize instead of minting the same id. The row takes the
  # target table's own column count.
  local bid
  bid="$(BACKLOG_FILE="$backlog" bash "$BACKLOG_SH" add --notes "${notes:-filed via board capture}" -- "$title")" \
    || { echo "board capture: could not add the row to $backlog" >&2; exit 1; }
  # sync in a subshell: cmd_sync ends in exec and must not replace this shell.
  ( cmd_sync --backlog-file "$backlog" ) || true
  local rid=""
  rid="$(python3 - "$backlog" "$bid" "$(bash "$BOARD_DIR/../config/data-path.sh" path state backlog-sync)" <<'PY'
import json, re, sys
from pathlib import Path
slug = re.sub(r"[^a-zA-Z0-9]+", "-", str(Path(sys.argv[1]).resolve())).strip("-")
p = Path(sys.argv[3]) / slug / "github.state.json"
try:
    print(json.loads(p.read_text())["map"][sys.argv[2]]["rid"])
except Exception:
    pass
PY
)"
  echo "filed: $bid"
  if [ -n "$rid" ]; then
    local url
    url="$(cd "$(dirname "$backlog")/.." && gh issue view "$rid" --json url --jq .url 2>/dev/null || true)"
    if [ -n "$url" ]; then
      printf '%s' "$url" | pbcopy 2>/dev/null || true
      echo "issue: $url  (link on clipboard)"
      # enrich: what already exists nearby, so duplicates get merged early
      (cd "$(dirname "$backlog")/.." && gh issue list --state all --search "$title" \
        --limit 4 --json number,title \
        --jq '.[] | "  #\(.number) \(.title)"' 2>/dev/null | grep -v "^  #$rid " || true) \
        | sed '1s/^/related existing issues:\n/' | head -5
    fi
  else
    echo "note: no github spoke configured (or sync skipped); row is on the board"
  fi
}

# _sync_note_shadow <section.key> <root-value> -- says so on stderr when a project .kit.toml set a
# root-only key to something else, so a repo that used to carry it learns why it is ignored.
_sync_note_shadow() {
  local proj; proj="$(kit_config_get "$1" "")"
  [ -n "$proj" ] && [ "$proj" != "$2" ] \
    && echo "board sync: ignoring $1 from the project .kit.toml (root-only key); set it in $(kit_config_operator)" >&2
  return 0
}

# engine plain flags (the engine never reads TOML). User-passed flags land
# after the config-derived ones, so argparse lets them win.
cmd_sync() {
  local backlog="" fwd=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --backlog-file) backlog="${2:-}"; shift 2 ;;
      *) fwd+=("$1"); shift ;;
    esac
  done
  backlog="${backlog:-$PWD/_meta/BACKLOG.md}"
  [ -f "$backlog" ] || { echo "board sync: no backlog at $backlog" >&2; exit 2; }
  . "$BOARD_DIR/../config/kit-config.sh"
  . "$BOARD_DIR/../sync/adapters.sh"
  # git-aware repo root: BACKLOG.md lives at _meta/ in some repos and at repo
  # root in others; _repo_root_for handles both
  KIT_PROJECT_ROOT="$(_repo_root_for "$backlog")"
  export KIT_PROJECT_ROOT
  local args=(--backlog "$backlog") v
  v="$(kit_config_get sync.apps "")"
  [ -n "$v" ] || v="$(kit_config_get sync.surfaces "")"  # legacy alias
  [ -n "$v" ] || v="$(kit_config_get sync.sources "")"   # older legacy alias
  if [ -z "$v" ]; then
    echo "board sync: no [sync] apps configured in $KIT_PROJECT_ROOT/.kit.toml" >&2
    printf '  add e.g.:\n  [sync]\n  apps = "<app>"\n' >&2
    exit 2
  fi
  args+=(--apps "$v")
  local fk
  v="$(kit_config_get sync.scope_exit_cap "")"; [ -n "$v" ] && args+=(--scope-exit-cap "$v")
  # only for a repo whose archive is not BACKLOG-archive.md beside the board
  v="$(kit_config_get sync.archive_file "")"; [ -n "$v" ] && args+=(--archive-file "$v")
  # The adapter manifests (lib/adapters/*/adapter.tsv) declare the rest: per-app filter keys, one engine
  # flag per `opt` row, one env secret per `secret` row. A manifest error is global and loud. An `opt`
  # row of scope root and every `secret` row read the operator and kit-root files only, because a
  # project .kit.toml rides inside an untrusted PR and these pick the host and the secret it receives.
  local rows rdir rflag rkey rscope rapp rmode renv rval fks
  rows="$(adapters_rows app)" || exit 1
  while IFS=$'\t' read -r rdir rapp rmode; do
    [ -n "$rapp" ] || continue
    case "$rmode" in
      two-way) fks="only_tags skip_tags intake" ;;
      create-only) fks="only_tags skip_tags" ;;
      *) fks="" ;;
    esac
    for fk in $fks; do
      v="$(kit_config_get "sync.${rapp//-/_}_${fk}" "")"
      [ -n "$v" ] && args+=(--filter "${rapp}:${fk}=${v}")
    done
  done <<< "$rows"
  rows="$(adapters_rows opt)" || exit 1
  while IFS=$'\t' read -r rdir rflag rkey rscope _; do
    [ -n "$rflag" ] || continue
    if [ "$rscope" = root ]; then
      v="$(kit_config_get_root "sync.$rkey" "")"; _sync_note_shadow "sync.$rkey" "$v"
    else
      v="$(kit_config_get "sync.$rkey" "")"
    fi
    [ -n "$v" ] && args+=("--$rflag" "$v")
  done <<< "$rows"
  # a secret rides the environment, never argv (ps leaks argv): root-only ref, Keychain-cached read
  # first, raw `op read` as the fallback, skipped when the variable is already set
  rows="$(adapters_rows secret)" || exit 1
  while IFS=$'\t' read -r rdir renv rkey; do
    [ -n "$renv" ] || continue
    v="$(kit_config_get_root "sync.$rkey" "")"; _sync_note_shadow "sync.$rkey" "$v"
    if [ -n "$v" ] && [ -z "${!renv:-}" ]; then
      if command -v secret-cache-read >/dev/null 2>&1; then
        rval="$(secret-cache-read --ttl 21600 "$renv" "$v")"
      else
        rval="$(op read "$v")"
      fi
      export "$renv=$rval"
    fi
  done <<< "$rows"
  exec python3 "$BOARD_DIR/../sync/backlog_sync.py" "${args[@]}" ${fwd[@]+"${fwd[@]}"}
}

# publish: the git leg of the sync-engine's intake -> publish -> relay sequencing.
# `board sync` mutates the board file in place; without this leg a scheduled
# runner (the estate's hourly sweeper) leaves every checkout permanently
# dirty, spoke writes invisible off-host and every ff-pull blocked
# Stages ONLY the board file; other dirt is untouched.
#
# COMMIT-FIRST by design (battery 2026-09-01): committing before any pull
# means a rebase conflict can never stage conflict markers into the board
# file, and a failed rebase aborts back to the committed state instead of
# wedging the checkout. Exit codes: 0 published or clean no-op; 2 usage or
# fence refusal; 3 committed locally but NOT on the remote (push/rebase
# failure) -- callers treat 3 as a monitoring signal, the commit is safe.
cmd_publish() {
  local backlog="" push=1
  while [ $# -gt 0 ]; do case "$1" in
    --backlog-file) backlog="${2:-}"; shift 2 ;;
    --no-push) push=0; shift ;;
    *) echo "publish: unknown arg: $1" >&2; return 64 ;;
  esac; done
  backlog="${backlog:-$PWD/_meta/BACKLOG.md}"
  [ -f "$backlog" ] || { echo "board publish: no backlog at $backlog" >&2; return 2; }
  # physical path (pwd -P): the worktree fence must not be evadable through
  # a symlinked path, matching the sync engine's resolve() fence
  local absdir; absdir="$(cd "$(dirname "$backlog")" && pwd -P)"
  case "$absdir" in
    */.claude/worktrees/*)
      echo "board publish: refusing a worktree checkout ($backlog); publish" >&2
      echo "  runs from the canonical checkout only (same fence as sync)." >&2
      return 2 ;;
  esac
  local root; root="$(git -C "$absdir" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "board publish: $backlog is not in a git repo" >&2; return 2; }
  local branch; branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)" \
    || { echo "board publish: detached HEAD; refusing to publish" >&2; return 2; }
  local rel="${absdir}/$(basename "$backlog")"; rel="${rel#"$root"/}"
  # :(literal) everywhere: a board path with glob characters must never
  # widen the pathspec to unrelated files in an auto-pushed commit
  local spec=":(literal)$rel"
  if git -C "$root" diff --quiet -- "$spec" 2>/dev/null; then
    echo "board publish: no board changes in $rel"
    return 0
  fi
  # a scheduled runner must never hang on a credential or hostkey prompt
  local -a G=(git -c core.askPass=true -C "$root")
  export GIT_TERMINAL_PROMPT=0
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"
  "${G[@]}" add -- "$spec"
  if ! "${G[@]}" commit --quiet -m "chore(board): publish spoke updates" -- "$spec"; then
    echo "board publish: commit failed for $rel" >&2
    return 1
  fi
  echo "board publish: committed $rel"
  [ "$push" -eq 1 ] || return 0
  # pinned refspec: only ever the current branch, never a surprise target
  if "${G[@]}" push --quiet origin "HEAD:refs/heads/$branch" 2>/dev/null; then
    echo "board publish: pushed"
    return 0
  fi
  # non-ff or auth failure: try one rebase, abort hard on any conflict so
  # the checkout is never left mid-rebase (the commit survives either way)
  if ! "${G[@]}" pull --rebase --autostash --quiet origin "$branch" 2>/dev/null \
      || [ -n "$("${G[@]}" ls-files -u -- "$spec" 2>/dev/null)" ]; then
    "${G[@]}" rebase --abort >/dev/null 2>&1 || true
    echo "board publish: WARN remote diverged and rebase did not apply cleanly;" >&2
    echo "  commit is local, checkout restored, will retry next publish" >&2
    return 3
  fi
  # A rebase can apply cleanly onto a genuine row-id collision instead
  # of conflicting on it, because consumer boards mark BACKLOG.md
  # `merge=union` -- two sessions each minting an id from a clone that never
  # fetched land both rows, silently. `parse_board` then keeps only the FIRST
  # occurrence per id, so the second row becomes invisible to sync while the
  # snapshot still maps the id to whichever row minted last, mispairing the
  # two. Only the post-rebase file can carry this; a clean ff push cannot
  # introduce a collision the pre-push diff didn't already have.
  local dup_ids
  dup_ids="$(grep -oE '^\| [A-Z][A-Z0-9]*-[0-9]+ \|' "$root/$rel" 2>/dev/null \
    | tr -d '| ' | sort | uniq -d | tr '\n' ' ')"
  dup_ids="${dup_ids% }"
  if [ -n "$dup_ids" ]; then
    echo "board publish: WARN duplicate row ids after rebase: $dup_ids; not pushing, fix by hand" >&2
    return 3
  fi
  if "${G[@]}" push --quiet origin "HEAD:refs/heads/$branch" 2>/dev/null; then
    echo "board publish: pushed (after rebase)"
    return 0
  fi
  echo "board publish: WARN push failed (auth?); commit is local, next publish retries" >&2
  return 3
}

# board promote [list | <n>... | all | reject <n>...] [--backlog-file <path>]
# -- the human gate. Consumer shims scaffolded by `cmd_init` ALWAYS append
# `--backlog-file`, and `bin/add-backlog` understands no flags at all: it reads
# BACKLOG_STAGE_BACKLOG / BACKLOG_STAGE_STAGING with a cwd-derived fallback.
# Forwarding argv verbatim therefore broke twice over -- the flag reached
# add-backlog's `int(x)` selection parse (so `promote <n>` and `promote reject
# <n>` always failed usage, leaving `all` as the only working path and reducing
# the review gate to all-or-nothing), and the operator's explicit target was
# silently dropped, so promote resolved its write target from cwd and could land
# rows in a DIFFERENT repo's board than the shim addressed. Translate here, the
# same way cmd_sync already does for its engine. Fixes #443.
cmd_promote() {
  local backlog="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --backlog-file) backlog="${2:-}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [ -n "$backlog" ]; then
    export BACKLOG_STAGE_BACKLOG="$backlog"
    # staging is the board's sibling by construction (cmd_init scaffolds both
    # into _meta/), so derive rather than adding a second flag to every shim.
    export BACKLOG_STAGE_STAGING="${BACKLOG_STAGE_STAGING:-$(dirname "$backlog")/backlog-staging.md}"
  fi
  exec "$BOARD_DIR/bin/add-backlog" ${args+"${args[@]}"}
}

# _run_adapter_verb <verb> [args...] -- when an adapter manifest declares <verb> (lib/adapters/*/adapter.tsv, a
# `verb` row), exec its script with the manifest args first, then the caller's args; return 1 on a miss, so the
# caller falls through. A core verb answers 1 at once, without a scan, so `board next` pays for one sourced file.
# KIT_LIB (the absolute lib/) is exported for out-of-tree scripts; in-tree scripts derive their own.
_run_adapter_verb() {
  case "${1:-}" in ''|-*) return 1 ;; esac
  . "$BOARD_DIR/../sync/adapters.sh"
  local verb_line verb_script
  local -a verb_args
  verb_line="$(adapters_verb "$1")" || return 1
  IFS=$'\t' read -r -a verb_args <<< "$verb_line"
  verb_script="${verb_args[0]}"
  unset 'verb_args[0]'
  shift
  export KIT_LIB
  case "$verb_script" in
    *.py) exec python3 "$verb_script" ${verb_args[@]+"${verb_args[@]}"} "$@" ;;
    *) exec bash "$verb_script" ${verb_args[@]+"${verb_args[@]}"} "$@" ;;
  esac
}

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
  local dir; dir="$(. "$BOARD_DIR/../sync/adapters.sh"; adapters_dir 2>/dev/null)" || dir=""
  [ -z "$dir" ] || printf '\nadapter directory: %s (KIT_ADAPTERS_DIR replaces it; the verbs a manifest declares run from there)\n' "$dir"
  return 0
}

main() {
  local first="${1:-}"
  case "$first" in
    all)    shift; cmd_all "$@" ;;
    queue)  shift; cmd_queue "$@" ;;
    sync) shift; cmd_sync "$@" ;;
    publish) shift; cmd_publish "$@" ;;
    sweep)
      shift
      if [ "${1:-}" = "verify" ]; then shift; exec bash "$BOARD_SWEEP_VERIFY_SH" "$@"; fi
      exec bash "$BOARD_SWEEP_SH" "$@" ;;
    state-check) shift; exec python3 "$BOARD_STATE_CHECK_PY" "$@" ;;
    health) shift; exec python3 "$BOARD_HEALTH_PY" "$@" ;;
    brief) shift; exec python3 "$BOARD_BRIEF_PY" "$@" ;;
    init) shift; cmd_init "$@" ;;
    capture) shift; cmd_capture "$@" ;;
    promote) shift; cmd_promote "$@" ;;
    normalize) shift; exec python3 "$BOARD_DIR/bin/board-normalize" "$@" ;;
    run) shift; exec "$BOARD_RUN_SH" "$@" ;;
    work) shift; exec bash "$BOARD_DIR/work.sh" "$@" ;;
    -h|--help|help) usage ;;
    *) _run_adapter_verb "$@" || true; cmd_board_single "$@" ;;
  esac
}

main "$@"

# provenance: SPEC-146, SPEC-147, SPEC-149, SPEC-002, ADR-0034
