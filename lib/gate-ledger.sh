#!/usr/bin/env bash
# gate-ledger.sh -- lane-aware gate ledger + action log + ship-completeness check.
#
# The single source for "which gates a lane requires" is the WORKFLOW.md lane×phase
# matrix; this parses it at runtime (no second copy), mirroring lib/dispatch-gate.sh's
# hands-off extraction. A matrix cell of `measure-twice` => the gate is REQUIRED for
# that lane. Records are append-only, operator-readable, and redacted (no command
# bodies). See docs/decisions/0024-gate-ledger-and-ship-enforcement.md.
#
# Subcommands:
#   required <lane>                     print the lane's required (measure-twice) gate keys
#   start    <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]   record routing facts (SPEC-061/062)
#   start --amend <same args>           sanctioned correction; readers take the last AMEND (SPEC-077)
#   record   <rid> <phase> <ran|skipped> [reason]   append a gate decision
#   action   <rid> <text>              append an action-log line
#   override <rid> <phase> <reason>    record a human override for a gate
#   check    <lane> <rid>              exit 0 if every required gate has a ran|override entry; else 1
#   show     <rid>                     print the run's ledger
#   plan     <lane>                    the lane's ordered phase checklist (SPEC-063)
#   progress <rid> <lane>              plan x ledger -> "step k/n" + checklist (SPEC-063)
#   rid                                the canonical run id for the cwd: branch slug (SPEC-070)
#   descent  <rid> <lane>              plan-order timeline check; violations detected, never blocked (SPEC-076)
set -euo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$GATE_DIR/.." && pwd)"
WORKFLOW="${GATE_LEDGER_WORKFLOW:-$KIT_ROOT/WORKFLOW.md}"
# Durable run-telemetry root (SPEC-097): resolve + one-time additive migration out of the
# ~/.claude/dwarves-kit reinstall blast zone. One resolver, no hard-coded default here.
# shellcheck source=lib/kit-log-dir.sh
source "$GATE_DIR/kit-log-dir.sh" || { echo "FATAL: lib/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)"
RUNS_DIR="$LOG_DIR/runs"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Collapse newlines/carriage-returns in operator/LLM-supplied free text to spaces before it
# is written to the append-only ledger (security review B1). Without this, a reason/action
# containing an embedded newline splits into extra pipe-delimited lines that readers
# (check/progress/descent + the SPEC-097 override guard) cannot distinguish from real GATE
# lines -- a prompt-injection -> ledger-forgery -> gate-bypass chain (a forged `| ran |`
# line makes check() believe a required gate ran). One ledger line per call, always.
oneline() { printf '%s' "${*:-}" | tr '\n\r' '  '; }

# TTY-gated colors (SPEC-069): escape codes emit ONLY on an interactive stdout with
# NO_COLOR unset, so every piped consumer (300+ test pins, scripts) sees plain bytes.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_DONE=$'\033[32m'; C_CUR=$'\033[1;33m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_DONE=""; C_CUR=""; C_DIM=""; C_BOLD=""; C_OFF=""
fi
runid() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }
ledger_file() {
  # Guard (SPEC-070 review S1): a slug of only special chars normalizes to "",
  # which would silently merge audit trails into a hidden RUNS_DIR/.log.
  local safe; safe="$(runid "$1")"
  [ -n "$safe" ] || { echo "ledger_file: rid '$1' normalizes to an empty filename" >&2; return 1; }
  printf '%s/%s.log' "$RUNS_DIR" "$safe"
}

# Stable key for a phase name: drop "(...)", lowercase, spaces -> dashes.
# "Design (opt-in)"->design, "Design critique (opt-in)"->design-critique,
# "Test plan (opt-in)"->test-plan, "Debug (off-cycle)"->debug, "UI design"->ui-design.
normalize_phase() {
  # collapse newlines first (security review, defense-in-depth): a phase arg with an embedded
  # newline would otherwise emit a second physical ledger line. Unreachable today (all callers
  # pass a hardcoded phase literal), but the guard is one tr and matches oneline()'s intent.
  printf '%s' "$1" | tr '\n\r' '  ' | sed -E 's/\([^)]*\)//g' | tr 'A-Z' 'a-z' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/-/g'
}

# print "<rawphase>\t<cell>" for each matrix row under the given lane column.
# Empty output => the lane column was not found (unknown lane).
matrix_for_lane() {
  awk -v lane="$1" '
    /^## Lane.*depth matrix/ {inmx=1; next}
    inmx && /^## / {exit}
    inmx && /^\| *Phase *\|/ {
      n=split($0, h, "|");
      for (i=1;i<=n;i++){gsub(/^ +| +$/,"",h[i]); if(h[i]==lane) col=i}
      next
    }
    inmx && col>0 && /^\|/ {
      if ($0 ~ /^\| *-+/) next;
      split($0, c, "|");
      ph=c[2]; gsub(/^ +| +$/,"",ph);
      cell=c[col]; gsub(/^ +| +$/,"",cell);
      if (ph!="" && ph!="Phase") print ph "\t" cell;
    }
  ' "$WORKFLOW"
}

required() {
  local lane="${1:-}"; [ -n "$lane" ] || { echo "usage: required <lane>" >&2; return 64; }
  local rows ph cell
  rows="$(matrix_for_lane "$lane")"
  [ -n "$rows" ] || { echo "unknown lane '$lane' (not a column in the WORKFLOW matrix)" >&2; return 1; }
  while IFS=$'\t' read -r ph cell; do
    [ "$cell" = "measure-twice" ] && printf '%s\n' "$(normalize_phase "$ph")"
  done <<< "$rows"
  return 0
}

# START records the run's routing facts for lane telemetry (SPEC-061): the lane the
# operator chose, the classifier's suggestion, the work type, and the repo. One line per
# run, written at assign/start time; lib/lane-telemetry.sh aggregates these read-side.
start() {
  # --amend (SPEC-077 / ID-072): a sanctioned correction. Writes START-AMEND; every
  # reader takes the LAST START-AMEND, else the FIRST plain START. Append-only stands.
  local marker=START uprefix=start
  if [ "${1:-}" = "--amend" ]; then marker=START-AMEND; uprefix="start --amend"; shift; fi
  local rid="${1:-}" lane="${2:-}" classified="${3:-}" type="${4:-}" ctype="${5:-}" repo="${6:-}"
  if [ -z "$rid" ] || [ -z "$lane" ] || [ -z "$classified" ] || [ -z "$type" ]; then
    echo "usage: $uprefix <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]" >&2; return 64
  fi
  [ -n "$repo" ] || repo="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  # the KV blob is space-split read-side; a space in any value corrupts the parse
  repo="$(printf '%s' "$repo" | tr ' ' '-')"
  type="$(printf '%s' "$type" | tr ' ' '-')"
  ctype="$(printf '%s' "$ctype" | tr ' ' '-')"
  lane="$(printf '%s' "$lane" | tr ' ' '-')"
  classified="$(printf '%s' "$classified" | tr ' ' '-')"
  mkdir -p "$RUNS_DIR"
  local line
  line="$(printf '%s | %s | lane=%s classified=%s type=%s' "$(now)" "$marker" "$lane" "$classified" "$type")"
  [ -n "$ctype" ] && line="$line ctype=$ctype"
  printf '%s repo=%s\n' "$line" "$repo" >> "$(ledger_file "$rid")"
}

record() {
  local rid="${1:-}" raw="${2:-}" state="${3:-}"; shift 3 2>/dev/null || { echo "usage: record <rid> <phase> <ran|skipped> [reason]" >&2; return 64; }
  case "$state" in ran|skipped) ;; *) echo "state must be ran|skipped" >&2; return 64;; esac
  mkdir -p "$RUNS_DIR"
  printf '%s | GATE | %s | %s | %s\n' "$(now)" "$(normalize_phase "$raw")" "$state" "$(oneline "$@")" >> "$(ledger_file "$rid")"
}

action() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: action <rid> <text>" >&2; return 64; }
  mkdir -p "$RUNS_DIR"
  printf '%s | ACTION | %s\n' "$(now)" "$(oneline "$@")" >> "$(ledger_file "$rid")"
}

# tokens: record a run's token usage as an ADDITIVE marker (SPEC-110). Emits a `| TOKENS |` line
# that check()/override()/descent()/_rows() all ignore (they key on $2=="GATE"|START|ACTION), so a
# token line can never fake a gate. Values are sanitized to non-negative integers.
# Usage: tokens <rid> in=N out=N cache_read=N cache_create=N [cost=N]
tokens() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: tokens <rid> in=N out=N cache_read=N cache_create=N [cost=N]" >&2; return 64; }
  [ -n "$rid" ] || { echo "tokens requires a rid" >&2; return 64; }
  local intok=0 outtok=0 cread=0 ccreate=0 cost="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      in)           intok="$(printf '%s' "$v" | tr -cd '0-9')"; intok="${intok:-0}" ;;
      out)          outtok="$(printf '%s' "$v" | tr -cd '0-9')"; outtok="${outtok:-0}" ;;
      cache_read)   cread="$(printf '%s' "$v" | tr -cd '0-9')"; cread="${cread:-0}" ;;
      cache_create) ccreate="$(printf '%s' "$v" | tr -cd '0-9')"; ccreate="${ccreate:-0}" ;;
      cost)         cost="$(printf '%s' "$v" | tr -cd '0-9.')" ;;   # decimal dollars: digits + dot(s); display-only, never summed
    esac
  done
  mkdir -p "$RUNS_DIR"
  local line; line="$(printf 'in=%s out=%s cache_read=%s cache_create=%s' "$intok" "$outtok" "$cread" "$ccreate")"
  [ -n "$cost" ] && line="$line cost=$cost"
  printf '%s | TOKENS | %s\n' "$(now)" "$line" >> "$(ledger_file "$rid")"
}

override() {
  local rid="${1:-}" raw="${2:-}"; shift 2 2>/dev/null || { echo "usage: override <rid> <phase> <reason>" >&2; return 64; }
  local reason; reason="$(oneline "$@")"; [ -n "$reason" ] || { echo "override requires a reason" >&2; return 64; }
  local phase; phase="$(normalize_phase "$raw")"
  local f; f="$(ledger_file "$rid")"
  # Blanket-override guard (SPEC-097): a reason already used to override a DIFFERENT phase
  # in this run is one pasted across all gates, which defeats the per-gate audit trail --
  # reject it (exit 65). Re-applying the same reason to the SAME phase (idempotent re-run)
  # is fine. Split on ' | ' so fields line up with the write format below.
  if [ -f "$f" ] && awk -F' [|] ' -v p="$phase" -v r="$reason" '
        $2=="GATE" && $4=="override" && $3!=p {
          rr=$5; for (i=6; i<=NF; i++) rr=rr " | " $i   # reason may contain " | "
          if (rr==r) found=1
        }
        END { exit !found }' "$f"; then
    echo "override rejected: reason already used for another gate in run '$rid' -- each gate override needs its own reason (SPEC-097)" >&2
    return 65
  fi
  mkdir -p "$RUNS_DIR"
  printf '%s | GATE | %s | override | %s\n' "$(now)" "$phase" "$reason" >> "$f"
}

show() { local f; f="$(ledger_file "${1:-}")"; if [ -f "$f" ]; then cat "$f"; else echo "(no ledger for '${1:-}')" >&2; return 1; fi; }

# exit 0 if every required (measure-twice) gate has a ran|override entry; else 1 + list gaps.
check() {
  local lane="${1:-}" rid="${2:-}"; [ -n "$lane" ] && [ -n "$rid" ] || { echo "usage: check <lane> <rid>" >&2; return 64; }
  # FAIL CLOSED on an unknown lane (security review, TIER-4): `required` returns nonzero for a
  # lane that is not a WORKFLOW matrix column (a typo, or "mega"). Reading its EMPTY stream in
  # the loop below would leave missing=0 and vacuously PASS -- so an unknown lane would let
  # mega-merge auto-merge (and ship-gate pass) with zero gates enforced. Distinguish it from a
  # VALID lane that legitimately has zero measure-twice gates (e.g. `tiny`): `required` exits 0
  # there with empty output, which correctly passes.
  local req
  if ! req="$(required "$lane" 2>/dev/null)"; then
    echo "check: unknown lane '$lane' (not a WORKFLOW matrix column: tiny|normal|full|bug|backfill); refusing, fail-closed" >&2
    return 1
  fi
  local f; f="$(ledger_file "$rid")"
  local missing=0 phase
  while IFS= read -r phase; do
    [ -n "$phase" ] || continue
    if [ ! -f "$f" ] || ! awk -F' [|] ' -v p="$phase" '$2=="GATE" && $3==p && ($4=="ran"||$4=="override"){f=1} END{exit !f}' "$f"; then
      echo "MISSING-GATE: $phase (required for lane '$lane'; no ran/override entry in the ledger)" >&2
      missing=1
    fi
  done <<< "$req"
  return "$missing"
}

# plan: the lane's ordered phase checklist, derived from the WORKFLOW matrix (skip cells
# omitted; measure-twice = required, run-lite = lite). grill is prepended as the universal
# intake phase (SPEC-058; tiny lane exempt). This is what /kit:assign prints right after a
# lane is committed, so the operator sees the road before the run starts (SPEC-063).
plan() {
  local lane="${1:-}"; [ -n "$lane" ] || { echo "usage: plan <lane>" >&2; return 64; }
  local rows; rows="$(matrix_for_lane "$lane")"
  [ -n "$rows" ] || { echo "unknown lane '$lane' (not a column in the WORKFLOW matrix)" >&2; return 1; }
  local i=0 ph cell mark
  if [ "$lane" != "tiny" ]; then
    i=1; printf '%2d. %-18s %s\n' 1 "grill" "intake (universal, SPEC-058)"
  fi
  while IFS=$'\t' read -r ph cell; do
    case "$cell" in
      measure-twice) mark="required" ;;
      run-lite)      mark="lite" ;;
      *) continue ;;
    esac
    i=$((i+1))
    printf '%2d. %-18s %s\n' "$i" "$(normalize_phase "$ph")" "$mark"
  done <<< "$rows"
}

# progress: plan x ledger -> one status line + checklist. A phase counts done when the
# ledger carries ANY entry for it (ran, skipped-with-reason, override); the current step
# is the first phase without one. Commands print this at phase entry (SPEC-063).
progress() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: progress <rid> <lane>" >&2; return 64; }
  local f; f="$(ledger_file "$rid")"
  local total=0 done_n=0 cur="" cur_idx=0 list="" ooo=0
  local idx ph rest
  while IFS= read -r pline; do
    idx="${pline%%.*}"; idx="$(printf '%s' "$idx" | tr -d ' ')"
    ph="$(printf '%s' "$pline" | awk '{print $2}')"
    total=$((total+1))
    # disposed = ran / override / skipped WITH a reason; a bare skip stays visible as a gap
    if [ -f "$f" ] && awk -F' [|] ' -v p="$ph" '$2=="GATE" && $3==p && ($4!="skipped" || (NF>=5 && $5!="")) {found=1} END{exit !found}' "$f"; then
      # SPEC-071 / ID-050: a phase disposed AFTER the current pointer gets its own
      # marker (*), so an out-of-order ✓ can't mislead the at-a-glance read.
      if [ -n "$cur" ]; then
        done_n=$((done_n+1)); ooo=1; list="$list ${C_DONE}*$ph${C_OFF}"
      else
        done_n=$((done_n+1)); list="$list ${C_DONE}✓$ph${C_OFF}"
      fi
    elif [ -z "$cur" ]; then
      cur="$ph"; cur_idx="$idx"; list="$list ${C_CUR}▶$ph${C_OFF}"
    else
      list="$list ${C_DIM}·$ph${C_OFF}"
    fi
  done < <(plan "$lane")
  [ "$total" -gt 0 ] || return 1
  if [ -z "$cur" ]; then
    printf '%s%s · %s · complete (%d/%d)%s\n' "$C_DONE" "$rid" "$lane" "$done_n" "$total" "$C_OFF"
  else
    printf '%s%s · %s · step %s/%d (%s)%s\n' "$C_BOLD" "$rid" "$lane" "$cur_idx" "$total" "$cur" "$C_OFF"
  fi
  printf ' %s\n' "$list"
  [ "$ooo" -eq 1 ] && printf '%s  (* = disposed out of order)%s\n' "$C_DIM" "$C_OFF"
  return 0
}

# Descent check (SPEC-076 / ID-068): the lane's plan order IS the V-model descent
# order. Replay the ledger timeline; a phase recorded while an EARLIER plan phase is
# still undisposed at that moment is a descent violation. Detection only: exit 0
# always (ADR-0024, mid-flight never blocks); ship-gate surfaces the count as an
# advisory. Disposal semantics agree with progress(): ran / override / skipped WITH
# a non-empty reason dispose; a bare skip does not.
descent() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: descent <rid> <lane>" >&2; return 64; }
  local f; f="$(ledger_file "$rid")" || return 0
  [ -f "$f" ] || { echo "descent clean (no ledger)"; return 0; }
  # phase + depth pairs: run-lite/intake phases are implicit checkpoints (review
  # HIGH: an unrecorded run-lite phase must not produce false violations); only
  # measure-twice (printed as "required") phases gate the descent when unrecorded.
  local plan_list; plan_list="$(plan "$lane" | awk '{print $2"="$3}' | tr '\n' ' ')" || return 0
  [ -n "$plan_list" ] || { echo "descent clean (no plan)"; return 0; }
  local out
  out="$(awk -F' [|] ' -v plan="$plan_list" '
    BEGIN {
      n=split(plan, R, " ")
      for (i=1;i<=n;i++) if (R[i]!="") {
        split(R[i], kv, "="); P[i]=kv[1]; order[kv[1]]=i
        if (kv[2]=="lite") disposed[kv[1]]=1   # run-lite only; grill (intake) + required phases stay real checkpoints
      }
    }
    $2=="GATE" {
      p=$3; if (!(p in order)) next
      for (j=1; j<order[p]; j++) if (P[j]!="" && !(P[j] in disposed) && !((p SUBSEP P[j]) in seen)) {
        printf "DESCENT: %s recorded before %s disposed\n", p, P[j]
        seen[p SUBSEP P[j]]=1   # dedup: one line per (phase, gap) pair
      }
      if ($4!="skipped" || (NF>=5 && $5!="")) disposed[p]=1
    }' "$f")"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "descent clean"; fi
  return 0
}

# The canonical run id (SPEC-070 / ID-059): the current branch with its leading
# `type/` segment stripped, the EXACT transform ship-gate keys its ledger check by
# (`${branch#*/}` here == `${BRANCH#*/}` in hooks/ship-gate.sh; agreement-pinned in tests/test-meta.sh).
# One rid from assign to ship means no mirror records. Fails loudly off a work
# branch: a wrong rid recorded silently is worse than no rid.
rid() {
  local branch slug
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$branch" in
    ""|HEAD|master|main)
      echo "rid: not on a work branch (got '${branch:-none}'); create the branch first, then derive the rid" >&2
      return 1 ;;
  esac
  slug="${branch#*/}"
  if [ -z "$slug" ] || [ -z "$(runid "$slug")" ]; then
    echo "rid: branch '$branch' strips to an empty slug" >&2
    return 1
  fi
  # Emit the runid-normalized form (review S2): the visible key equals the
  # ledger filename stem, so forensic review never chases two spellings.
  printf '%s\n' "$(runid "$slug")"
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  required) required "$@" ;;
  start)    start "$@" ;;
  record)   record "$@" ;;
  action)   action "$@" ;;
  tokens)   tokens "$@" ;;
  override) override "$@" ;;
  check)    check "$@" ;;
  show)     show "$@" ;;
  plan)     plan "$@" ;;
  progress) progress "$@" ;;
  rid)      rid "$@" ;;
  descent)  descent "$@" ;;
  *) echo "usage: gate-ledger.sh {required|start|record|action|tokens|override|check|show|plan|progress|rid|descent} ..." >&2; exit 64 ;;
esac
