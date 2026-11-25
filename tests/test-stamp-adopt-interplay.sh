#!/usr/bin/env bash
# test-stamp-adopt-interplay.sh -- the stamp and adopt on the same repo, in both orders.
# Depends only on line 1 of lib/adopt/AGENTS.pointer.md (the marker) and adopt's own known-hash
# list, never on the pointer's body text.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }
command -v jq >/dev/null 2>&1 || { echo "ok - jq not found, skipping"; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-adopt.XXXXXX")" || exit 1
# adopt reads the operator's kit config and the Claude home; fence both off, as test-adopt.sh does
mkdir -p "$WORK/operator" "$WORK/claude"
export KIT_CONFIG_OPERATOR="$WORK/operator" CLAUDE_DIR="$WORK/claude"

newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")"; git -C "$d" init -q -b main 2>/dev/null; echo "$d"; }
STAMP="bash $ROOT/lib/stamp.sh"; ADOPT="bash $ROOT/lib/adopt.sh"
FLAGS="--default-branch main --owner alice"
POINTER="$ROOT/lib/adopt/AGENTS.pointer.md"
marker="$(head -n 1 "$POINTER" | tr -d '\r')"
sum() { cksum < "$1"; }

# ===== order A: stamp first, adopt later =====
A="$(newrepo)"
$STAMP $FLAGS "$A" >/dev/null 2>&1
sum_agents="$(sum "$A/AGENTS.md")"; sum_readme="$(sum "$A/docs/verification/README.md")"; sum_kit="$(sum "$A/.kit.toml")"
expect "stamp first: line 1 of AGENTS.md is the kit marker" [ "$(head -n 1 "$A/AGENTS.md")" = "$marker" ]
$ADOPT "$A" >"$WORK/a-adopt.out" 2>&1; arc=$?
expect "adopt after a stamp exits 0" [ "$arc" -eq 0 ]
expect "adopt left the stamp's AGENTS.md alone" [ "$sum_agents" = "$(sum "$A/AGENTS.md")" ]
expect "adopt left the stamp's proof guide alone (it never overwrites the marker file)" [ "$sum_readme" = "$(sum "$A/docs/verification/README.md")" ]
expect "adopt left the stamp's .kit.toml alone, lane_gates stays false" bash -c "[ \"\$1\" = \"\$(cksum < '$A/.kit.toml')\" ] && grep -q 'lane_gates = false' '$A/.kit.toml'" _ "$sum_kit"
$ADOPT --check "$A" >/dev/null 2>&1; expect "adopt --check reports the stamped repo adopted" [ "$?" -eq 0 ]
expect "settings.json holds both the stamp's hook and adopt's entries" bash -c "jq -e '[.. | .command? // empty] | (map(select(test(\"scripts/agent-guard.sh\"))) | length > 0)' '$A/.claude/settings.json' >/dev/null"
out="$($STAMP "$A" 2>&1)"
expect "a stamp after adopt prints only unchanged lines (adopt's settings entries are not drift)" bash -c "[ \$(printf '%s\n' \"\$1\" | grep -E '^(created|merged|edited|older|missing)' | wc -l) -eq 0 ]" _ "$out"
$STAMP --check "$A" >/dev/null 2>&1; expect "stamp --check exits 0 after adopt" [ "$?" -eq 0 ]

# ===== order B: adopt first, stamp later =====
B="$(newrepo)"
$ADOPT "$B" >/dev/null 2>&1
expect "adopt first: AGENTS.md is the kit pointer" bash -c "[ \"\$(head -n 1 '$B/AGENTS.md' | tr -d '\r')\" = \"\$1\" ]" _ "$marker"
expect "adopt seeded lane_gates = true" grep -q 'lane_gates = true' "$B/.kit.toml"
sum_b_agents="$(sum "$B/AGENTS.md")"; sum_b_kit="$(sum "$B/.kit.toml")"; sum_b_readme="$(sum "$B/docs/verification/README.md")"
out="$($STAMP $FLAGS "$B" 2>&1)"; brc=$?
expect "a stamp over an adopted repo exits 0" [ "$brc" -eq 0 ]
expect "AGENTS.md (adopt's pointer) is reported, not rewritten" bash -c "printf '%s\n' \"\$1\" | grep -q '^edited (left alone): AGENTS.md' && [ \"\$2\" = \"\$(cksum < '$B/AGENTS.md')\" ]" _ "$out" "$sum_b_agents"
expect "adopt's proof marker is reported, not rewritten" bash -c "printf '%s\n' \"\$1\" | grep -q '^edited (left alone): docs/verification/README.md' && [ \"\$2\" = \"\$(cksum < '$B/docs/verification/README.md')\" ]" _ "$out" "$sum_b_readme"
expect ".kit.toml keeps lane_gates = true and is reported with a two-line drift" bash -c "grep -q 'lane_gates = true' '$B/.kit.toml' && printf '%s\n' \"\$1\" | grep -qx 'Fix: set lane_gates = false in .kit.toml'" _ "$out"
expect "the stamp never edited .kit.toml" [ "$sum_b_kit" = "$(sum "$B/.kit.toml")" ]
expect "kit hook entries in settings.json are reported and kept" bash -c "printf '%s\n' \"\$1\" | grep -q '^note: .claude/settings.json holds [0-9]* kit hook command' && jq -e '[.. | .command? // empty] | any(contains(\"dwarves-kit\"))' '$B/.claude/settings.json' >/dev/null" _ "$out"
expect "and the stamp's own hook was merged beside them" bash -c "jq -e '[.. | .command? // empty] | any(contains(\"scripts/agent-guard.sh\"))' '$B/.claude/settings.json' >/dev/null"
$STAMP --check "$B" >/dev/null 2>&1; expect "stamp --check exits 1 while the drift stands" [ "$?" -eq 1 ]

# take swaps adopt's own files, and only those
$STAMP --take AGENTS.md "$B" >/dev/null 2>&1; trc=$?
expect "--take AGENTS.md replaces a known kit pointer" [ "$trc" -eq 0 ]
expect "the stamp's AGENTS.md keeps the kit marker on line 1" [ "$(head -n 1 "$B/AGENTS.md")" = "$marker" ]
expect "the old pointer is kept as AGENTS.md.orig" [ "$sum_b_agents" = "$(sum "$B/AGENTS.md.orig")" ]
$STAMP --take docs/verification/README.md "$B" >/dev/null 2>&1
expect "--take swaps adopt's proof marker for the proof guide" bash -c "grep -q 'NEGATIVE CONTROL' '$B/docs/verification/README.md' && [ \"\$1\" = \"\$(cksum < '$B/docs/verification/README.md.orig')\" ]" _ "$sum_b_readme"
$STAMP --take .kit.toml "$B" >"$WORK/take-kit.out" 2>&1; krc=$?
expect "--take .kit.toml is refused (edited, not a known kit file)" [ "$krc" -eq 1 ]
expect "and says to apply the diff by hand" grep -qx 'Fix: apply the diff above by hand' "$WORK/take-kit.out"
expect ".kit.toml is untouched by the refused take" [ "$sum_b_kit" = "$(sum "$B/.kit.toml")" ]
$ADOPT --check "$B" >/dev/null 2>&1; expect "adopt --check still reports the repo adopted after the swaps" [ "$?" -eq 0 ]
sum_after="$(sum "$B/AGENTS.md")"
$ADOPT --refresh "$B" >/dev/null 2>&1
expect "adopt --refresh does not rewrite the stamp's AGENTS.md" [ "$sum_after" = "$(sum "$B/AGENTS.md")" ]

# ===== a repo's own AGENTS.md =====
C="$(newrepo)"; printf '# our rules\n' > "$C/AGENTS.md"
out="$($STAMP $FLAGS "$C" 2>&1)"
expect "a repo's own AGENTS.md is left alone and reported" bash -c "[ \"\$(cat '$C/AGENTS.md')\" = '# our rules' ] && printf '%s\n' \"\$1\" | grep -q '^edited (left alone): AGENTS.md (not written by stamp'" _ "$out"
$STAMP --take AGENTS.md "$C" >/dev/null 2>&1
expect "--take refuses to replace a repo's own file" bash -c "[ \"\$(cat '$C/AGENTS.md')\" = '# our rules' ]"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
