#!/usr/bin/env bash
# lib/loop/ql-verdict.sh is the one parser for QL-VERDICT round markers, and `resume` derives a
# bounded loop's position from its own record (docs/briefs/DECISION-BRIEF-loop-resume.md).
#
# Run: bash tests/test-ql-verdict.sh   (exit 0 = all green)
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QV="$KIT_DIR/lib/loop/ql-verdict.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got [$2] want [$3]"; fi; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

mk() { printf '%s\n' "${@:2}" > "$TMP/$1"; }

# ---- parse ----
mk plain 'intro' '[[QL-VERDICT round=1 clean=false findings=4]]' 'text' '`[[QL-VERDICT round=2 clean=true findings=0]]`'
eq "parse: file order, backticks allowed" "$(bash "$QV" parse "$TMP/plain")" $'1 false 4\n2 true 0'

mk none 'no markers here'
eq "parse: no markers prints nothing" "$(bash "$QV" parse "$TMP/none")" ""

eq "parse: missing file prints nothing" "$(bash "$QV" parse "$TMP/absent")" ""

mk badvalue '[[QL-VERDICT round=1 clean=maybe findings=2]]'
out=$(bash "$QV" parse "$TMP/badvalue" 2>&1 >/dev/null); rc=$?
eq "parse: malformed marker exits 65" "$rc" "65"
case "$out" in *"malformed QL-VERDICT"*"clean=maybe"*) pass "parse: malformed marker names the line" ;; *) fail "parse: stderr was [$out]" ;; esac

mk prose 'The QL-VERDICT marker is emitted per round.'
bash "$QV" parse "$TMP/prose" >/dev/null 2>&1; eq "parse: prose naming QL-VERDICT is loud" "$?" "65"

mk mixed '[[QL-VERDICT round=1 clean=false findings=2]] [[QL-VERDICT round=2 clean=tru findings=0]]'
bash "$QV" parse "$TMP/mixed" >/dev/null 2>&1; eq "parse: valid plus corrupt on one line fails" "$?" "65"

bash "$QV" >/dev/null 2>&1; eq "no verb exits 64" "$?" "64"
bash "$QV" parse >/dev/null 2>&1; eq "parse without a file exits 64" "$?" "64"

# ---- resume ----
eq "resume: missing file" "$(bash "$QV" resume "$TMP/absent")" "round=1 clean_streak=0 last_findings=-"
eq "resume: no markers" "$(bash "$QV" resume "$TMP/none")" "round=1 clean_streak=0 last_findings=-"

mk falling '[[QL-VERDICT round=1 clean=false findings=5]]' '[[QL-VERDICT round=2 clean=false findings=2]]'
eq "resume: dirty tail" "$(bash "$QV" resume "$TMP/falling")" "round=3 clean_streak=0 last_findings=2"

mk streak2 '[[QL-VERDICT round=1 clean=false findings=3]]' '[[QL-VERDICT round=2 clean=true findings=0]]' '[[QL-VERDICT round=3 clean=true findings=0]]'
eq "resume: two clean at the end" "$(bash "$QV" resume "$TMP/streak2")" "round=4 clean_streak=2 last_findings=0"

mk broken '[[QL-VERDICT round=1 clean=true findings=0]]' '[[QL-VERDICT round=2 clean=false findings=1]]' '[[QL-VERDICT round=3 clean=true findings=0]]'
eq "resume: a dirty round resets the streak" "$(bash "$QV" resume "$TMP/broken")" "round=4 clean_streak=1 last_findings=0"

mk spec '# Spec' '## Test plan' '[[QL-VERDICT round=9 clean=true findings=0]]' '## Test plan critique' 'Rounds:' '[[QL-VERDICT round=1 clean=false findings=3]]' '[[QL-VERDICT round=2 clean=false findings=1]]' '### Scores' '[[QL-VERDICT round=3 clean=true findings=0]]' '## Review' '[[QL-VERDICT round=8 clean=true findings=0]]'
eq "resume --section: only that section, subsections included" "$(bash "$QV" resume "$TMP/spec" --section '## Test plan critique')" "round=4 clean_streak=1 last_findings=0"
eq "parse --section: lists only that section" "$(bash "$QV" parse "$TMP/spec" --section '## Test plan critique' | wc -l | tr -d ' ')" "3"
eq "resume --section: absent heading is a fresh start" "$(bash "$QV" resume "$TMP/spec" --section '## Nope')" "round=1 clean_streak=0 last_findings=-"
eq "resume: whole file without --section sees every marker" "$(bash "$QV" resume "$TMP/spec")" "round=10 clean_streak=2 last_findings=0"

bash "$QV" resume "$TMP/badvalue" >/dev/null 2>&1; eq "resume: malformed marker exits 65" "$?" "65"

# ---- one parser: stats.sh no longer carries its own grammar ----
if grep -q 'QL_OK=' "$KIT_DIR/lib/gauntlet/stats.sh"; then fail "stats.sh still keeps its own QL-VERDICT grammar"; else pass "stats.sh keeps no copy of the grammar"; fi
grep -q 'ql-verdict.sh' "$KIT_DIR/lib/gauntlet/stats.sh" && pass "stats.sh calls ql-verdict.sh" || fail "stats.sh does not call ql-verdict.sh"

# ---- prose wiring: every loop command names the resume verb ----
for c in gauntlet test-plan-review-team ui-design verify; do
  grep -q 'lib/loop/ql-verdict.sh resume' "$KIT_DIR/commands/$c.md" && pass "commands/$c.md names the resume verb" || fail "commands/$c.md does not name the resume verb"
done
grep -q 'gate-ledger.sh action <rid> greenlight-retry' "$KIT_DIR/commands/greenlight.md" && pass "greenlight appends retry ACTION lines" || fail "greenlight does not append retry ACTION lines"
grep -q 'gate-ledger.sh actions <rid> greenlight-retry' "$KIT_DIR/commands/greenlight.md" && pass "greenlight counts retries from the ledger" || fail "greenlight does not count retries from the ledger"
# ui-design: visual-team rewrites '## Visual critique' each round, so markers and resume must use the append-only section.
grep -q "resume <spec> --section '## UI design rounds'" "$KIT_DIR/commands/ui-design.md" && pass "ui-design resumes from the append-only rounds section" || fail "ui-design resumes from a section visual-team rewrites"
if grep -q "ql-verdict.sh resume <spec> --section '## Visual critique'" "$KIT_DIR/commands/ui-design.md"; then fail "ui-design still resumes from ## Visual critique"; else pass "ui-design no longer resumes from ## Visual critique"; fi
if grep -q 'in this session only' "$KIT_DIR/commands/greenlight.md"; then fail "greenlight still counts retries in session only"; else pass "greenlight no longer counts in context"; fi

echo ""
[ "$FAILED" -eq 0 ] && echo "ql-verdict: all passed" || echo "ql-verdict: $FAILED failed"
[ "$FAILED" -eq 0 ]
