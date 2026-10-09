#!/usr/bin/env bash
# mega-merge.sh -- ship-layer auto-merge ENFORCEMENT for the mega lane (P2/P3,
# kit-hardening). Auto-merge RIDES ON the ship-gate; it never bypasses it.
#
# DECISION is separated from ACTION (two verbs) so the decision is testable without side
# effects, and the action is dry-run by default so a passing gate alone never touches `gh`:
#
#   gate  <rid> <lane>                     decision only, no side effects. Exit 0 iff
#                                           lib/gate/gate-ledger.sh check <lane> <rid> passes
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
#                                           the exact mis-build this design names as the risk.
#                                           A passing gate still only PRINTS the `gh pr
#                                           merge` it would run unless --execute is given.
#
# Per-run merge posture (mirrors the ops-toolkit plan-for-mega-goal skill's
# merge_autonomy knob; the ONE team-facing flag this design calls out):
#   MEGA_MERGE_POSTURE=auto-to-final (default) | per-pr-review
#     auto-to-final  -- an `auto`-tagged sub-goal's PR merges once its gate passes
#                       (still requires --execute to actually call gh; see above).
#     per-pr-review  -- merge ALWAYS dry-runs, regardless of --execute or the gate
#                       result, so a team run keeps a human on every PR.
#   Resolution: --posture=<value> flag > MEGA_MERGE_POSTURE env >
#   the config layer's [mega].mega_merge_posture (project .kit.toml > kit-root kit.toml) >
#   default auto-to-final. The env var still wins over config outright, same as every other
#   `[mega]` knob orchestrate.sh resolves.
#
# commands/mega.md routes a `gate`-tagged sub-goal or the held final PR away from `merge`
# at the PROMPT level (mirrors /kit:dispatch and the skill: a human always merges those).
# A CODE-LEVEL backstop: `merge` itself calls `_merge_exclusion`,
# which reads the PR's GitHub STATE (draft / hold-label / bracketed title marker) and
# refuses , fail-closed on unreadable OR malformed state , so a prompt-rationalizing model
# cannot merge past the exclusion for a MARKED held PR even if the prompt-level rule is
# absent. It defends a MARKED PR; it does not synthesize a mark (an un-marked held PR must be
# opened draft/labelled at creation). Defense-in-depth, not a
# replacement for the routing.
#
# Subcommands:
#   gate  <rid> <lane>
#   merge <pr> <rid> <lane> [--execute] [--posture=<val>]
set -uo pipefail

MM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$MM_DIR/.." && pwd)"  # the lib/ dir; cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
GATE_LEDGER="${MEGA_MERGE_GATE_LEDGER:-$LIB_ROOT/gate/gate-ledger.sh}"
SHIP_RULES="$LIB_ROOT/gate/ship-rules.sh"
SPEC_FIND="$LIB_ROOT/spec/spec-find.sh"
# Config layer: see kit-config.sh header. Sourced once; idempotent if a
# caller already sourced it.
CONFIG_LIB="${CONFIG_LIB:-$LIB_ROOT/config/kit-config.sh}"
# shellcheck source=lib/config/kit-config.sh
[ -f "$CONFIG_LIB" ] && . "$CONFIG_LIB"
# Durable run-telemetry root: resolve + one-time additive migration.
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
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

# gate <rid> <lane> [--head <sha> [--base-tip <sha>]] -- DECISION ONLY. No gh calls, no writes
# beyond a scratch spec file that is removed before return. Reuses
# gate-ledger.sh check() byte-for-byte (same lane x phase matrix hooks/ship-gate.sh
# enforces at push), so its ledger arm never drifts looser than the ship-gate's. The
# ship-gate's full-lane implementation-notes check reads repo files and is NOT mirrored
# here: a PR reaching this merge was already pushed through that hook.
#
# The two ship-gate rules that read the diff and the spec run from the SAME helper the hook
# sources (lib/gate/ship-rules.sh), so a green gate means the push passes them too:
#   - a large normal-lane spec needs a validate ran/override record (spec found by spec_for_slug);
#   - a diff touching a hard path owes the full lane's gates whatever <lane> says.
# They read the repo at $MEGA_MERGE_ROOT (default: the cwd's repo). With no --head they read its
# local HEAD against the merge base with the remote default branch; no repo, no base, or no helper
# means the rules are skipped, the same fail-open the hook has (the hook-parity path). The hook's
# lane is the ledger START-AMEND over the spec header; here the caller's <lane> argument is that lane.
#
# With --head <sha> (what `merge` passes) the rules read <sha>, the PR head GitHub merges, from the
# object store, never the working tree or the local HEAD, with ONE exception: [lanes] extra_hard_paths is a
# union, so the $MEGA_MERGE_ROOT working tree and HEAD copies still count (they can only add entries) beside
# the copy committed at the base-branch tip. <sha> and --base-tip must be 40
# lowercase hex commits in the repo. The base is merge-base(<sha>, --base-tip), else the merge base
# with the remote default branch. Head mode never skips the rules: no repo, a bad SHA or no merge
# base (a shallow clone has none) is BLOCKED, exit 1. The spec comes from <sha>'s tree. The merge base
# only scopes the diff: every config read ([gate] lane_gates, the project lane override, the hard-path
# exemptions) is at the base-branch tip, since the PR author picks the merge base by where the branch is
# cut. Three silent passes remain, for hook parity: no ledger file, [gate] lane_gates off at the tip, and
# a classifier that is missing or errors (SECURITY.md).
gate() {
  local rid="${1:-}" lane="${2:-}" rc=0 root="" head="" base="" head_mode=0 tip="" a cfg=""
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: gate <rid> <lane> [--head <sha> [--base-tip <sha>]]" >&2; return 64; }
  shift 2
  while [ "$#" -gt 0 ]; do
    a="$1"
    case "$a" in
      --head|--base-tip)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "gate: $a needs a value" >&2; return 64; }
        if [ "$a" = --head ]; then head_mode=1; head="$2"; else tip="$2"; fi
        shift 2 ;;
      *) echo "gate: unknown argument '$a'" >&2; return 64 ;;
    esac
  done
  [ -z "$tip" ] || [ "$head_mode" -eq 1 ] || { echo "gate: --base-tip needs --head" >&2; return 64; }
  [ -f "$GATE_LEDGER" ] || { echo "gate: gate-ledger.sh not found at $GATE_LEDGER" >&2; return 1; }
  root="${MEGA_MERGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  if [ -z "$root" ]; then
    [ "$head_mode" -eq 0 ] || { echo "BLOCKED: mega gate: --head needs a repo" >&2; return 1; }
    # No repo: the ledger check runs bare and the diff rules are skipped, the same fail-open the hook has.
    bash "$GATE_LEDGER" check "$lane" "$rid"; return
  fi
  # A helper that fails to load fails the gate (the hook blocks too), never a silent bare check.
  # shellcheck source=lib/gate/ship-rules.sh
  if ! { [ -f "$SHIP_RULES" ] && source "$SHIP_RULES" 2>/dev/null; }; then
    echo "$(now) | FAIL-OPEN | ship-rules unavailable | $SHIP_RULES" >&2
    echo "BLOCKED: ship-gate. lib/gate/ship-rules.sh failed to load; reinstall or fix the kit" >&2
    return 1
  fi
  if [ "$head_mode" -eq 1 ]; then
    _gate_sha_ok "$root" "$head" || { echo "BLOCKED: mega gate: head $head is not a commit in $root" >&2; return 1; }
    if [ -n "$tip" ]; then
      _gate_sha_ok "$root" "$tip" || { echo "BLOCKED: mega gate: base tip $tip is not a commit in $root" >&2; return 1; }
      base="$(git -C "$root" merge-base "$head" "$tip" 2>/dev/null || true)"
    else
      base="$(ship_rules_merge_base "$root" "$head")"
    fi
    [ -n "$base" ] || { echo "BLOCKED: mega gate: no merge base for $head (shallow clone, or no shared history with the base branch?)" >&2; return 1; }
    # base == head means an empty diff and a vacuous floor. A forged tip (a fetch override printing the head or
    # one of its descendants) makes exactly that, so refuse it. The cost: a PR already inside its base branch
    # is refused too; it has nothing to merge.
    [ "$base" != "$head" ] || { echo "BLOCKED: mega gate: merge base equals head ($head has no changes against its base tip)" >&2; return 1; }
    # Config is read at the fresh base-branch tip (else the resolved default branch), never at the merge
    # base: a PR cut from an old commit picks its own base, and could carry a looser config.
    cfg="$tip"
    [ -n "$cfg" ] || cfg="$(git -C "$root" rev-parse --verify -q "$(ship_rules_resolve_base "$root")^{commit}" 2>/dev/null || true)"
    [ -n "$cfg" ] || cfg="$base"
  else
    head="$(git -C "$root" rev-parse HEAD 2>/dev/null || true)"
    [ -z "$head" ] || base="$(ship_rules_merge_base "$root" "$head")"
  fi
  # Same call as the hook: the project .kit.toml lanes come from the merge base, so a project lane
  # override reads the same in both gates and a change under review cannot rewrite its own lanes.
  ship_rules_ledger_check "$root" "$lane" "$rid" "$GATE_LEDGER" "${cfg:-$base}" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  if [ "$head_mode" -eq 1 ]; then _ship_rules_gate_head "$rid" "$lane" "$root" "$head" "$base" "$cfg"
  else _ship_rules_gate "$rid" "$lane" "$root" "$head" "$base"; fi
}

# _gate_sha_ok <root> <sha> -- 0 iff <sha> is 40 lowercase hex and a commit in <root>.
_gate_sha_ok() {
  [ "${#2}" -eq 40 ] || return 1
  case "$2" in *[!0123456789abcdef]*) return 1 ;; esac
  git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null
}

_ship_rules_gate() {
  local rid="$1" lane="$2" root="$3" head="$4" base="$5" spec=""
  [ -n "$head" ] || return 0
  # shellcheck source=lib/spec/spec-find.sh
  if [ -r "$SPEC_FIND" ] && source "$SPEC_FIND" 2>/dev/null; then spec="$(spec_for_slug "$root" "$rid")"; fi
  # The hook runs the large-spec rule only with a spec and only while [gate] lane_gates is on at the merge base.
  if [ -n "$spec" ] && ship_rules_switch_on lane_gates "$root" "$base"; then
    ship_rule_large_spec "$spec" "$rid" "$lane" "$GATE_LEDGER" || return 1
  fi
  ship_rule_floor "$root" "$base" "$head" "$rid" "$spec" "$GATE_LEDGER" || return 1
  return 0
}

# _ship_rules_gate_head -- the same two rules on a commit: the spec is read from <head>'s tree into a
# scratch file (removed before every return), and messages name the in-tree path.
_ship_rules_gate_head() {
  local rid="$1" lane="$2" root="$3" head="$4" base="$5" cfg="$6" spec="" tmp="" rc=0
  spec="$(_spec_in_tree "$root" "$head" "$rid")"
  if [ -n "$spec" ] && ship_rules_switch_on lane_gates "$root" "$cfg"; then
    tmp="$(mktemp 2>/dev/null)" || tmp=""
    if [ -n "$tmp" ] && git -C "$root" cat-file blob "$head:$spec" > "$tmp" 2>/dev/null; then
      ship_rule_large_spec "$tmp" "$rid" "$lane" "$GATE_LEDGER" "$spec" || rc=1
    fi
    [ -z "$tmp" ] || rm -f "$tmp"
    [ "$rc" -eq 0 ] || return 1
  fi
  ship_rule_floor "$root" "$base" "$head" "$rid" "$spec" "$GATE_LEDGER" "$cfg" || return 1
  return 0
}

# _spec_in_tree <root> <sha> <rid> -- prints the in-tree path of the spec <rid> picks in <sha>'s tree:
# a root docs/specs/ match first, else the shallowest co-located match (LC_ALL=C order), the pick
# order of spec_for_slug. Prints nothing when there is none.
_spec_in_tree() {
  local root="$1" sha="$2" rid="$3" p rootpick="" colo="" n
  [ -r "$SPEC_FIND" ] && source "$SPEC_FIND" 2>/dev/null || return 0
  while IFS= read -r -d '' p; do
    case "$p" in *$'\n'*) continue ;; esac
    spec_path_matches "$p" "$rid" || continue
    if [ "${p#docs/specs/}" != "$p" ] && [ "${p#docs/specs/*/}" = "$p" ]; then
      rootpick="$p"; break
    fi
    n="$(printf '%s' "$p" | tr -cd '/' | wc -c | tr -d ' ')"
    colo="${colo:+$colo$'\n'}$n$(printf '\t')$p"
  done < <(git -C "$root" ls-tree -r -z --name-only "$sha" 2>/dev/null)
  if [ -n "$rootpick" ]; then printf '%s\n' "$rootpick"; return 0; fi
  [ -z "$colo" ] || printf '%s\n' "$colo" | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2 | head -1 | cut -f2-
  return 0
}

_resolve_posture() {
  local flag="${1:-}" cfg
  if [ -n "$flag" ]; then printf '%s\n' "$flag"; return; fi
  if [ -n "${MEGA_MERGE_POSTURE:-}" ]; then printf '%s\n' "$MEGA_MERGE_POSTURE"; return; fi
  cfg="$(kit_config_get mega.mega_merge_posture)"
  printf '%s\n' "${cfg:-auto-to-final}"
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

# _pr_head <pr> -- prints the PR head commit SHA (exactly 40 lowercase hex characters), the pin
# `merge` hands to `gh pr merge --match-head-commit`. Overridable for tests via
# MEGA_MERGE_PR_HEAD_CMD (test-only; never set in an unattended run). Prints nothing and returns
# nonzero when the read fails or the value is not a bare SHA (a multi-line or CR-tailed value fails
# the length check) -> caller fails closed.
_pr_head() {
  local out
  if [ -n "${MEGA_MERGE_PR_HEAD_CMD:-}" ]; then out="$("$MEGA_MERGE_PR_HEAD_CMD" "$1")" || return 1
  else out="$(gh pr view "$1" --json headRefOid --jq .headRefOid 2>/dev/null)" || return 1
  fi
  [ "${#out}" -eq 40 ] || return 1
  # Spelled out, not [!0-9a-f]: a range follows the locale's collation and can admit uppercase.
  case "$out" in *[!0123456789abcdef]*) return 1 ;; esac
  printf '%s\n' "$out"
}

# _pr_base <pr> -- prints the PR's base branch name. Overridable for tests via MEGA_MERGE_PR_BASE_CMD
# (test-only; never set in an unattended run). Nonzero when the read fails or the name is not a
# branch name git accepts (a leading - or @ is refused too) -> caller fails closed.
_pr_base() {
  local out
  if [ -n "${MEGA_MERGE_PR_BASE_CMD:-}" ]; then out="$("$MEGA_MERGE_PR_BASE_CMD" "$1")" || return 1
  else out="$(gh pr view "$1" --json baseRefName --jq .baseRefName 2>/dev/null)" || return 1
  fi
  [ -n "$out" ] || return 1
  case "$out" in -*|@*) return 1 ;; esac
  git check-ref-format --branch "$out" >/dev/null 2>&1 || return 1
  printf '%s\n' "$out"
}

# _pr_fetch <pr> <sha> <base-branch> -- fetches the PR head and its base branch from origin into the
# private refs refs/kit/pr-<pr>/head and /base (not FETCH_HEAD, so two merges cannot overwrite each
# other), checks the head ref equals <sha>, and prints the base tip. Returns 1 on a failed or timed-out
# fetch (MEGA_MERGE_FETCH_TIMEOUT seconds, default 60; no prompt) and 2 on a head mismatch. The private
# refs are deleted on every failure here and by `merge` after the gate. MEGA_MERGE_PR_FETCH_CMD
# replaces all of this, the comparison included (test-only; never set in an unattended run).
_pr_fetch() {
  local pr="$1" sha="$2" bb="$3" root fpid ticks rc got tip
  if [ -n "${MEGA_MERGE_PR_FETCH_CMD:-}" ]; then "$MEGA_MERGE_PR_FETCH_CMD" "$pr" "$sha" "$bb"; return; fi
  root="${MEGA_MERGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$root" ] || return 1
  # ponytail: a background fetch polled against a deadline, since macOS has no timeout(1). It signals git,
  # not git's helper children; upgrade to a process-group kill if a helper ever outlives the wait.
  # No watchdog subshell: a TERM disposition ignored by the caller would leave one running to its end.
  GIT_TERMINAL_PROMPT=0 git -C "$root" fetch -q origin "+refs/pull/$pr/head:refs/kit/pr-$pr/head" "+refs/heads/$bb:refs/kit/pr-$pr/base" >/dev/null 2>&1 &
  fpid=$!
  ticks=$(( ${MEGA_MERGE_FETCH_TIMEOUT:-60} * 10 ))
  while kill -0 "$fpid" 2>/dev/null; do
    if [ "$ticks" -le 0 ]; then
      kill "$fpid" 2>/dev/null; sleep 1; kill -KILL "$fpid" 2>/dev/null
      break
    fi
    ticks=$((ticks - 1)); sleep 0.1
  done
  wait "$fpid" 2>/dev/null; rc=$?
  if [ "$rc" -ne 0 ]; then _pr_fetch_clean "$root" "$pr"; return 1; fi
  got="$(git -C "$root" rev-parse --verify -q "refs/kit/pr-$pr/head^{commit}" 2>/dev/null || true)"
  tip="$(git -C "$root" rev-parse --verify -q "refs/kit/pr-$pr/base^{commit}" 2>/dev/null || true)"
  if [ -z "$tip" ]; then _pr_fetch_clean "$root" "$pr"; return 1; fi
  if [ "$got" != "$sha" ]; then _pr_fetch_clean "$root" "$pr"; return 2; fi
  printf '%s\n' "$tip"
}

# _pr_fetch_clean <root> <pr> -- drops the private refs so they pin no objects against gc.
_pr_fetch_clean() {
  git -C "$1" update-ref -d "refs/kit/pr-$2/head" >/dev/null 2>&1 || true
  git -C "$1" update-ref -d "refs/kit/pr-$2/base" >/dev/null 2>&1 || true
}

# _merge_exclusion <pr> -- the CODE-LEVEL gate/held-final exclusion,
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

# _pr_files <pr> -- prints the PR's changed file names, one per line. Overridable for tests via
# MEGA_MERGE_PR_FILES_CMD. Nonzero when the list cannot be read (gh error / offline).
_pr_files() {
  local out n
  if [ -n "${MEGA_MERGE_PR_FILES_CMD:-}" ]; then out="$("$MEGA_MERGE_PR_FILES_CMD" "$1")" || return 1
  else
    # `gh pr diff --name-only` lists only a rename's new name; the REST files list carries both sides.
    out="$(gh api "repos/{owner}/{repo}/pulls/$1/files" --paginate --jq '.[] | .filename, (.previous_filename // empty)' 2>/dev/null)" || return 1
  fi
  # The REST endpoint returns at most 3000 files: a list this long may be cut, so it is unclassifiable.
  n="$(printf '%s\n' "$out" | grep -c .)"
  [ "$n" -lt 3000 ] || return 1
  printf '%s\n' "$out"
}

# _merge_config_guard <pr> -- a PR that touches the root .kit.toml is never auto-merged: the file holds
# the hard-path exemptions and the gate switches, and the full lane's gates are agent-run, so a human
# reads that change. A file-level rule on purpose: an exemption entry spans several lines, so a match
# on changed lines would miss an edit to only an entry's `paths =` line. Kept out of _merge_exclusion,
# which `mark` re-runs to confirm a hold landed and so must stay state-only.
#   return 0 + a reason -> refuse;  return 1 -> clear;  return 2 -> the file list is unreadable or empty.
_merge_config_guard() {
  local files
  files="$(_pr_files "$1")" || return 2
  [ -n "$files" ] || return 2
  if printf '%s\n' "$files" | grep -qxF '.kit.toml'; then
    echo "touches .kit.toml (hard-path and gate config); a human merges it"; return 0
  fi
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

  # Head pin. Read the head FIRST: the merge below succeeds only if the PR head still equals H, and H
  # was read before the PR-state guards, so each of them read H or a newer head (which fails the
  # merge). Do not move this read after a guard. The gate below runs on H itself (fetched from
  # refs/pull/<pr>/head and checked equal to H), so its diff rules see the commit GitHub merges.
  local head excl rc
  head="$(_pr_head "$pr")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "BLOCKED: cannot read PR #$pr head commit (gh unavailable/offline); failing closed and refusing auto-merge. Verify + merge manually if intended." >&2
    _log "$rid" "BLOCKED merge pr=$pr (head unreadable, fail-closed)"
    return 1
  fi

  # CODE-LEVEL gate/held-final exclusion, checked BEFORE the gate so a
  # held PR is refused even if its gates pass. Fail-closed: unreadable state is refused.
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

  excl="$(_merge_config_guard "$pr")"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "BLOCKED: refusing to auto-merge PR #$pr -- $excl." >&2
    _log "$rid" "BLOCKED merge pr=$pr (config guard: $excl)"
    return 1
  elif [ "$rc" -eq 2 ]; then
    echo "BLOCKED: cannot classify PR #$pr: its changed files are unreadable (gh unavailable/offline); failing closed and refusing auto-merge. Verify + merge manually if intended." >&2
    _log "$rid" "BLOCKED merge pr=$pr (changed files unreadable, fail-closed)"
    return 1
  fi

  # Gate on the PR head GitHub merges, not on this checkout's HEAD: fetch the head and its base branch,
  # check the head is the pinned one, and hand both to the gate. The base comes from the PR's own base
  # branch, so a wave PR is not charged for earlier waves' changes.
  local base_branch tip root
  base_branch="$(_pr_base "$pr")"; rc=$?
  if [ "$rc" -eq 0 ]; then tip="$(_pr_fetch "$pr" "$head" "$base_branch")"; rc=$?; fi
  if [ "$rc" -eq 2 ]; then
    echo "BLOCKED: PR #$pr head moved after it was pinned ($head); refusing auto-merge, rerun to pin the new head." >&2
    _log "$rid" "BLOCKED merge pr=$pr (head moved after pin)"
    return 1
  elif [ "$rc" -ne 0 ]; then
    echo "BLOCKED: cannot fetch PR #$pr head or base from origin; failing closed and refusing auto-merge." >&2
    _log "$rid" "BLOCKED merge pr=$pr (fetch failed, fail-closed)"
    return 1
  fi

  local gate_out
  gate_out="$(gate "$rid" "$lane" --head "$head" --base-tip "$tip" 2>&1)"; rc=$?
  root="${MEGA_MERGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -z "$root" ] || _pr_fetch_clean "$root" "$pr"
  if [ "$rc" -ne 0 ]; then
    {
      echo "BLOCKED: ship-gate not satisfied, refusing auto-merge for PR #$pr (rid=$rid, lane=$lane)."
      printf '%s\n' "$gate_out" | sed 's/^/  /'
      echo "Run the missing gate(s), or record an explicit override (audited):"
      echo "  bash \"$GATE_LEDGER\" override $rid <phase> \"<reason>\""
    } >&2
    _log "$rid" "BLOCKED merge pr=$pr lane=$lane (gate failed)"
    return 1
  fi

  local cmd_str="gh pr merge $pr --squash --delete-branch --match-head-commit $head"
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

  # --match-head-commit pins only the head: a base retarget after the gate would change what the merge
  # lands on, so read the base again and refuse when it moved.
  if [ "$(_pr_base "$pr")" != "$base_branch" ]; then
    echo "BLOCKED: PR #$pr base branch changed after the gate ran (was $base_branch); refusing auto-merge, rerun to gate the new base." >&2
    _log "$rid" "BLOCKED merge pr=$pr (base changed after gate)"
    return 1
  fi

  echo "EXECUTING: $cmd_str"
  _log "$rid" "EXECUTE merge pr=$pr lane=$lane posture=$posture"
  gh pr merge "$pr" --squash --delete-branch --match-head-commit "$head"
}

# mark <pr> [repo] -- the MARK half of the merge-exclusion guard. The guard
# (_merge_exclusion) defends a PR that CARRIES a mark but cannot synthesize one, so an
# UN-marked gate/gated-final PR would slip through. This opens the mark: it puts a
# gate-tagged sub-goal PR (and the held final PR) into exactly the state the guard refuses
# -- a DRAFT (GitHub-intrinsic: GitHub itself blocks merging a draft) PLUS the `do-not-merge`
# hold label (the belt-and-suspenders the code guard also reads). Called by commands/mega.md
# right after such a PR is opened. Idempotent (safe to re-run); routes gh through MEGA_MERGE_GH
# so tests assert the calls without touching GitHub. The label is ensured first so a later
# `--add-label` never fails on a repo that lacks it.
mark() {
  local pr="${1:-}" repo="${2:-}"
  case "$pr" in ''|*[!0-9]*) echo "mark: <pr> must be a bare PR number (got '$pr')" >&2; return 64 ;; esac
  local gh="${MEGA_MERGE_GH:-gh}"
  # ${rf[@]+"${rf[@]}"} is the set -u-safe empty-array expansion (bash 3.2 on the macos CI runner
  # throws "unbound variable" on a bare "${rf[@]}" over an empty array under set -u; same guard as
  # _merge_exclusion's larr handling above).
  local rf=(); [ -n "$repo" ] && rf=(--repo "$repo")
  # idempotent label-ensure (|| true: already exists is the common case)
  "$gh" label create do-not-merge ${rf[@]+"${rf[@]}"} --color B60205 --description "held: do not auto-merge (mega gate/gated-final)" >/dev/null 2>&1 || true
  # draft = the primary, GitHub-intrinsic block; `pr ready --undo` converts an open PR to draft
  "$gh" pr ready "$pr" ${rf[@]+"${rf[@]}"} --undo >/dev/null 2>&1 || true
  # do-not-merge label = the mark the code guard (_merge_exclusion) reads
  "$gh" pr edit "$pr" ${rf[@]+"${rf[@]}"} --add-label do-not-merge >/dev/null 2>&1 || true
  # Confirm the mark actually landed (TIER-4 security review, Medium). The three calls
  # above are best-effort (|| true) so a gh auth/rate-limit/wrong-repo/creation-race failure never
  # crashes the loop -- but a silent no-op that still reported success would leave a held PR
  # UNPROTECTED while claiming otherwise. Reuse _merge_exclusion as the verifier: mark succeeded
  # iff the guard would now REFUSE the PR (rc 0 = held). rc 1 (clear) or 2 (unreadable) => the
  # mark did not land; WARN + nonzero so a caller/CI can react instead of trusting a success string.
  _merge_exclusion "$pr" >/dev/null 2>&1; local mrc=$?
  if [ "$mrc" -eq 0 ]; then
    echo "marked PR #$pr held: draft + do-not-merge"
    return 0
  fi
  echo "mark: WARN PR #$pr is NOT confirmed held after marking (exclusion rc=$mrc); the draft/label may not have landed (gh auth / wrong repo / PR not yet visible). Verify + re-mark manually before relying on the guard." >&2
  return 1
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  gate)  gate "$@" ;;
  merge) merge "$@" ;;
  mark)  mark "$@" ;;
  *) echo "usage: mega-merge.sh {gate <rid> <lane>|merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]|mark <pr> [repo]}" >&2; exit 64 ;;
esac
