#!/usr/bin/env bash
# mega-merge.sh -- ship-layer auto-merge ENFORCEMENT for the mega lane (ADR-0028 P2/P3,
# kit-hardening SG-08). Auto-merge RIDES ON the ship-gate; it never bypasses it.
#
# DECISION is separated from ACTION (two verbs) so the decision is testable without side
# effects, and the action is dry-run by default so a passing gate alone never touches `gh`:
#
#   gate  <rid> <lane>                     decision only, no side effects. Exit 0 iff
#                                           lib/gate-ledger.sh check <lane> <rid> passes
#                                           (every required measure-twice gate for <lane>
#                                           has a ran|override entry in <rid>'s ledger).
#                                           REUSES gate-ledger check verbatim -- never
#                                           re-implements or loosens the ship-gate's own
#                                           required-gate logic. Exit 1 + the gaps otherwise.
#
#   merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]
#                                           action. Runs `gate` FIRST; a failing or missing
#                                           gate REFUSES unconditionally (prints BLOCKED,
#                                           logs it, exits nonzero, never touches `gh`) --
#                                           a failing/missing gate can never auto-merge,
#                                           the exact mis-build ADR-0028 names as the risk.
#                                           A passing gate still only PRINTS the `gh pr
#                                           merge` it would run unless --execute is given.
#
# Per-run merge posture (mirrors the ops-toolkit plan-for-mega-goal skill's
# merge_autonomy knob; the ONE team-facing flag ADR-0028 calls out):
#   MEGA_MERGE_POSTURE=auto-to-final (default) | per-pr-review
#     auto-to-final  -- an `auto`-tagged sub-goal's PR merges once its gate passes
#                       (still requires --execute to actually call gh; see above).
#     per-pr-review  -- merge ALWAYS dry-runs, regardless of --execute or the gate
#                       result, so a team run keeps a human on every PR.
#   Resolution: --posture=<value> flag > MEGA_MERGE_POSTURE env > default auto-to-final.
#
# commands/mega.md routes a `gate`-tagged sub-goal or the held final PR away from `merge`
# at the PROMPT level (mirrors /kit:dispatch and the skill: a human always merges those).
# SPEC-100 (ID-083) adds a CODE-LEVEL backstop: `merge` itself calls `_merge_exclusion`,
# which reads the PR's GitHub STATE (draft / hold-label / bracketed title marker) and
# refuses , fail-closed on unreadable OR malformed state , so a prompt-rationalizing model
# cannot merge past the exclusion for a MARKED held PR even if the prompt-level rule is
# absent. It defends a MARKED PR; it does not synthesize a mark (an un-marked held PR must be
# opened draft/labelled at creation , enforcement tracked as ID-089). Defense-in-depth, not a
# replacement for the routing.
#
# Subcommands:
#   gate  <rid> <lane>
#   merge <pr> <rid> <lane> [--execute] [--posture=<val>]
set -uo pipefail

MM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_LEDGER="${MEGA_MERGE_GATE_LEDGER:-$MM_DIR/gate-ledger.sh}"
# Durable run-telemetry root (SPEC-097): resolve + one-time additive migration.
# shellcheck source=lib/kit-log-dir.sh
source "$MM_DIR/kit-log-dir.sh" || { echo "FATAL: lib/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

_log() {  # rid text
  # Collapse newlines in both fields before writing (mirrors gate-ledger's oneline; security
  # review defense-in-depth): today's rid sources (branch slug / gate-ledger rid) can't carry a
  # raw newline, but a future caller must not be able to forge a second log line.
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  local a b; a="$(printf '%s' "${1:-?}" | tr '\n\r' '  ')"; b="$(printf '%s' "${2:-}" | tr '\n\r' '  ')"
  printf '%s | %s | %s\n' "$(now)" "$a" "$b" >> "$LOG_DIR/mega-merge.log" 2>/dev/null || true
}

# gate <rid> <lane> -- DECISION ONLY. No file writes, no gh calls. Reuses
# gate-ledger.sh check() byte-for-byte (same lane x phase matrix hooks/ship-gate.sh
# enforces at push), so this can never drift looser than the ship-gate itself.
gate() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: gate <rid> <lane>" >&2; return 64; }
  [ -f "$GATE_LEDGER" ] || { echo "gate: gate-ledger.sh not found at $GATE_LEDGER" >&2; return 1; }
  bash "$GATE_LEDGER" check "$lane" "$rid"
}

_resolve_posture() {
  local flag="${1:-}"
  if [ -n "$flag" ]; then printf '%s\n' "$flag"; return; fi
  printf '%s\n' "${MEGA_MERGE_POSTURE:-auto-to-final}"
}

# _pr_info <pr> -- prints "<isDraft><US><comma-labels><US><title>" for the PR (US = the
# ASCII Unit Separator \037), reading GitHub STATE (never conversation intent). Overridable
# for tests via MEGA_MERGE_PR_INFO_CMD. The separator is a NON-whitespace control char so an
# empty labels field is preserved by `read` (a tab/space collapses empty fields, a \037 does
# not). Returns nonzero if the state cannot be read (gh error / offline) -> caller fails closed.
_pr_info() {
  if [ -n "${MEGA_MERGE_PR_INFO_CMD:-}" ]; then "$MEGA_MERGE_PR_INFO_CMD" "$1"; return; fi
  gh pr view "$1" --json isDraft,labels,title \
    --jq '[(.isDraft|tostring), ([.labels[].name]|join(",")), .title] | join("")' 2>/dev/null
}

# _merge_exclusion <pr> -- the CODE-LEVEL gate/held-final exclusion (SPEC-100, ID-083),
# defense-in-depth over commands/mega.md's prompt-only rule. Reads PR STATE:
#   return 0 + a reason  -> this PR must NOT auto-merge (draft / hold-label / title marker)
#   return 1             -> clear to auto-merge (normal `auto` sub-goal PR)
#   return 2             -> UNCLASSIFIABLE (state unreadable): caller fails closed, refuses.
# A prompt-rationalizing model cannot merge past this; it keys on state, not on being told.
_merge_exclusion() {
  local pr="$1" info draft labels title l
  info="$(_pr_info "$pr")" || return 2
  [ -n "$info" ] || return 2
  # Fail CLOSED on malformed-but-non-empty state (security review B2): a `gh` wrapper banner
  # or any output not of the exact 3-field <draft>US<labels>US<title> shape must NOT parse to
  # a garbage `draft` that then falls through to "clear". Require EXACTLY two \037 separators
  # and a boolean draft, else refuse as unclassifiable.
  local US=$'\037'
  [ "$(printf '%s' "$info" | tr -cd '\037' | wc -c | tr -d ' ')" = "2" ] || return 2
  # Split on the Unit Separator with pure PARAMETER EXPANSION, not `IFS= read` , the
  # empty-labels-middle-field case mis-parsed under the macos-latest CI bash (title landed in
  # labels), even though it parsed correctly under local bash 3.2/5.x. Parameter expansion is
  # deterministic for empty fields on every bash build.
  draft="${info%%"$US"*}"                      # up to the 1st US
  local rest="${info#*"$US"}"                   # after the 1st US
  labels="${rest%%"$US"*}"                     # up to the 2nd US
  title="${rest#*"$US"}"                        # after the 2nd US
  case "$draft" in true|false) ;; *) return 2 ;; esac
  [ "$draft" = "true" ] && { echo "PR #$pr is a draft"; return 0; }
  # hold labels: any of these (case-insensitive) block auto-merge. Split on comma with
  # `read -ra` (NOT an unquoted `for l in ${labels//,/ }`, which would word-split AND GLOB an
  # attacker-set label like `*`); the loop var is always quoted.
  local hold=" do-not-merge donotmerge gated-final hold blocked wip no-merge "
  local larr=() l ll
  # Guard the empty-labels case: `"${larr[@]}"` on an EMPTY array throws "unbound variable"
  # under `set -u` on bash 3.2 (the macos-latest CI runner). Only iterate when labels exist.
  if [ -n "$labels" ]; then
    IFS=',' read -ra larr <<< "$labels"
    for l in "${larr[@]}"; do
      ll="$(printf '%s' "$l" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
      [ -n "$ll" ] || continue
      case "$hold" in *" $ll "*)
        echo "PR #$pr carries the hold label '$l'"; return 0 ;; esac
    done
  fi
  # bracketed title markers, e.g. [HOLD] [gated-final] [do-not-merge] [WIP] [final]. Pure-bash
  # case-glob (not grep -E): identical across bash 3.2/5.x and every grep build (a BSD/CI grep
  # quirk on the -E pattern flaked this check on macos-latest; bash string matching is portable).
  local tl m; tl="$(printf '%s' "$title" | tr 'A-Z' 'a-z')"
  for m in '[hold]' '[gated-final]' '[do-not-merge]' '[wip]' '[final]' '[no-merge]'; do
    case "$tl" in *"$m"*) echo "PR #$pr title carries a hold marker"; return 0 ;; esac
  done
  return 1
}

# merge <pr> <rid> <lane> [--execute] [--posture=<val>] -- ACTION.
merge() {
  local pr="${1:-}" rid="${2:-}" lane="${3:-}"
  [ -n "$pr" ] && [ -n "$rid" ] && [ -n "$lane" ] || {
    echo "usage: merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]" >&2
    return 64
  }
  shift 3 2>/dev/null || true
  case "$pr" in
    ''|*[!0-9]*) echo "merge: <pr> must be a bare PR number (got '$pr')" >&2; return 64 ;;
  esac

  local execute=0 posture_flag="" arg
  for arg in "$@"; do
    case "$arg" in
      --execute) execute=1 ;;
      --posture=*) posture_flag="${arg#--posture=}" ;;
    esac
  done
  local posture; posture="$(_resolve_posture "$posture_flag")"

  # CODE-LEVEL gate/held-final exclusion (SPEC-100, ID-083), checked BEFORE the gate so a
  # held PR is refused even if its gates pass. Fail-closed: unreadable state is refused.
  local excl rc
  excl="$(_merge_exclusion "$pr")"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "BLOCKED: refusing to auto-merge PR #$pr -- $excl. Gated / held-final PRs are merged by a human, not the loop (mega-merge exclusion)." >&2
    _log "$rid" "BLOCKED merge pr=$pr (exclusion: $excl)"
    return 1
  elif [ "$rc" -eq 2 ]; then
    echo "BLOCKED: cannot read PR #$pr state (gh unavailable/offline); failing closed and refusing auto-merge. Verify + merge manually if intended." >&2
    _log "$rid" "BLOCKED merge pr=$pr (unclassifiable state, fail-closed)"
    return 1
  fi

  local gate_out
  if ! gate_out="$(gate "$rid" "$lane" 2>&1)"; then
    {
      echo "BLOCKED: ship-gate not satisfied, refusing auto-merge for PR #$pr (rid=$rid, lane=$lane)."
      printf '%s\n' "$gate_out" | sed 's/^/  /'
      echo "Run the missing gate(s), or record an explicit override (audited):"
      echo "  bash \"$GATE_LEDGER\" override $rid <phase> \"<reason>\""
    } >&2
    _log "$rid" "BLOCKED merge pr=$pr lane=$lane (gate failed)"
    return 1
  fi

  local cmd_str="gh pr merge $pr --squash --delete-branch"
  if [ "$posture" = "per-pr-review" ]; then
    echo "DRY-RUN (posture=per-pr-review, a human reviews every PR): $cmd_str"
    _log "$rid" "DRY-RUN merge pr=$pr lane=$lane posture=per-pr-review"
    return 0
  fi
  if [ "$execute" -ne 1 ]; then
    echo "DRY-RUN (gate passed; pass --execute to actually run this): $cmd_str"
    _log "$rid" "DRY-RUN merge pr=$pr lane=$lane posture=$posture"
    return 0
  fi

  echo "EXECUTING: $cmd_str"
  _log "$rid" "EXECUTE merge pr=$pr lane=$lane posture=$posture"
  gh pr merge "$pr" --squash --delete-branch
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  gate)  gate "$@" ;;
  merge) merge "$@" ;;
  *) echo "usage: mega-merge.sh {gate <rid> <lane>|merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]}" >&2; exit 64 ;;
esac
