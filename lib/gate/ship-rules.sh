#!/usr/bin/env bash
# ship-rules.sh -- sourced helper: the ship-gate rules that read the repo diff and the spec, in one place.
#
# hooks/ship-gate.sh (the push gate) and lib/goal/mega-merge.sh gate (the mega loop's merge gate)
# both source this file, so a green mega gate means the push passes these rules.
#
#   ship_rules_resolve_base <root>                 the remote default branch ref, else empty
#   ship_rules_merge_base <root> <head>            merge base of <head> and the default branch
#   ship_rules_switch_on <key> <root> [<ref>]      0 unless [gate] <key> is explicitly off (reader exit 1)
#   ship_rules_ledger_check <root> <lane> <rid> <ledger> [<base>]
#                                                  the lane's ledger check with the repo's project config
#                                                  (KIT_PROJECT_ROOT=<root>), so a project lane override
#                                                  reads the same for every caller; with <base> the project
#                                                  lanes come from the .kit.toml committed at <base>
#   ship_rule_large_spec <spec> <rid> <lane> <ledger>
#                                                  a large normal-lane spec needs a validate ran/override
#   ship_rule_floor <root> <base> <head> <rid> <spec> <ledger>
#                                                  a hard-path diff owes the full lane's gates
#
# The two rule functions print the BLOCKED message on stderr and return 2; they return 0 on a pass
# and on any ambiguity (missing tooling, no base): the ship-gate is a quality gate that fails open.
# They write the audit log only when SHIP_RULES_LOG=1 (the hook sets it; the mega gate stays
# side-effect free). Sibling libs resolve from this file's own location.
#
# No `set` options here: the file is sourced into callers that own theirs.

_SR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SR_POLICY="$_SR_DIR/gate-policy.sh"
_SR_LCLS="$_SR_DIR/../classify/lane-classify.sh"
_SR_SPEC_SH="$_SR_DIR/../spec/spec.sh"

_sr_log() {  # _sr_log <log-line-tail>
  [ "${SHIP_RULES_LOG:-0}" = 1 ] || return 0
  local log_dir="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$log_dir" 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $1" >> "$log_dir/ship-gate.log" 2>/dev/null || true
}

# The base is the REMOTE default branch: origin/HEAD, else origin/main or origin/master. A local
# branch can carry unpushed commits and would hide them from the diff. Only a repo with no origin
# at all falls back to local main or master. An origin with no remote-tracking default gives no
# base, and the callers skip their checks.
ship_rules_resolve_base() {
  local root="$1" ref c
  ref=$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  [ -z "$ref" ] || { echo "$ref"; return 0; }
  if git -C "$root" remote get-url origin >/dev/null 2>&1; then
    for c in origin/main origin/master; do
      git -C "$root" rev-parse --verify -q "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }
    done
    return 0
  fi
  git -C "$root" rev-parse --verify -q main >/dev/null 2>&1 && echo main || echo master
}

ship_rules_merge_base() {
  git -C "$1" merge-base "$2" "$(ship_rules_resolve_base "$1")" 2>/dev/null || true
}

# Only exit 1 from the reader means off. A missing or broken reader (any other exit) means ON:
# switching a gate off has to be explicit.
ship_rules_switch_on() {
  local key="$1" root="$2" at="${3:-}" rc=0
  [ -f "$_SR_POLICY" ] || return 0
  if [ -n "$at" ]; then bash "$_SR_POLICY" enabled "$key" "$root" --at "$at" || rc=$?
  else bash "$_SR_POLICY" enabled "$key" "$root" || rc=$?; fi
  [ "$rc" -eq 1 ] || return 0
  return 1
}

# The project lanes are read at the merge base when one is known, never from the PR head: a PR cannot
# rewrite its own lanes (the floor and the [gate] switch already read at the merge base).
ship_rules_ledger_check() {
  KIT_LANE_PROJECT_AT="${5:-}" KIT_PROJECT_ROOT="$1" bash "$4" check "$2" "$3"
}

# Validate by size: the normal lane lists validate as lite (not required), so nothing in the ledger
# check stops a LARGE normal-lane spec from shipping unvalidated. `spec.sh depth size` exits 1 on a
# large spec; only that exact code engages. A missing spec.sh or an unreadable spec (exit 2) fails open.
ship_rule_large_spec() {
  local spec="$1" rid="$2" lane="$3" ledger="$4" size_rc rid_q
  [ "$lane" = normal ] && [ -f "$_SR_SPEC_SH" ] || return 0
  bash "$_SR_SPEC_SH" depth size "$spec" >/dev/null 2>&1; size_rc=$?
  [ "$size_rc" -eq 1 ] || return 0
  bash "$ledger" show "$rid" 2>/dev/null | awk -F' [|] ' '$2=="GATE" && $3=="validate"{s=$4} END{exit !(s=="ran"||s=="override")}' && return 0
  rid_q=$(printf '%q' "$rid")
  _sr_log "BLOCKED | ship-gate | $rid ($lane, large, no validate)"
  {
    echo "BLOCKED: ship-gate. Spec '$rid' is large (4+ tasks, a deeper Depth, or no countable task) and has no validate gate that ran or was overridden."
    echo "Rule: a large normal-lane spec needs the fresh-context validation before it ships (\`bash <kit>/lib/spec/spec.sh depth size $spec\`). Run /kit:spec-validate, or log an explicit override (recorded for audit):"
    echo "  bash \"$ledger\" override $rid_q validate \"<reason>\""
    echo "Or switch the lane gates off for this repo: [gate] lane_gates = false in the committed project kit config (lib/gate/README.md, 'Switching a gate off')."
  } >&2
  return 2
}

# Diff floor (hard paths). The path test lives in lib/classify/lane-classify.sh `floor`. A hit means
# the full lane's gates apply whatever the spec's Lane says. The floor follows [gate] lane_gates as of
# the MERGE BASE, never the PR head, so a PR cannot switch off its own floor. Full-lane gates are read
# from the kit and operator layers only (--kit-lanes).
ship_rule_floor() {
  local root="$1" base="$2" head="$3" rid="$4" spec="$5" ledger="$6" hit gaps fk rid_q
  [ -f "$ledger" ] || return 0
  [ -n "$base" ] || return 0
  if ! ship_rules_switch_on lane_gates "$root" "$base"; then
    _sr_log "OFF-BY-CONFIG | floor | $rid"
    return 0
  fi
  [ -f "$_SR_LCLS" ] || return 0
  [ "$base" != "$(git -C "$root" rev-parse "$head" 2>/dev/null || true)" ] || return 0
  hit=$(bash "$_SR_LCLS" floor "$root" "$base" "$head" 2>/dev/null || true)
  [ -n "$hit" ] || return 0
  gaps=$(KIT_PROJECT_ROOT="$root" bash "$ledger" check full "$rid" --kit-lanes 2>&1) && return 0
  fk="${hit#full }"
  rid_q=$(printf '%q' "$rid")
  _sr_log "BLOCKED | ship-gate | $rid (hard-path ${fk%%:*})"
  {
    echo "BLOCKED: ship-gate. This diff touches a hard path ($fk); the full lane's gates apply whatever the spec's Lane says:"
    [ -n "$spec" ] || echo "(no spec found for '$rid'; a hard-path diff owes the full lane's gates with or without one)"
    printf '%s\n' "$gaps" | sed 's/^/  /'
    echo "Run the missing gate(s), or log an explicit override (recorded for audit):"
    echo "  bash \"$ledger\" override $rid_q <phase> \"<reason>\""
  } >&2
  return 2
}
