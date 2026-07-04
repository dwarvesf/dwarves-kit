#!/usr/bin/env bash
# board.sh -- the kit's cockpit board command (SPEC-146, runner-fastpath sub-goal 04;
# `mirror`/`status` added by SPEC-147, sub-goal 07).
#
# The SOLE cockpit board command: it ABSORBS the render logic that used to live in ops-toolkit's
# `_meta/board` (the `priority` quadrant awk, single-repo) and `_meta/board-all` (the `boards.txt`
# registry walk + `priority matrix` cross-repo pivot), ADDS a `queue` subcommand that emits an
# allow-listed overnight-runner queue, and ADDS `mirror`/`status` (SPEC-147): a one-way git ->
# Hermes kanban bridge over opt-in repos + active mega-goals, native `hermes kanban` CLI only.
# Base kanban render (board/next/set/states) is UNCHANGED and still delegates to
# `lib/backlog.sh` -- this file never reimplements it. The substantial `mirror`/`status` logic
# (extract/diff/plan/apply) lives in `lib/board-mirror.sh`, the same delegation shape `queue`
# already has with `lib/parse-board.sh`.
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
#   board.sh mirror [--dry-run] [--repo-root <path>] [--registry <path>] [--snapshot <path>]
#                    [--mega-board <name>] [--board-prefix <prefix>]
#                    [--remote <user@host>] [--remote-kit-path <path>]
#                                                               project opt-in (`bridge=on`)
#                                                               cockpit boards + one card per
#                                                               ACTIVE mega-goal onto a Hermes
#                                                               kanban, idempotently. `--dry-run`
#                                                               prints the plan and applies
#                                                               nothing (no Hermes calls, no
#                                                               snapshot write). `--remote` ships
#                                                               the plan over ONE `ssh` call to a
#                                                               remote host's own board-mirror.sh
#                                                               apply-plan (argv vectors, never a
#                                                               templated shell string); default
#                                                               is local (`$HERMES_BIN`/`hermes`
#                                                               runs on this host). See
#                                                               `lib/board-mirror.sh` for the full
#                                                               ETL design + state-mapping table.
#   board.sh status [--repo-root <path>] [--registry <path>] [--snapshot <path>]
#                                                               mirror staleness: per opted-in
#                                                               repo, the snapshot's newest
#                                                               `seen_at` vs the BACKLOG.md's own
#                                                               last git-log touch time.
#
# Registry format (`boards.txt`): whitespace-delimited `<name> <path-to-BACKLOG.md> [bridge]`
# rows, `#` comments, `~` expands to $HOME. A THIRD field, `bridge`, opts a repo into `mirror`:
# exactly the literal token `on` opts in; absent, `off`, or any other value stays OUT (default
# OFF -- a repo must explicitly opt in; sensitive repos like `trading`/`family-office` must never
# be `on`). `board`/`next`/`priority`/`states`/`queue` never read this field (they only ever
# consumed the first two columns, per SPEC-146's own forward-compat design), so adding it is a
# zero-code-change, non-regressing registry format extension.
#
# --repo-root resolution precedence (cross-repo `all`/`queue`/`mirror`/`status` modes only): the
# `--repo-root` flag, else the `REPO_ROOT` env var, else `git rev-parse --show-toplevel` of the
# CURRENT cwd, else cwd itself. The single-repo subcommands never need --repo-root; the shim that
# calls them always passes an explicit --backlog-file instead.
#
# DWARVES_KIT overrides where lib/backlog.sh + lib/parse-board.sh + lib/board-mirror.sh are found
# relative to this file (they are always siblings in lib/, so this only matters if board.sh is
# copied standalone).

set -euo pipefail

BOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_SH="$BOARD_DIR/backlog.sh"
PARSE_BOARD_SH="$BOARD_DIR/parse-board.sh"
BOARD_MIRROR_SH="$BOARD_DIR/board-mirror.sh"

[ -f "$BACKLOG_SH" ]      || { echo "board: lib/backlog.sh not found at $BACKLOG_SH" >&2; exit 1; }
[ -f "$PARSE_BOARD_SH" ]  || { echo "board: lib/parse-board.sh not found at $PARSE_BOARD_SH" >&2; exit 1; }
[ -f "$BOARD_MIRROR_SH" ] || { echo "board: lib/board-mirror.sh not found at $BOARD_MIRROR_SH" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Flag parsing (shared): extracts --backlog-file / --repo-root / --registry / --dry-run plus the
# mirror-only flags (--snapshot / --mega-board / --board-prefix / --remote / --remote-kit-path)
# from anywhere in argv, leaving the rest in POSITIONAL in order. Re-callable per subcommand (each
# resets its own OPT_* vars first). The mirror-only flags are harmless no-ops for every OTHER
# subcommand (board/next/set/states/priority/all/queue never read them), so folding them into the
# one shared parser costs nothing and keeps a single flag-parsing surface (SPEC-146's own design).
# ---------------------------------------------------------------------------
OPT_BACKLOG_FILE=""; OPT_REPO_ROOT=""; OPT_REGISTRY=""; OPT_DRY_RUN=0
OPT_SNAPSHOT=""; OPT_MEGA_BOARD=""; OPT_BOARD_PREFIX=""; OPT_REMOTE=""; OPT_REMOTE_KIT_PATH=""
POSITIONAL=()
_parse_flags() {
  OPT_BACKLOG_FILE=""; OPT_REPO_ROOT=""; OPT_REGISTRY=""; OPT_DRY_RUN=0
  OPT_SNAPSHOT=""; OPT_MEGA_BOARD=""; OPT_BOARD_PREFIX=""; OPT_REMOTE=""; OPT_REMOTE_KIT_PATH=""
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

# ---------------------------------------------------------------------------
# mirror -- git<->Hermes kanban bridge, read-mirror leg (SPEC-147, runner-fastpath sub-goal 07).
# Delegates ALL substantial logic (extract/diff/plan/apply) to lib/board-mirror.sh, exactly the
# way `queue` above delegates parsing to lib/parse-board.sh; this function is the thin,
# human-facing wrapper: resolve config, get a plan, apply it (locally or over one `ssh` call),
# persist the snapshot incrementally as results stream back, print a summary. Never mutates any
# BACKLOG.md (mirror is one-way: git -> Hermes; SG-08 owns the reverse leg).
# ---------------------------------------------------------------------------
cmd_mirror() {
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-$repo_root/_meta/boards.txt}"
  local snapshot="${OPT_SNAPSHOT:-$repo_root/_meta/.board-mirror-snapshot.jsonl}"
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
    results="$(ssh "$OPT_REMOTE" "bash ${remote_kit}/lib/board-mirror.sh apply-plan" < "$plan")"
  else
    results="$(bash "$BOARD_MIRROR_SH" apply-plan < "$plan")"
  fi
  rm -f "$plan"

  local created=0 changed=0 completed=0 errors=0
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
      create)   created=$((created+1)) ;;
      change)   changed=$((changed+1)) ;;
      complete) completed=$((completed+1)) ;;
    esac
    hermes_id="$(printf '%s' "$rline" | jq -r '.hermes_id')"
    hermes_status="$(printf '%s' "$rline" | jq -r '.hermes_status')"
    echo "mirror: ${op} ${origin} -> ${hermes_id} (${hermes_status})" >&2
    # Persisted PER LINE, as results arrive (a mid-sync crash never loses a completed row).
    printf '%s' "$rline" | bash "$BOARD_MIRROR_SH" snapshot-upsert "$snapshot"
  done <<< "$results"

  echo "mirror: applied ${created} create, ${changed} change, ${completed} complete, ${errors} error(s)" >&2
  [ "$errors" -eq 0 ]
}

# ---------------------------------------------------------------------------
# status -- mirror staleness report (SPEC-147). Compares the snapshot's newest `seen_at` per
# opted-in repo against that repo's BACKLOG.md's own last git-log touch time; never touches
# Hermes or the snapshot file (read-only).
# ---------------------------------------------------------------------------
cmd_status() {
  _parse_flags "$@"
  local repo_root; repo_root="$(_resolve_repo_root)"
  local registry="${OPT_REGISTRY:-$repo_root/_meta/boards.txt}"
  local snapshot="${OPT_SNAPSHOT:-$repo_root/_meta/.board-mirror-snapshot.jsonl}"
  [ -f "$registry" ] || { echo "status: no registry at $registry" >&2; return 1; }

  local snap_tsv; snap_tsv="$(mktemp "${TMPDIR:-/tmp}/board-mirror-status.XXXXXX")"
  bash "$BOARD_MIRROR_SH" snapshot-read "$snapshot" > "$snap_tsv"

  local name path bridge rroot last_mirror last_touch changed=0 total_bridged=0 newest=""
  while read -r name path bridge; do
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
}

usage() { sed -n '2,78p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local first="${1:-}"
  case "$first" in
    all)    shift; cmd_all "$@" ;;
    queue)  shift; cmd_queue "$@" ;;
    mirror) shift; cmd_mirror "$@" ;;
    status) shift; cmd_status "$@" ;;
    -h|--help|help) usage ;;
    *) cmd_board_single "$@" ;;
  esac
}

main "$@"
