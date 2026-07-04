#!/usr/bin/env bash
# board.sh -- the kit's cockpit board command (SPEC-146, runner-fastpath sub-goal 04).
#
# The SOLE cockpit board command: it ABSORBS the render logic that used to live in ops-toolkit's
# `_meta/board` (the `priority` quadrant awk, single-repo) and `_meta/board-all` (the `boards.txt`
# registry walk + `priority matrix` cross-repo pivot), and ADDS a `queue` subcommand that emits an
# allow-listed overnight-runner queue. Base kanban render (board/next/set/states) is UNCHANGED and
# still delegates to `lib/backlog.sh` -- this file never reimplements it.
#
# The kit itself carries NO personal data: the consumer registry (`boards.txt`), the repo it
# describes, and any future bridge opt-ins are CONSUMER config this tool reads at runtime via
# `--repo-root <path>` / the `REPO_ROOT` env var (the kit's existing consumer pattern -- see
# lib/weekend-batch.sh's `_repo_root()` / `--repo-root`, lib/mega-merge.sh's env-override
# precedent). Never invents a `CONSUMER_ROOT` var.
#
# Usage:
#   board.sh board  [--backlog-file <path>]                    single-repo kanban render
#   board.sh next   [--backlog-file <path>]                    first queued ID
#   board.sh set <ID> <state> [note] [--backlog-file <path>]   flip a row's state
#   board.sh states [--backlog-file <path>]                    legal state names
#   board.sh priority [counts|brief|overview|full] [--backlog-file <path>]
#                                                               single-repo urgency x fit quadrant
#
#   board.sh all board|next|states [--repo-root <path>] [--registry <path>]
#                                                               cross-repo render, grouped by repo
#   board.sh all priority [counts|brief|overview|full] [--repo-root <path>] [--registry <path>]
#                                                               each repo's quadrant, grouped by repo
#   board.sh all priority matrix [--repo-root <path>] [--registry <path>]
#                                                               cross-repo urgency x repo pivot table
#
#   board.sh queue [--dry-run] [--repo-root <path>] [--registry <path>]
#                                                               walk the registry, parse every
#                                                               repo's BACKLOG.md via
#                                                               lib/parse-board.sh, emit
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
# Registry format (`boards.txt`): whitespace-delimited `<name> <path-to-BACKLOG.md> [...]` rows,
# `#` comments, `~` expands to $HOME. Trailing fields beyond the first two are read into a
# discarded remainder (`_rest`) today -- this is what makes the format tolerant of a future
# `bridge` column (SG-07) with zero code change here.
#
# --repo-root resolution precedence (cross-repo `all`/`queue` modes only): the `--repo-root` flag,
# else the `REPO_ROOT` env var, else `git rev-parse --show-toplevel` of the CURRENT cwd, else cwd
# itself. The single-repo subcommands never need --repo-root; the shim that calls them always
# passes an explicit --backlog-file instead.
#
# DWARVES_KIT overrides where lib/backlog.sh + lib/parse-board.sh are found relative to this file
# (they are always siblings in lib/, so this only matters if board.sh is copied standalone).

set -euo pipefail

BOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_SH="$BOARD_DIR/backlog.sh"
PARSE_BOARD_SH="$BOARD_DIR/parse-board.sh"

[ -f "$BACKLOG_SH" ]     || { echo "board: lib/backlog.sh not found at $BACKLOG_SH" >&2; exit 1; }
[ -f "$PARSE_BOARD_SH" ] || { echo "board: lib/parse-board.sh not found at $PARSE_BOARD_SH" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Flag parsing (shared): extracts --backlog-file / --repo-root / --registry / --dry-run from
# anywhere in argv, leaving the rest in POSITIONAL in order. Re-callable per subcommand (each
# resets its own OPT_* vars first).
# ---------------------------------------------------------------------------
OPT_BACKLOG_FILE=""; OPT_REPO_ROOT=""; OPT_REGISTRY=""; OPT_DRY_RUN=0
POSITIONAL=()
_parse_flags() {
  OPT_BACKLOG_FILE=""; OPT_REPO_ROOT=""; OPT_REGISTRY=""; OPT_DRY_RUN=0
  POSITIONAL=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --backlog-file) OPT_BACKLOG_FILE="${2:-}"; shift 2 ;;
      --repo-root)    OPT_REPO_ROOT="${2:-}"; shift 2 ;;
      --registry)     OPT_REGISTRY="${2:-}"; shift 2 ;;
      --dry-run)      OPT_DRY_RUN=1; shift ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
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

# ---------------------------------------------------------------------------
# Priority render (single repo) -- verbatim port of the awk program from ops-toolkit's
# `_meta/board` `priority` branch. Byte-identical output is the load-bearing non-regression
# contract (SPEC-146 proof-of-done); do not "clean up" this awk without re-running that proof.
# ---------------------------------------------------------------------------
_priority_render() {  # <backlog-file> <mode>
  local file="$1" mode="${2:-overview}"
  case "$mode" in counts|brief|overview|full) ;; *) mode="overview" ;; esac
  awk -F'|' -v mode="$mode" '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    function shorten(t){ if(length(t)>52) return substr(t,1,49)"..."; return t }
    $0 ~ /^\| *[A-Z]+-[0-9]+ *\|/ {
      id=trim($2); title=shorten(trim($3)); status=trim($(NF-1)); line=$0
      split(status,a,/[ \[(]/); lead=a[1]
      if (lead=="executing"||lead=="claimed"||lead=="speccing"||lead=="validated"){
        inflight[++nf]=sprintf("  %-8s %s  [%s]", id, title, lead); next }
      if (lead!="queued") next
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
    _priority_render "$OPT_BACKLOG_FILE" "${args[1]:-overview}"
    return 0
  fi
  BACKLOG_FILE="$OPT_BACKLOG_FILE" bash "$BACKLOG_SH" "${args[@]}"
}

# ---------------------------------------------------------------------------
# Cross-repo dispatch (mirrors ops-toolkit's old `_meta/board-all`).
# ---------------------------------------------------------------------------
cmd_all() {
  _parse_flags "$@"
  local args=("${POSITIONAL[@]}")
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-$repo_root/_meta/boards.txt}"
  [ -f "$registry" ] || { echo "board all: no registry at $registry" >&2; return 1; }

  local sub="${args[0]:-board}"
  local mode="${args[1]:-overview}"

  if [ "$sub" = "priority" ] && [ "$mode" = "matrix" ]; then
    _priority_matrix "$registry"
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
      local out; out="$(_priority_render "$path" "$mode" 2>&1 || true)"
      printf '\n=== %s ===\n%s\n' "$name" "$out"
    done < "$registry"
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
    local out; out="$(BACKLOG_FILE="$path" bash "$BACKLOG_SH" "$sub" 2>&1 || true)"
    if [ "$sub" = "next" ]; then
      printf '%-14s %s\n' "$name" "$out"
    else
      printf '\n=== %s ===\n%s\n' "$name" "$out"
    fi
  done < "$registry"
}

# ---------------------------------------------------------------------------
# queue -- the new overnight-runner feed (SPEC-146). Never mutates any BACKLOG.md.
# ---------------------------------------------------------------------------
cmd_queue() {
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-$repo_root/_meta/boards.txt}"
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

usage() { sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local first="${1:-}"
  case "$first" in
    all)   shift; cmd_all "$@" ;;
    queue) shift; cmd_queue "$@" ;;
    -h|--help|help) usage ;;
    *) cmd_board_single "$@" ;;
  esac
}

main "$@"
