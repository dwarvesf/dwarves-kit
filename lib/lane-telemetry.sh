#!/usr/bin/env bash
# lane-telemetry.sh -- the read side of lane effectiveness (SPEC-061).
#
# The kit records run facts in append-only ledgers (lib/gate-ledger.sh -> logs/runs/<rid>.log,
# lane downgrades -> logs/completeness.log) but until SPEC-061 nothing AGGREGATED them, so
# lane misfires died in chat instead of becoming classifier fixes + pins. This is the
# aggregator: pure bash/awk over the existing pipe-delimited logs, no new store, no daemon.
# Advisory: it reports, /kit:retro disposes (Detect, don't dictate).
#
# Usage:
#   lane-telemetry.sh report      -> per-lane + per-type aggregates over every run ledger
#   lane-telemetry.sh misfires    -> the runs where chosen lane != classified lane, plus
#                                    completeness.log LANE-CHECK lines: the feed for keyword fixes
#   lane-telemetry.sh trace <rid> -> one run's full story, formatted for review (SPEC-063)
#
# Line formats consumed (produced by gate-ledger.sh):
#   TS | START | lane=<chosen> classified=<suggested> type=<t> [ctype=<suggested-type>] repo=<r>
#   TS | ACTION | ... escaped-from=<spec-slug> ...   (SPEC-062: a bug run indicting a shipped spec)
#   TS | GATE | <phase> | ran|skipped|override | <reason>
# A run with no START line surfaces as lane "?" (an untracked run is itself a signal).
#
# DWARVES_KIT_LOG_DIR overrides the log root (tests point it at a fixture copy).
set -euo pipefail

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
RUNS_DIR="$LOG_DIR/runs"
COMPLETENESS="$LOG_DIR/completeness.log"
KIT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TTY-gated colors (SPEC-069): plain bytes whenever piped or NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[1;31m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_BOLD=""; C_OFF=""
fi

# Boardless runs (SPEC-069): a run ledger whose repo matches the cwd repo but whose rid
# the board never mentions. Detection only; the board file is the repo's own.
_boardless() {
  local root board myrepo f rid
  # worktree-safe (review A1): --git-common-dir resolves the MAIN checkout even from a
  # .claude/worktrees/<branch> session, where --show-toplevel's basename is the branch.
  local common; common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || return 0
  board="$root/_meta/BACKLOG.md"; [ -f "$board" ] || return 0
  myrepo="$(basename "$root")"
  for f in "$RUNS_DIR"/*.log; do
    [ -e "$f" ] || continue
    rid="$(basename "$f" .log)"
    grep -qF -- "repo=$myrepo" "$f" 2>/dev/null || continue
    grep -qF -- "$rid" "$board" 2>/dev/null || printf '%s\n' "$rid"
  done
}

# Shipped-incomplete (SPEC-069): a shipped run whose plan still has un-disposed phases
# (the spec-064 think class). Reads lane from the START line, asks gate-ledger progress.
# INTENTIONAL SEAM (review A4): this is lane-telemetry's ONE runtime call into
# gate-ledger, delegated to avoid duplicating the lane->phase map (WORKFLOW matrix
# parsing). The agreement is the literal word "complete" in progress's status line; a
# test pin asserts both sides carry it so a rename breaks the build, not the detector.
_shipped_incomplete() {
  local f rid lane
  for f in "$RUNS_DIR"/*.log; do
    [ -e "$f" ] || continue
    grep -q '| GATE | ship | ran' "$f" 2>/dev/null || continue
    rid="$(basename "$f" .log)"
    lane="$(grep -m1 '| START |' "$f" 2>/dev/null | grep -oE 'lane=[^ ]+' | head -1 | cut -d= -f2 || true)"
    [ -n "$lane" ] || continue
    bash "$KIT_LIB/gate-ledger.sh" progress "$rid" "$lane" 2>/dev/null | head -1 | grep -q 'complete' \
      || printf '%s (%s)\n' "$rid" "$lane"
  done
}

# one TSV row per run: rid repo lane classified type ctype ran skip ovr mis tmis ship review first last
_rows() {
  local f rid
  for f in "$RUNS_DIR"/*.log; do
    [ -e "$f" ] || continue
    rid="$(basename "$f" .log)"
    awk -v rid="$rid" '
      BEGIN { FS=" \\| " }
      NR==1 { first=$1 }
      { last=$1 }
      $2=="START" {
        n=split($3, kv, " ")
        for (i=1; i<=n; i++) { split(kv[i], p, "="); m[p[1]]=p[2] }
      }
      $2=="GATE" && $4=="ran"      { ran++ }
      $2=="GATE" && $4=="skipped"  { skip++ }
      $2=="GATE" && $4=="override" { ovr++ }
      $2=="GATE" && $3=="review" && $4=="ran" { review=$5; for (i=6; i<=NF; i++) review = review " | " $i }
      $2=="GATE" && $3=="ship"   && $4=="ran" { ship=1 }
      END {
        lane=(m["lane"]==""?"?":m["lane"]); cls=(m["classified"]==""?"?":m["classified"])
        type=(m["type"]==""?"?":m["type"]); repo=(m["repo"]==""?"?":m["repo"])
        ctype=(m["ctype"]==""?"?":m["ctype"])
        mis=(lane!="?" && cls!="?" && lane!=cls) ? 1 : 0
        tmis=(type!="?" && ctype!="?" && type!=ctype) ? 1 : 0
        if (review=="") review="-"
        gsub(/\t/, " ", review)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\n", \
          rid, repo, lane, cls, type, ctype, ran+0, skip+0, ovr+0, mis, tmis, ship+0, review, first, last
      }' "$f"
  done
}

# "<spec>\t<bug-rid>" per escaped-from ACTION marker (SPEC-062: test-design quality feed)
_escapes() {
  local f rid
  for f in "$RUNS_DIR"/*.log; do
    [ -e "$f" ] || continue
    rid="$(basename "$f" .log)"
    awk -v rid="$rid" 'BEGIN { FS=" \\| " }
      $2=="ACTION" && $3 ~ /escaped-from=/ {
        s=$3; sub(/.*escaped-from=/, "", s); sub(/[ ].*/, "", s)
        printf "%s\t%s\n", s, rid
      }' "$f"
  done
}

report() {
  [ -d "$RUNS_DIR" ] || { echo "(no runs dir at $RUNS_DIR)"; return 0; }
  local rows; rows="$(_rows)"
  [ -n "$rows" ] || { echo "(no run ledgers)"; return 0; }
  printf '%s\n' "$rows" | awk '
    BEGIN { FS="\t" }
    {
      runs[$3]++; types[$5]++; ran[$3]+=$7; skip[$3]+=$8; ovr[$3]+=$9
      mis[$3]+=$10; ships[$3]+=$12; total++; lmis+=$10; ttmis+=$11; tships+=$12
      if ($3=="?") untracked++
    }
    END {
      printf "runs: %d   lane-misrouted: %d   type-misrouted: %d   shipped: %d   untracked (no START): %d\n\n", \
        total, lmis, ttmis, tships, untracked+0
      printf "%-12s %5s %5s %6s %5s %5s %6s\n", "lane", "runs", "mis", "gates", "skip", "ovr", "ships"
      for (l in runs) printf "%-12s %5d %5d %6d %5d %5d %6d\n", l, runs[l], mis[l], ran[l], skip[l], ovr[l], ships[l]
      printf "\n%-14s %5s\n", "type", "runs"
      for (t in types) printf "%-14s %5d\n", t, types[t]
    }'
  local bl; bl="$(_boardless | grep -c . || true)"
  [ "${bl:-0}" -gt 0 ] && printf '%sboardless runs (ledgered but never on the board): %s%s\n' "$C_RED" "$bl" "$C_OFF"
  local esc; esc="$(_escapes)"
  if [ -n "$esc" ]; then
    echo ""
    echo "escaped defects (bug runs tracing to a shipped spec's test plan):"
    printf '%s\n' "$esc" | awk 'BEGIN{FS="\t"} { printf "  %s <- %s\n", $1, $2 }'
  fi
  echo ""
  echo "runs (rid  repo  lane<-classified  type<-ctype  review  first..last):"
  printf '%s\n' "$rows" | awk 'BEGIN{FS="\t"} { printf "  %-28s %-12s %s<-%s  %s<-%s  %-24s %s .. %s\n", $1, $2, $3, $4, $5, $6, $13, $14, $15 }'
}

misfires() {
  local any=0
  if [ -d "$RUNS_DIR" ]; then
    local lines
    lines="$(_rows | awk 'BEGIN{FS="\t"} $10==1 { printf "  %s: chosen=%s classified=%s (type=%s repo=%s)\n", $1, $3, $4, $5, $2 }')"
    if [ -n "$lines" ]; then
      echo "routing misfires (chosen lane != classified):"
      printf '%s\n' "$lines"; any=1
    fi
    lines="$(_rows | awk 'BEGIN{FS="\t"} $11==1 { printf "  %s: type=%s classified-type=%s (lane=%s repo=%s)\n", $1, $5, $6, $3, $2 }')"
    if [ -n "$lines" ]; then
      echo "type misfires (chosen type != classified):"
      printf '%s\n' "$lines"; any=1
    fi
  fi
  local bl_list; bl_list="$(_boardless)"
  if [ -n "$bl_list" ]; then
    echo "boardless runs (SPEC-069: work that never touched the board):"
    printf '%s\n' "$bl_list" | sed 's/^/  /'; any=1
  fi
  local si_list; si_list="$(_shipped_incomplete)"
  if [ -n "$si_list" ]; then
    echo "shipped-incomplete runs (a ship gate over un-disposed phases):"
    printf '%s\n' "$si_list" | sed 's/^/  /'; any=1
  fi
  if [ -f "$COMPLETENESS" ] && grep -q 'LANE-CHECK' "$COMPLETENESS" 2>/dev/null; then
    echo "floor-check downgrades (completeness.log):"
    grep 'LANE-CHECK' "$COMPLETENESS" | sed 's/^/  /'; any=1
  fi
  [ "$any" -eq 1 ] || echo "(no misfires recorded)"
  return 0
}

# trace: one run's ledger rendered as a reviewable story (SPEC-063): routing header with
# misfire flags, then the humanized timeline (gates with state + reason, actions, with
# escaped-from indictments called out).
trace() {
  local rid="${1:-}"; [ -n "$rid" ] || { echo "usage: trace <rid>" >&2; return 64; }
  local f="$RUNS_DIR/$rid.log"
  [ -f "$f" ] || { echo "(no ledger for '$rid' at $f)" >&2; return 1; }
  awk -v rid="$rid" -v red="$C_RED" -v off="$C_OFF" '
    BEGIN { FS=" \\| " }
    {
      ts=$1; sub(/T/, " ", ts); sub(/Z$/, "", ts)
      if (first=="") first=$1
      last=$1
    }
    $2=="START" {
      starts++
      if (m["lane"] != "") next   # first START wins; later ones noted in the header
      n=split($3, kv, " ")
      for (i=1; i<=n; i++) { split(kv[i], p, "="); m[p[1]]=p[2] }
      next
    }
    $2=="GATE" {
      reason=$5; for (i=6; i<=NF; i++) reason = reason " | " $i
      lines[++ln] = sprintf("  %s  %-10s %-9s %s", ts, $3, $4, reason)
      next
    }
    $2=="ACTION" {
      reason=$3; for (i=4; i<=NF; i++) reason = reason " | " $i
      flag=""
      if (reason ~ /escaped-from=/) flag="  << indicts a shipped spec test plan"
      lines[++ln] = sprintf("  %s  %-10s %-9s %s%s", ts, "action", "-", reason, flag)
      next
    }
    { lines[++ln] = sprintf("  %s  %s", ts, $0) }
    END {
      lane=(m["lane"]==""?"?":m["lane"]); cls=(m["classified"]==""?"?":m["classified"])
      type=(m["type"]==""?"?":m["type"]); ctype=(m["ctype"]==""?"?":m["ctype"])
      repo=(m["repo"]==""?"?":m["repo"])
      lflag=(lane!="?" && cls!="?" && lane!=cls) ? "  " red "<< LANE MISFIRE" off : ""
      tflag=(type!="?" && ctype!="?" && type!=ctype) ? "  " red "<< TYPE MISFIRE" off : ""
      printf "run: %s   repo: %s%s\n", rid, repo, (starts>1 ? sprintf("   << MULTI-START (n=%d; first wins)", starts) : "")
      printf "  lane: %s (classified: %s)%s\n", lane, cls, lflag
      printf "  type: %s (classified: %s)%s\n", type, ctype, tflag
      printf "  window: %s .. %s\n\n", first, last
      for (i=1; i<=ln; i++) print lines[i]
    }' "$f"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    report)   report ;;
    misfires) misfires ;;
    trace)    trace "$@" ;;
    *) echo "usage: lane-telemetry.sh {report|misfires|trace <rid>}" >&2; return 64 ;;
  esac
}

main "$@"
