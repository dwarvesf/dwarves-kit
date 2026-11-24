#!/usr/bin/env bash
# test-active-spec-pick.sh -- which spec each caller picks as "the active one", on one fixture repo.
#
# Fixture: branch feat/alpha; root specs 010 alpha (SHIPPED), 020 beta (DRAFT), 030 gamma (DRAFT);
# a co-located tools/x 005 delta; a copy of 020 beta under .claude/worktrees/w. The REAL hooks and
# lib scripts run; every answer is recorded below.
#
# A row marked `gap` pins today's disagreement between callers and names the task that flips it.
# When that task lands, the row is rewritten as an `eq` on the shared answer.
#
# Run: bash tests/test-active-spec-pick.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars)
APS_HOME="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; HOME="$APS_HOME"; export HOME
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DWARVES_KIT_LOG_DIR="$APS_HOME/logs"
unset CLAUDE_PLUGIN_ROOT KIT_LEDGER_DIR DWARVES_KIT_DEBUG

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
# gap <label> <task> <got> <today's answer>: green while the disagreement still stands.
gap() { if [ "$3" = "$4" ]; then ok "$1 [known-gap, flips in $2]"; else bad "$1 [known-gap, flips in $2] (want today's '$4' got '$3')"; fi; }

_td="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; TMP="$(cd "$_td" && pwd -P)"
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP" "$APS_HOME"; }
trap cleanup EXIT

spec() { # <path> <Status line or ""> <body>
  mkdir -p "$(dirname "$1")"
  { printf '# Spec: %s\n\n' "$(basename "$1" .md)"; [ -n "$2" ] && printf 'Status: %s\n\n' "$2"; printf '%s\n' "${3:-}"; } > "$1"
}

# <dir> <branch>: the fixture of the header comment
mkfix() {
  local d="$1" br="$2"
  git init -q -b master "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false
  spec "$d/docs/specs/SPEC-010-alpha.md" SHIPPED "Touches src/alpha_only.ts"
  spec "$d/docs/specs/SPEC-020-beta.md" DRAFT "Touches src/beta_only.ts"
  spec "$d/docs/specs/SPEC-030-gamma.md" DRAFT "Touches src/gamma_only.ts"
  spec "$d/tools/x/docs/specs/SPEC-005-delta.md" DRAFT "Touches src/delta_only.ts"
  spec "$d/.claude/worktrees/w/docs/specs/SPEC-020-beta.md" DRAFT "copy"
  git -C "$d" add -A; git -C "$d" commit -qm init
  git -C "$d" checkout -q -b "$br"
}

# <dir> <branch>: two specs, one DRAFT and one with no Status header
mkheaderless() {
  local d="$1" br="$2"
  git init -q -b master "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false
  spec "$d/docs/specs/SPEC-020-beta.md" DRAFT "Touches src/beta_only.ts"
  spec "$d/docs/specs/SPEC-030-gamma.md" "" "Touches src/gamma_only.ts"
  git -C "$d" add -A; git -C "$d" commit -qm init
  git -C "$d" checkout -q -b "$br"
}

compact_pre()  { ( cd "$1" && rm -rf .claude/backups && echo '{}' | bash "$KIT_DIR/hooks/pre-compact-backup.sh" >/dev/null 2>&1; sed -n '/^### Active spec/,/^### Recent/p' .claude/backups/*.md | sed -n '2p' ); }
compact_post() { ( cd "$1" && bash "$KIT_DIR/hooks/post-compact-reinject.sh" </dev/null 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | grep '^SPEC: ' ); }
readiness()    { ( cd "$1" && bash "$KIT_DIR/hooks/context-readiness.sh" </dev/null 2>/dev/null | jq -r '.additionalContext' | tr ' ' '\n' | grep '^spec:' ); }
drift()        { ( cd "$1" && printf '{"tool_input":{"file_path":"%s"}}' "$2" | bash "$KIT_DIR/hooks/spec-drift-guard.sh" 2>/dev/null | grep -c 'is not in any active spec' ); }
index_ns()     { ( cd "$1" && bash "$KIT_DIR/lib/spec/spec-index.sh" list 2>/dev/null | grep -v '^ ' | grep -v '^$' ); }

echo "== the pick the ship gate binds to =="
# shellcheck source=lib/spec/spec-find.sh
. "$KIT_DIR/lib/spec/spec-find.sh"
F="$TMP/f1"; mkfix "$F" feat/alpha
eq "spec_for_slug alpha (SHIPPED) picks by name" "$(spec_for_slug "$F" alpha)" "$F/docs/specs/SPEC-010-alpha.md"
eq "spec_for_slug delta picks the co-located spec" "$(spec_for_slug "$F" delta)" "$F/tools/x/docs/specs/SPEC-005-delta.md"
eq "spec_for_slug picks nothing for an unknown slug" "$(spec_for_slug "$F" nope)" ""
eq "spec_for_slug gam (substring of gamma) picks nothing" "$(spec_for_slug "$F" gam)" ""

echo "== ship-gate call site: its own block, extracted and run =="
# The block from the anchor comment to the next section. ROOT, SLUG and the kit path are the only inputs.
block="$(awk '/^# Resolve the spec for this slug; fail open/ {on=1} /^# Build-ran advisory/ {on=0} on' "$KIT_DIR/hooks/ship-gate.sh")"
if [ -n "$block" ]; then ok "ship-gate spec block found"; else bad "ship-gate spec block found"; fi
gate_pick() { ( set -uo pipefail; ROOT="$1"; SLUG="$2"; CLAUDE_PLUGIN_ROOT="$KIT_DIR"; eval "$block"; printf '%s' "$SPEC" ); }
for s in alpha beta gamma delta nope gam ""; do
  eq "ship-gate block == spec_for_slug for slug '$s'" "$(gate_pick "$F" "$s")" "$(spec_for_slug "$F" "$s")"
done

H0="$TMP/f0"; mkheaderless "$H0" feat/zzz
echo "== compaction hooks: the branch's own spec, else ambiguous, never the highest unrelated one =="
eq "pre-compact feat/alpha: ambiguous, not the highest" "$(compact_pre "$F")" "Spec: ambiguous (SPEC-020, SPEC-030)"
eq "post-compact feat/alpha: ambiguous, not the highest" "$(compact_post "$F")" "SPEC: ambiguous (SPEC-020, SPEC-030); state which spec before implementing"
B="$TMP/f2"; mkfix "$B" feat/beta
eq "pre-compact feat/beta: its own spec" "$(compact_pre "$B")" "Spec: docs/specs/SPEC-020-beta.md"
eq "post-compact feat/beta: its own spec" "$(compact_post "$B")" "SPEC: docs/specs/SPEC-020-beta.md (read before implementing)"
mkdir -p "$F/src/deep" "$B/src/deep"
eq "pre-compact from a subdirectory uses the repo root" "$(compact_pre "$B/src/deep")" "Spec: $B/docs/specs/SPEC-020-beta.md"
eq "post-compact from a subdirectory uses the repo root" "$(compact_post "$B/src/deep")" "SPEC: $B/docs/specs/SPEC-020-beta.md (read before implementing)"
eq "pre-compact on a branch with no slash match and a header-less spec" "$(compact_pre "$H0")" "Spec: ambiguous (SPEC-020, SPEC-030)"
# a kit whose lib lacks spec-active.sh (partial install): no spec resolved, the hook still runs
STALE="$TMP/stale-kit"; mkdir -p "$STALE"; cp -R "$KIT_DIR/lib" "$KIT_DIR/hooks" "$STALE/"; rm "$STALE/lib/spec/spec-active.sh"
eq "pre-compact on a partial install: no spec, no crash" "$( cd "$B" && rm -rf .claude/backups && echo '{}' | bash "$STALE/hooks/pre-compact-backup.sh" >/dev/null 2>&1; sed -n '/^### Active spec/,/^### Recent/p' "$B"/.claude/backups/*.md | sed -n '2p')" "No spec found (docs/specs/)"

echo "== readiness =="
eq "readiness feat/alpha: two open specs, no branch match" "$(readiness "$F")" "spec:ambiguous(SPEC-020,SPEC-030)"
eq "readiness feat/beta: the branch's own spec" "$(readiness "$B")" "spec:DRAFT"
H="$TMP/f3"; mkheaderless "$H" feat/zzz
gap "readiness treats a header-less spec as closed" TASK-6 "$(readiness "$H")" "spec:DRAFT"
gap "readiness from a subdirectory finds no spec" TASK-6 "$(readiness "$F/src/deep")" ""

echo "== drift guard: the union of open specs =="
eq "a file named by an open spec (beta) is known" "$(drift "$F" "$F/src/beta_only.ts")" "0"
eq "a file named by another open spec (gamma) is known" "$(drift "$F" "$F/src/gamma_only.ts")" "0"
eq "a file named only by the SHIPPED spec is drift" "$(drift "$F" "$F/src/alpha_only.ts")" "1"
eq "a file named by no spec is drift" "$(drift "$F" "$F/src/unknown.ts")" "1"
eq "a header-less spec counts as open for the guard" "$(drift "$H" "$H/src/gamma_only.ts")" "0"
gap "drift guard from a subdirectory sees no spec and stays silent" TASK-7 "$(drift "$F/src/deep" "$F/src/deep/unknown.ts")" "0"

echo "== spec-index =="
gap "spec-index lists a dot-dir worktree copy as its own namespace" TASK-7 "$(index_ns "$F" | grep -c '^\.claude')" "1"
eq "spec-index lists the central and the co-located namespace" "$(index_ns "$F" | grep -c -e '^central docs/specs' -e '^tools/x')" "2"

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
