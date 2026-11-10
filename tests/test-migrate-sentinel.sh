#!/usr/bin/env bash
# test-migrate-sentinel.sh -- the `.migrated` sentinel means "the legacy corpus is present at the new root".
# A symlinked legacy dir is refused (never copied through), so nothing is copied and no sentinel may be
# written; a distinct `.migrate-refused` marker records the reason. A real legacy dir stays byte-identical:
# files copied, sentinel written.
#
# Run: bash tests/test-migrate-sentinel.sh   (exit 0 = all green)
set -uo pipefail
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KM="$KIT_DIR/lib/telemetry/kit-migrate.sh"
PASS=0; FAIL=0
check() { if eval "$2"; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }

TMPS=()
mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; TMPS+=("$d"); printf '%s' "$d"; }
trap 'for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done' EXIT

# fresh fake HOME with an unpinned durable root (no knob set), legacy dir created by the caller
setup() { HH="$(mk)"; XX="$(mk)"; LEGACY="$HH/.claude/dwarves-kit/logs"; DURABLE="$XX/dwarves-kit/logs"; mkdir -p "$HH/.claude/dwarves-kit"; }
migrate() { env -i PATH="$PATH" HOME="$HH" XDG_STATE_HOME="$XX" KIT_CONFIG_OPERATOR="$HH/none" KIT_CONFIG_ROOT="$HH/none" bash "$KM" 2>"$HH/err.txt"; }

echo "== real legacy dir: byte-identical behavior =="
setup; mkdir -p "$LEGACY/runs"; echo real > "$LEGACY/runs/r.log"
migrate
check "real dir: files copied" '[ -f "$DURABLE/runs/r.log" ]'
check "real dir: sentinel written" '[ -f "$DURABLE/.migrated" ]'

echo "== symlinked legacy dir with files =="
setup; EVIL="$(mk)"; mkdir -p "$EVIL/runs"; echo planted > "$EVIL/runs/p.log"; ln -s "$EVIL" "$LEGACY"
migrate
check "symlink: nothing copied through the link" '[ ! -e "$DURABLE/runs/p.log" ]'
check "symlink: no .migrated sentinel (nothing was copied)" '[ ! -e "$DURABLE/.migrated" ]'
check "symlink: refusal reason recorded in .migrate-refused" 'grep -q symlink "$DURABLE/.migrate-refused" 2>/dev/null'
check "symlink: refusal announced on stderr" 'grep -q symlink "$HH/err.txt"'

echo "== symlink replaced by a real dir: the next run migrates =="
rm "$LEGACY"; mkdir -p "$LEGACY/runs"; echo now-real > "$LEGACY/runs/n.log"
migrate
check "retry: files now copied" '[ -f "$DURABLE/runs/n.log" ]'
check "retry: sentinel written" '[ -f "$DURABLE/.migrated" ]'
check "retry: stale refusal marker cleared" '[ ! -e "$DURABLE/.migrate-refused" ]'

echo "== no legacy dir at all (fresh install) =="
setup
migrate
check "fresh: sentinel written (nothing to copy, nothing missing)" '[ -f "$DURABLE/.migrated" ]'

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
