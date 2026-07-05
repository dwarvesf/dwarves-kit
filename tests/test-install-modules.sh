#!/usr/bin/env bash
# test-install-modules.sh -- ID-277 SG-04 (kit-modularity, install/wire): install.sh is
# LAYERED. The spine (safety-gate, ship-gate, spec-drift-guard, secrets-guard,
# commit-format, anti-rationalization) is always wired; every other hook belongs to an
# opt-in module (`--with <a,b,c>`), recorded in a `kit.toml [modules]` manifest that
# DRIVES the shell wiring above -- it is never a runtime feature-registry a hook reads
# (see the standing anti-drift lint at the bottom of this file).
#
# Run: bash tests/test-install-modules.sh
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
assert_true() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

wired_hooks() { # $1 = settings.json path
  jq -r '[.hooks // {} | to_entries[]? | .value[]? | .hooks[]? | .command] | .[]' "$1" 2>/dev/null \
    | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh' | sed 's#hooks/##' | sort -u
}

# ============================================================
echo "== NC spine-only: a plain temp-HOME install wires ONLY the spine =="
# ============================================================
H1="$(mktemp -d)"
HOME="$H1" bash "$KIT_DIR/install.sh" >/tmp/kitmod-h1.log 2>&1
WIRED1="$(wired_hooks "$H1/.claude/settings.json")"
EXPECT_SPINE="anti-rationalization.sh
commit-format.sh
safety-gate.sh
secrets-guard.sh
ship-gate.sh
spec-drift-guard.sh"
assert_true "spine-only install wires exactly the 6 spine hooks" "$([ "$WIRED1" = "$EXPECT_SPINE" ]; echo $?)"
NON_SPINE="$(printf '%s\n' "$WIRED1" | grep -vFxf <(printf '%s\n' "$EXPECT_SPINE") || true)"
assert_true "spine-only install: no optional-module hook present (extra: ${NON_SPINE:-none})" "$([ -z "$NON_SPINE" ]; echo $?)"
assert_true "spine-only install: kit.toml has team_mode = false" "$(grep -qx 'team_mode = false' "$H1/.claude/dwarves-kit/kit.toml"; echo $?)"
OPT_TRUE="$(grep -E '^[a-z_]+ = true$' "$H1/.claude/dwarves-kit/kit.toml" 2>/dev/null || true)"
assert_true "spine-only install: no module recorded true in kit.toml" "$([ -z "$OPT_TRUE" ]; echo $?)"

# ============================================================
echo "== NC --with board,stats: wires exactly those + records in kit.toml; re-run reproduces =="
# ============================================================
H2="$(mktemp -d)"
HOME="$H2" bash "$KIT_DIR/install.sh" --with board,stats >/tmp/kitmod-h2.log 2>&1
WIRED2="$(wired_hooks "$H2/.claude/settings.json")"
EXPECT_BOARD="$(printf '%s\nbacklog-stage.sh' "$EXPECT_SPINE" | sort -u)"
assert_true "--with board,stats wires spine + backlog-stage.sh (board's hook) only" "$([ "$WIRED2" = "$EXPECT_BOARD" ]; echo $?)"
assert_true "kit.toml records board = true" "$(grep -qx 'board = true' "$H2/.claude/dwarves-kit/kit.toml"; echo $?)"
assert_true "kit.toml records stats = true (hookless module, still recorded)" "$(grep -qx 'stats = true' "$H2/.claude/dwarves-kit/kit.toml"; echo $?)"
assert_true "kit.toml records session = false (not requested)" "$(grep -qx 'session = false' "$H2/.claude/dwarves-kit/kit.toml"; echo $?)"

HOME="$H2" bash "$KIT_DIR/install.sh" >/tmp/kitmod-h2-rerun.log 2>&1
WIRED2B="$(wired_hooks "$H2/.claude/settings.json")"
assert_true "re-run (no --with) reproduces the same wired set from the manifest" "$([ "$WIRED2" = "$WIRED2B" ]; echo $?)"

# ============================================================
echo "== NC un-opted-hook-absent: a cosmetic/session/advisor hook never reaches settings.json =="
# ============================================================
UNWANTED="auto-format.sh notification.sh slop-cleaner.sh statusline.sh codebase-index.sh permission-auto-approve.sh context-hints.sh harvest.sh session-state-save.sh citation-guard.sh context-readiness.sh output-offload.sh pre-compact-backup.sh post-compact-reinject.sh"
LEAKED=""
for h in $UNWANTED; do
  printf '%s\n' "$WIRED2" | grep -qx "$h" && LEAKED="$LEAKED $h"
done
assert_true "no un-opted-in module hook present after --with board,stats (leaked:${LEAKED:-none})" "$([ -z "$LEAKED" ]; echo $?)"

# ============================================================
echo "== NC team_mode reserved: --with team_mode is a clean error, not installable =="
# ============================================================
H3="$(mktemp -d)"
ERR3="$(HOME="$H3" bash "$KIT_DIR/install.sh" --with team_mode 2>&1)"; RC3=$?
assert_true "--with team_mode exits nonzero" "$([ "$RC3" -ne 0 ]; echo $?)"
assert_true "--with team_mode error names the reserved reason" "$(printf '%s' "$ERR3" | grep -qi 'reserved'; echo $?)"
assert_true "--with team_mode never wrote a settings.json" "$([ ! -f "$H3/.claude/settings.json" ]; echo $?)"

# ============================================================
echo "== NC unknown module name: clean error, not silent =="
# ============================================================
H4="$(mktemp -d)"
ERR4="$(HOME="$H4" bash "$KIT_DIR/install.sh" --with bogus-module 2>&1)"; RC4=$?
assert_true "--with bogus-module exits nonzero" "$([ "$RC4" -ne 0 ]; echo $?)"
assert_true "--with bogus-module error names the unknown module" "$(printf '%s' "$ERR4" | grep -q 'bogus-module'; echo $?)"
assert_true "--with bogus-module never wrote a settings.json" "$([ ! -f "$H4/.claude/settings.json" ]; echo $?)"

# ============================================================
echo "== NC existing-consumer migration: re-running install.sh is ADDITIVE, never un-wires =="
# ============================================================
# Simulate the pre-SG-04 all-hooks installer: seed settings.json with the FULL
# (unfiltered) kit settings.json, no kit.toml yet.
H5="$(mktemp -d)"
mkdir -p "$H5/.claude"
cp "$KIT_DIR/settings.json" "$H5/.claude/settings.json"
BEFORE5="$(wired_hooks "$H5/.claude/settings.json")"
BEFORE5_N="$(printf '%s\n' "$BEFORE5" | grep -c .)"
HOME="$H5" bash "$KIT_DIR/install.sh" >/tmp/kitmod-h5.log 2>&1
AFTER5="$(wired_hooks "$H5/.claude/settings.json")"
DROPPED="$(comm -23 <(printf '%s\n' "$BEFORE5") <(printf '%s\n' "$AFTER5"))"
assert_true "additive re-install drops nothing from an old all-hooks install (before=$BEFORE5_N, dropped:${DROPPED:-none})" "$([ -z "$DROPPED" ]; echo $?)"

# ============================================================
echo "== NC --prune: the explicit, only way to trim a previously-wired hook =="
# ============================================================
H6="$(mktemp -d)"
mkdir -p "$H6/.claude"
cp "$KIT_DIR/settings.json" "$H6/.claude/settings.json"
HOME="$H6" bash "$KIT_DIR/install.sh" --prune --with board >/tmp/kitmod-h6.log 2>&1
WIRED6="$(wired_hooks "$H6/.claude/settings.json")"
EXPECT_PRUNE="$(printf '%s\nbacklog-stage.sh' "$EXPECT_SPINE" | sort -u)"
assert_true "--prune --with board trims to exactly spine + board (drops the old all-hooks set)" "$([ "$WIRED6" = "$EXPECT_PRUNE" ]; echo $?)"

# ============================================================
echo "== POST-INSTALL SMOKE: every wired hook script runs cleanly (exit 0) on a no-op event =="
# ============================================================
H7="$(mktemp -d)"
HOME="$H7" bash "$KIT_DIR/install.sh" --with board,session,advisor,cosmetic,queue,stats,quiz_gate,weekend_batch,bridge >/tmp/kitmod-h7.log 2>&1
# Invoke each installed hook from a real (throwaway) git repo, not the kit checkout
# itself, so a hook's project-root-relative reads (e.g. .claude/backups, docs/specs)
# see a clean, self-consistent tree instead of the kit's own live dev state.
SMOKE_REPO="$(mktemp -d)"
git -C "$SMOKE_REPO" init -q
mkdir -p "$SMOKE_REPO/.claude/backups" "$SMOKE_REPO/docs/specs"
SMOKE_FAIL=0; SMOKE_N=0
for h in "$H7/.claude/dwarves-kit/hooks/"*.sh; do
  SMOKE_N=$((SMOKE_N+1))
  ( cd "$SMOKE_REPO" && echo '{}' | bash "$h" >/tmp/kitmod-smoke-out 2>&1 )
  rc=$?
  if [ "$rc" -ne 0 ]; then SMOKE_FAIL=$((SMOKE_FAIL+1)); echo "    smoke-fail: $(basename "$h") exit=$rc"; fi
done
assert_true "post-install smoke: all $SMOKE_N wired hooks exit 0 on a no-op event ($SMOKE_FAIL failed)" "$([ "$SMOKE_FAIL" -eq 0 ]; echo $?)"

# ============================================================
echo "== STANDING ANTI-DRIFT LINT: no hook reads kit.toml at runtime (record, not registry) =="
# ============================================================
LEAK="$(grep -rl 'kit\.toml' "$KIT_DIR/hooks" 2>/dev/null || true)"
assert_true "no hooks/*.sh reads kit.toml (leaked: ${LEAK:-none})" "$([ -z "$LEAK" ]; echo $?)"

# ============================================================
echo "== COVERAGE-DELTA: every module in the manifest maps to a real installable unit =="
# ============================================================
# Each optional module either has >=1 hook that exists on disk, or is a documented
# hookless module backed by a real command/skill/lib subsystem.
declare -a HOOKED_MODULES=(board session advisor cosmetic)
declare -a HOOKLESS_MODULES=(queue stats quiz_gate weekend_batch bridge)
COV_FAIL=""
for m in "${HOOKED_MODULES[@]}"; do
  case "$m" in
    board) HOOKS="backlog-stage.sh" ;;
    session) HOOKS="context-readiness.sh output-offload.sh pre-compact-backup.sh post-compact-reinject.sh session-state-save.sh harvest.sh citation-guard.sh" ;;
    advisor) HOOKS="context-hints.sh" ;;
    cosmetic) HOOKS="auto-format.sh notification.sh slop-cleaner.sh statusline.sh codebase-index.sh permission-auto-approve.sh" ;;
  esac
  for h in $HOOKS; do
    [ -f "$KIT_DIR/hooks/$h" ] || COV_FAIL="$COV_FAIL $m:$h"
  done
done
[ -d "$KIT_DIR/lib/queue" ] || COV_FAIL="$COV_FAIL queue:lib/queue"
[ -d "$KIT_DIR/lib/stats" ] || COV_FAIL="$COV_FAIL stats:lib/stats"
[ -f "$KIT_DIR/commands/quiz-gate.md" ] || COV_FAIL="$COV_FAIL quiz_gate:commands/quiz-gate.md"
grep -rq "weekend" "$KIT_DIR/commands" 2>/dev/null || COV_FAIL="$COV_FAIL weekend_batch:commands"
grep -rq "bridge" "$KIT_DIR/lib/board" 2>/dev/null || COV_FAIL="$COV_FAIL bridge:lib/board"
assert_true "every manifest module maps to a real installable unit (missing:${COV_FAIL:-none})" "$([ -z "$COV_FAIL" ]; echo $?)"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
