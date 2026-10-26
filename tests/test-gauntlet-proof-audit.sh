#!/usr/bin/env bash
# test-gauntlet-proof-audit.sh (ID-495): pins the gauntlet-proof-audit skill's
# Tier-1 logic so it is a re-runnable regression, not a one-time hand run.
# The skill is prose (no lib/ script), so this test EXTRACTS the actual item-set
# command verbatim from skills/gauntlet-proof-audit/SKILL.md and runs it, and
# exercises the documented verdict-vs-evidence + scrub rules against fixtures.
# A broken extraction is a failure (the doc drifted out from under the test),
# never a silent skip. Run: bash tests/test-gauntlet-proof-audit.sh
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$KIT_DIR/skills/gauntlet-proof-audit/SKILL.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
TMPS=()
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

echo "=== gauntlet-proof-audit Tier-1 pins (ID-495) ==="

[ -f "$SKILL" ]; assert "skill file exists" $?

# 1. Item-set command: extract the git ls-files invocation verbatim from the
#    four-slots table and confirm it enumerates committed records only.
ITEMSET="$(grep -oE "git ls-files '[^|]*ROUNDS\.md'" "$SKILL" | head -1)"
[ -n "$ITEMSET" ]; assert "extracted the item-set command from SKILL.md" $?
if [ -n "$ITEMSET" ]; then
  COUNT="$(cd "$KIT_DIR" && eval "$ITEMSET" | wc -l | tr -d ' ')"
  [ "${COUNT:-0}" -ge 1 ]; assert "item-set enumerates >=1 committed record ($COUNT)" $?
  # Untracked room-copy ROUNDS files must NOT appear (the ID-640/git-ls-files point).
  UNTRACKED_IN_SET="$(cd "$KIT_DIR" && eval "$ITEMSET" | grep -cE '/(kit|kit-extract|fixture-repo)/' || true)"
  [ "${UNTRACKED_IN_SET:-0}" -eq 0 ]; assert "item-set excludes room-copy ROUNDS paths" $?
fi

# 2. Verdict-vs-evidence rule: a table cell that contradicts its checker-output
#    must be caught. Build a minimal record fixture and apply the documented rule.
REC="$(_mk)"
mkdir -p "$REC/round-1"
printf '| 1 | GREEN | GREEN | 0 |\n' > "$REC/ROUNDS.md"
printf 'SUBMISSION: GREEN\n' > "$REC/round-1/checker-output.txt"
_verdict() { # table_cell vs evidence -> prints OK|FLAG
  local tbl ev
  tbl="$(grep -oE '\| (GREEN|RED) \|' "$1/ROUNDS.md" | head -1 | tr -d '| ')"
  ev="$(grep -o 'SUBMISSION: [A-Z]*' "$1/round-1/checker-output.txt" | awk '{print $2}')"
  [ "$tbl" = "$ev" ] && echo OK || echo FLAG
}
[ "$(_verdict "$REC")" = "OK" ]; assert "matching verdict+evidence -> OK" $?
# Plant the contradiction (GREEN table cell, evidence stays GREEN -> flip cell).
sed -i.bak 's/| GREEN |/| RED |/' "$REC/ROUNDS.md" && rm -f "$REC/ROUNDS.md.bak"
[ "$(_verdict "$REC")" = "FLAG" ]; assert "contradicting verdict+evidence -> FLAG" $?

# 3. Scrub axis: a resolved credential VALUE is a leak; a bare op:// is not.
LEAK="$(_mk)"; printf 'ANTHROPIC_API_KEY=sk-ant-abcdef0123456789ABCDEF\n' > "$LEAK/transcript.jsonl"
grep -qE 'sk-ant-[A-Za-z0-9]|ANTHROPIC_API_KEY=[A-Za-z0-9+/]{20}' "$LEAK/transcript.jsonl"; assert "credential VALUE is detected as a leak" $?
PTR="$(_mk)"; printf 'key from op://Toolkit/anthropic-api-key/credential\n' > "$PTR/transcript.jsonl"
! grep -qE 'sk-ant-[A-Za-z0-9]|ANTHROPIC_API_KEY=[A-Za-z0-9+/]{20}' "$PTR/transcript.jsonl"; assert "bare op:// pointer is NOT a leak" $?
grep -qi 'op://.*pointer is allowed\|op://.*NOT a leak\|pointer, allowed' "$SKILL"; assert "SKILL states op:// pointer is allowed" $?

# 4. Contract pins the audit-loop stance + delegates marker grammar to stats.sh.
grep -qiE 'REMOVE is (never used|disallowed)' "$SKILL"; assert "SKILL disallows REMOVE" $?
grep -q 'lib/gauntlet/stats.sh' "$SKILL"; assert "SKILL delegates marker grammar to stats.sh" $?

# 5. Corpus-out: bulk transcripts live in a release asset described by CORPUS.md. stats.sh
#    must say so when none are unpacked, and stay quiet when one is.
CORPUS="$KIT_DIR/docs/verification/gauntlet/CORPUS.md"
[ -f "$CORPUS" ]; assert "CORPUS.md exists" $?
grep -qE 'Asset sha256 \| `[0-9a-f]{64}`' "$CORPUS"; assert "CORPUS.md carries the asset sha256" $?
grep -q 'gh release download' "$CORPUS" && grep -q 'tar -xzf' "$CORPUS"; assert "CORPUS.md carries fetch and unpack steps" $?
TRACKED_MOVED=0
while IFS= read -r p; do
  git -C "$KIT_DIR" ls-files --error-unmatch "docs/verification/gauntlet/$p" >/dev/null 2>&1 && TRACKED_MOVED=$((TRACKED_MOVED+1))
done < <(sed -nE 's/^\| `([^`]+)` \| `[0-9a-f]{64}` \| [0-9]+ \|$/\1/p' "$CORPUS")
[ "$TRACKED_MOVED" -eq 0 ]; assert "no file listed in CORPUS.md is tracked in git ($TRACKED_MOVED)" $?
SR="$(_mk)"; mkdir -p "$SR/docs/verification/gauntlet/2026-09-01-corpus-x/round-1"
printf '| Probe | claude |\n[[QL-VERDICT round=1 clean=true findings=0]]\n' > "$SR/docs/verification/gauntlet/2026-09-01-corpus-x/ROUNDS.md"
SOUT="$(cd "$SR" && bash "$KIT_DIR/lib/gauntlet/stats.sh" 2>&1)"; SRC=$?
[ "$SRC" -eq 0 ] && echo "$SOUT" | grep -q 'corpus not unpacked'; assert "stats.sh reports an unpacked-corpus gap and still renders" $?
printf '{"type":"result"}\n' > "$SR/docs/verification/gauntlet/2026-09-01-corpus-x/round-1/transcript.jsonl"
SOUT="$(cd "$SR" && bash "$KIT_DIR/lib/gauntlet/stats.sh" 2>&1)"
! echo "$SOUT" | grep -q 'corpus not unpacked'; assert "stats.sh is quiet when a transcript is present" $?

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
