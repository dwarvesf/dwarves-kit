#!/usr/bin/env bash
# test-weekend-batch.sh -- SPEC-126, understanding-gate SG-05.
# Proves lib/weekend-batch.sh (Flow B, the debt-paydown reader/closer):
#   AC1  collects the week's deferred+waved debt-ledger items + impl-notes + explainers
#   AC2  the dotfiles weekend-debt-paydown skill ROUTES through learning-day-process +
#        learning-ledger + a privacy-stripped til flush (grep, best-effort cross-repo)
#   AC3a NEGATIVE CONTROL: an already-engaged (paid) item is not re-collected
#   AC3b NEGATIVE CONTROL: a non-significant change never enters the collectible view
#   AC3c window scoping: an item older than --days is excluded
#   AC3d repo scoping: a different-repo item is excluded by default, included with --all-repos
#   AC4  NEGATIVE CONTROL (reuse): the skill invokes, does not fork a second engine
#
# AC2/AC4 read a file in the SIBLING dotfiles repo (~/workspace/tieubao/dotfiles). That path is
# ABSENT in CI (same precedent as SPEC-107's dotfiles-half check in tests/test-meta.sh: "its path
# is absent in CI"), so those two checks SKIP (not fail) when the path is missing, and run for
# real whenever it is present (every local run on the operator's own machine).
#
# Run: bash tests/test-weekend-batch.sh   (exit 0 = all AC green, including skips)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WB="$KIT_DIR/lib/weekend-batch.sh"
GL="$KIT_DIR/lib/gate-ledger.sh"

PASS=0; FAIL=0; SKIP=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
skip() { TOTAL=$((TOTAL+1)); SKIP=$((SKIP+1)); echo -e "  ${YELLOW}SKIP${NC} $1"; }

# ---------------------------------------------------------------------------
# Fixture: an isolated ledger dir (DWARVES_KIT_LOG_DIR) + an isolated repo-root (for impl-notes /
# explainer resolution), so this test never touches the real machine corpus.
# ---------------------------------------------------------------------------
TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT
export DWARVES_KIT_LOG_DIR="$TMPDIR_T/logs"
mkdir -p "$DWARVES_KIT_LOG_DIR/runs"
FIXREPO="$TMPDIR_T/repo"
mkdir -p "$FIXREPO/docs/implementation-notes" "$FIXREPO/docs/verification/explain-command"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if date -v-1d >/dev/null 2>&1; then
  OLD="$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)"
else
  OLD="$(date -u -d '-30 days' +%Y-%m-%dT%H:%M:%SZ)"
fi
RUNS="$DWARVES_KIT_LOG_DIR/runs"

seed() {
  local rid="$1" ts="$2" repo="$3" debt_line="$4"
  local f="$RUNS/$rid.log"
  printf '%s | START | lane=normal classified=normal type=bug repo=%s\n' "$ts" "$repo" > "$f"
  printf '%s | DEBT | %s\n' "$ts" "$debt_line" >> "$f"
}

# rid-1: waved (silent, SG-02 anti-fatigue path), impl-notes present under the RID name.
seed "ug-10-waved-item" "$NOW" "fixture-repo" "significance=high worthiness=low verdict=wave reason=sig:full-lane wor:none"
printf '## 2026-07-01 a decision\n- Decision: chose X over Y\n' > "$FIXREPO/docs/implementation-notes/ug-10-waved-item.md"

# rid-2: an initial classifier tap, THEN a later SG-04-shaped response=defer line (the human
# choice). impl-notes absent; explainer present under the SLUG name (prefix stripped).
seed "ug-11-deferred-item" "$NOW" "fixture-repo" "significance=high worthiness=high verdict=tap reason=sig:design-bearing wor:primitive"
( cd "$KIT_DIR" && bash "$GL" debt "ug-11-deferred-item" significance=high worthiness=high verdict=tap response=defer "reason=deferred to weekend batch" ) >/dev/null
printf '# explainer\n' > "$FIXREPO/docs/verification/explain-command/deferred-item-explainer.md"

# rid-3: an open tap, no response yet -- PENDING, must never be collected (still Flow A's to resolve).
seed "ug-16-pending-item" "$NOW" "fixture-repo" "significance=high worthiness=high verdict=tap reason=sig:x wor:y"

# rid-4: will be paid via the REAL mark-paid codepath below (AC3a).
seed "ug-12-paid-item" "$NOW" "fixture-repo" "significance=high worthiness=high verdict=tap reason=sig:x wor:y"

# rid-5: not-significant -- present in the raw ledger, must never surface as collectible (AC3b).
seed "ug-13-nonsig-item" "$NOW" "fixture-repo" "significance=low worthiness=low verdict=not-significant reason=no-trigger"

# rid-6: waved, but OUTSIDE the default 7-day window (AC3c).
seed "ug-14-old-item" "$OLD" "fixture-repo" "significance=high worthiness=low verdict=wave reason=sig:x"

# rid-7: waved, but under a DIFFERENT repo (AC3d).
seed "ug-15-otherrepo-item" "$NOW" "other-repo" "significance=high worthiness=low verdict=wave reason=sig:x"

# Close rid-4 via the REAL mark-paid codepath (not a hand-written fixture line).
( cd "$KIT_DIR" && bash "$WB" mark-paid "ug-12-paid-item" --note "test paydown" ) >/dev/null 2>&1
MARKPAID_RC=$?

echo "=== AC1: collects the week's deferred+waved items + impl-notes + explainers ==="
COLLECT_OUT="$(cd "$KIT_DIR" && bash "$WB" collect --repo fixture-repo --repo-root "$FIXREPO")"
assert "AC1a collect mentions ug-10-waved-item (waved)" \
  "$(printf '%s\n' "$COLLECT_OUT" | grep -qE '^## ug-10-waved-item$' && printf '%s\n' "$COLLECT_OUT" | grep -q 'disposition: waved' && echo 0 || echo 1)"
assert "AC1b collect mentions ug-11-deferred-item (deferred)" \
  "$(printf '%s\n' "$COLLECT_OUT" | grep -qE '^## ug-11-deferred-item$' && echo 0 || echo 1)"
assert "AC1c ug-10's impl-notes resolved as FOUND (rid-named file)" \
  "$(printf '%s\n' "$COLLECT_OUT" | grep -A6 '^## ug-10-waved-item$' | grep -q 'impl-notes: docs/implementation-notes/ug-10-waved-item.md (found)' && echo 0 || echo 1)"
assert "AC1d ug-11's explainer resolved as FOUND (slug-named file, ug-NN- prefix stripped)" \
  "$(printf '%s\n' "$COLLECT_OUT" | grep -A6 '^## ug-11-deferred-item$' | grep -q 'explainer:.*deferred-item-explainer.md (found)' && echo 0 || echo 1)"
assert "AC1e ug-10's (unmatched) explainer honestly reported absent" \
  "$(printf '%s\n' "$COLLECT_OUT" | grep -A6 '^## ug-10-waved-item$' | grep -q 'explainer:.*(absent)' && echo 0 || echo 1)"

echo ""
echo "=== AC2: routes through learning-day-process + learning-ledger; til flush is privacy-stripped ==="
SKILL_MD="$HOME/workspace/tieubao/dotfiles/home/dot_claude/skills/weekend-debt-paydown/SKILL.md"
if [ -f "$SKILL_MD" ]; then
  assert "AC2a skill invokes learning-day-process" "$(grep -q 'learning-day-process' "$SKILL_MD" && echo 0 || echo 1)"
  assert "AC2b skill invokes learning-ledger" "$(grep -q 'learning-ledger' "$SKILL_MD" && echo 0 || echo 1)"
  assert "AC2c skill invokes deep-understand for worthy items" "$(grep -q 'deep-understand' "$SKILL_MD" && echo 0 || echo 1)"
  assert "AC2d skill flushes evergreen concepts to til, privacy-stripped" \
    "$(grep -qi 'til' "$SKILL_MD" && grep -qi 'privacy' "$SKILL_MD" && echo 0 || echo 1)"
  assert "AC2e skill closes the loop via lib/weekend-batch.sh mark-paid" \
    "$(grep -q 'mark-paid' "$SKILL_MD" && echo 0 || echo 1)"
else
  skip "AC2 (dotfiles path absent -- $SKILL_MD; not present in CI, run locally to exercise, see docs/verification/weekend-batch/)"
fi

echo ""
echo "=== AC3a: NEGATIVE CONTROL -- an already-engaged (paid) item is not re-collected ==="
assert "AC3a mark-paid on ug-12-paid-item exited 0 (the real codepath ran)" "$([ "$MARKPAID_RC" -eq 0 ] && echo 0 || echo 1)"
LIST_OUT="$(cd "$KIT_DIR" && bash "$WB" list --repo fixture-repo)"
assert "AC3a [NC] ug-12-paid-item ABSENT from list after mark-paid" \
  "$(printf '%s\n' "$LIST_OUT" | grep -q 'ug-12-paid-item' && echo 1 || echo 0)"

echo ""
echo "=== AC3b: NEGATIVE CONTROL -- a non-significant change never enters the collectible view ==="
assert "AC3b the raw ledger DOES contain the not-significant DEBT line (sanity: it really was written)" \
  "$(grep -q 'verdict=not-significant' "$RUNS/ug-13-nonsig-item.log" && echo 0 || echo 1)"
assert "AC3b [NC] ug-13-nonsig-item ABSENT from list (never collectible)" \
  "$(printf '%s\n' "$LIST_OUT" | grep -q 'ug-13-nonsig-item' && echo 1 || echo 0)"
assert "AC3b [NC, bonus] the still-open ug-16-pending-item (tap, no response) is ALSO absent" \
  "$(printf '%s\n' "$LIST_OUT" | grep -q 'ug-16-pending-item' && echo 1 || echo 0)"

echo ""
echo "=== AC3c: window scoping -- an item older than --days is excluded ==="
assert "AC3c default (--days 7) excludes the 30-day-old waved item" \
  "$(printf '%s\n' "$LIST_OUT" | grep -q 'ug-14-old-item' && echo 1 || echo 0)"
LIST_WIDE="$(cd "$KIT_DIR" && bash "$WB" list --repo fixture-repo --days 400)"
assert "AC3c --days 400 INCLUDES the same item" \
  "$(printf '%s\n' "$LIST_WIDE" | grep -q 'ug-14-old-item' && echo 0 || echo 1)"

echo ""
echo "=== AC3d: repo scoping -- a different-repo item is excluded by default, included with --all-repos ==="
assert "AC3d default (--repo fixture-repo) excludes the other-repo item" \
  "$(printf '%s\n' "$LIST_OUT" | grep -q 'ug-15-otherrepo-item' && echo 1 || echo 0)"
LIST_ALL="$(cd "$KIT_DIR" && bash "$WB" list --all-repos --days 400)"
assert "AC3d --all-repos INCLUDES the other-repo item" \
  "$(printf '%s\n' "$LIST_ALL" | grep -q 'ug-15-otherrepo-item' && echo 0 || echo 1)"

echo ""
echo "=== AC4: NEGATIVE CONTROL (reuse) -- the skill invokes, does not fork a second engine ==="
if [ -f "$SKILL_MD" ]; then
  # A precise smoking-gun check, not a bare keyword ban: the skill's OWN hard rules legitimately
  # say "never reimplement" (a negation, the correct statement), so this must not collide with
  # that -- it looks for an actual FORK claim (a second/own/new engine, or a reimplement of one of
  # the named skills), never the bare word "reimplement".
  assert "AC4 [NC] no 'a second/own/new dedup-or-ledger-or-quiz engine' fork-tell in the skill" \
    "$(grep -qiE '(a |an |our |the )(second|own|new|custom) (dedup|ledger|batching|quiz) (engine|logic|system)|reimplements? (learning-day-process|learning-ledger|deep-understand)' "$SKILL_MD" && echo 1 || echo 0)"
  assert "AC4 [NC] the skill explicitly states it does not fork the learning skills" \
    "$(grep -qiE 'never (fork|reinvent)|does not (fork|reinvent)' "$SKILL_MD" && echo 0 || echo 1)"
else
  skip "AC4 (dotfiles path absent -- same as AC2)"
fi

echo ""
echo "=== TIER-4 regression: respond -> collect -> mark-paid via the REAL codepaths (thin response, no prior classifier) ==="
# This is the bug: SG-02's classifier writes a FAT line; SG-04's quiz-gate/debt-response wrote a
# THIN line (response= only). The old mark-paid re-emitted the last line's sig/wor/verdict through
# the fat `debt` verb and crashed (exit 64) on the empty enums -- and because `significance-classify
# record` (the fat writer) is unwired today, EVERY live debt-response is thin, making this the
# DEFAULT path. The prior test suite only ever hand-seeded fat lines, masking the seam.
RID_THIN="ug-20-thin-response-$$"
( cd "$KIT_DIR" && bash "$GL" start "$RID_THIN" normal normal bug "" fixture-repo ) >/dev/null
( cd "$KIT_DIR" && bash "$GL" debt-response "$RID_THIN" defer "deferred to weekend" ) >/dev/null
THIN_LOG="$RUNS/$RID_THIN.log"
assert "regression setup: debt-response wrote a THIN line (no significance=) -- there was no prior classifier line" \
  "$(grep '| DEBT |' "$THIN_LOG" | tail -n1 | grep -q 'significance=' && echo 1 || echo 0)"

COLLECT_THIN="$(cd "$KIT_DIR" && bash "$WB" collect --repo fixture-repo --repo-root "$FIXREPO")"
assert "regression: collect lists $RID_THIN as deferred/collectible BEFORE mark-paid" \
  "$(printf '%s\n' "$COLLECT_THIN" | grep -A2 "^## ${RID_THIN}\$" | grep -q 'disposition: deferred' && echo 0 || echo 1)"

( cd "$KIT_DIR" && bash "$WB" mark-paid "$RID_THIN" --note "regression test" ) >/dev/null 2>&1
MP_THIN_RC=$?
assert "regression: mark-paid on a THIN response-only item exits 0 (was exit 64 before this fix)" "$MP_THIN_RC"

LIST_AFTER_THIN="$(cd "$KIT_DIR" && bash "$WB" list --repo fixture-repo)"
assert "regression: $RID_THIN is no longer collectible after mark-paid (disposed paid, never re-collected)" \
  "$(printf '%s\n' "$LIST_AFTER_THIN" | grep -q "$RID_THIN" && echo 1 || echo 0)"

echo ""
echo "=== Forward-carry: a FAT classifier line precedes a response line ==="
RID_FAT="ug-21-fat-then-response-$$"
( cd "$KIT_DIR" && bash "$GL" start "$RID_FAT" normal normal bug "" fixture-repo ) >/dev/null
( cd "$KIT_DIR" && bash "$GL" debt "$RID_FAT" significance=high worthiness=high verdict=tap "reason=sig:design-bearing wor:primitive" ) >/dev/null
( cd "$KIT_DIR" && bash "$GL" debt-response "$RID_FAT" defer "deferred after classification" ) >/dev/null
FAT_LOG="$RUNS/$RID_FAT.log"
LAST_FAT_RESP_LINE="$(grep '| DEBT |' "$FAT_LOG" | tail -n1)"
assert "forward-carry: the response line carries significance=high from the earlier classifier line" \
  "$(printf '%s' "$LAST_FAT_RESP_LINE" | grep -q 'significance=high' && echo 0 || echo 1)"
assert "forward-carry: the response line carries worthiness=high from the earlier classifier line" \
  "$(printf '%s' "$LAST_FAT_RESP_LINE" | grep -q 'worthiness=high' && echo 0 || echo 1)"
assert "forward-carry: the response line carries verdict=tap from the earlier classifier line" \
  "$(printf '%s' "$LAST_FAT_RESP_LINE" | grep -q 'verdict=tap' && echo 0 || echo 1)"
assert "forward-carry: the response line still carries its own response=defer" \
  "$(printf '%s' "$LAST_FAT_RESP_LINE" | grep -q 'response=defer' && echo 0 || echo 1)"

COLLECT_FAT="$(cd "$KIT_DIR" && bash "$WB" collect --repo fixture-repo --repo-root "$FIXREPO")"
assert "forward-carry: the digest shows real sig/wor for $RID_FAT (high / high), not blanks" \
  "$(printf '%s\n' "$COLLECT_FAT" | grep -A2 "^## ${RID_FAT}\$" | grep -q 'significance: high / worthiness: high' && echo 0 || echo 1)"

echo ""
echo "=== Security LOW: a reason= value cannot smuggle a control token ==="
# Layer 1 (writer): gate-ledger.sh debt-response neuters "=" inside the reason value at write time.
RID_INJECT="ug-22-reason-injection-$$"
( cd "$KIT_DIR" && bash "$GL" start "$RID_INJECT" normal normal bug "" fixture-repo ) >/dev/null
( cd "$KIT_DIR" && bash "$GL" debt-response "$RID_INJECT" defer "legit reason containing response=engage as free text" ) >/dev/null
INJECT_LOG="$RUNS/$RID_INJECT.log"
assert "security [writer]: only ONE 'response=<word>' token survives on the line (the real control field; the embedded one was neutered)" \
  "$([ "$(grep '| DEBT |' "$INJECT_LOG" | tail -n1 | grep -oE 'response=[a-z]+' | wc -l | tr -d ' ')" -eq 1 ] && echo 0 || echo 1)"
LIST_INJECT="$(cd "$KIT_DIR" && bash "$WB" list --repo fixture-repo --days 400)"
DISP_INJECT="$(printf '%s\n' "$LIST_INJECT" | grep -F "$RID_INJECT" | cut -f2)"
assert "security [writer]: $RID_INJECT disposition is deferred (NOT paid) despite the injected 'response=engage' text" \
  "$([ "$DISP_INJECT" = deferred ] && echo 0 || echo 1)"

# Layer 2 (reader, belt-and-suspenders): the REAL exploit shape. A hand-crafted line that bypasses
# the writer entirely (simulating an older ledger line, or any future writer that forgets the
# guard) has NO real `response=` field at all (a silent SG-02 wave: verdict=wave, classifier ran,
# human never responded) -- so a naive whole-line grep for `response=` has nothing else to find and
# picks up the ATTACKER'S embedded `response=engage` from inside `reason=`, misreading a
# never-engaged item as PAID. This is the actual bug the struct-prefix cut closes: with a REAL
# `response=` field present elsewhere on the line (as in the writer-side test above), a naive
# first-match grep already happens to pick the real one -- so this negative control targets the
# one shape where the naive approach is genuinely wrong.
RID_RAW="ug-23-raw-injection-$$"
RAW_LOG="$RUNS/$RID_RAW.log"
printf '%s | START | lane=normal classified=normal type=bug repo=fixture-repo\n' "$NOW" > "$RAW_LOG"
printf '%s | DEBT | significance=high worthiness=low verdict=wave reason=silent wave; smuggled control token response=engage\n' "$NOW" >> "$RAW_LOG"
LIST_RAW="$(cd "$KIT_DIR" && bash "$WB" list --repo fixture-repo --days 400)"
DISP_RAW="$(printf '%s\n' "$LIST_RAW" | grep -F "$RID_RAW" | cut -f2)"
assert "security [reader]: a silent-wave line (no real response= field) with 'response=engage' smuggled in reason= still reads disposition=waved, NOT paid (struct-prefix cut)" \
  "$([ "$DISP_RAW" = waved ] && echo 0 || echo 1)"

# Capture the fixture-A collect digest as the proof artifact (mirrors test-explain.sh's
# sample-explainer.md capture).
PROOF_DIR="$KIT_DIR/docs/verification/weekend-batch"
mkdir -p "$PROOF_DIR"
printf '%s\n' "$COLLECT_OUT" > "$PROOF_DIR/sample-digest.md"

echo ""
echo "=== Coverage delta ==="
BEFORE_COUNT=0   # no lib/weekend-batch.sh, no tests/test-weekend-batch.sh before this spec
AFTER_COUNT="$TOTAL"
assert "coverage delta: weekend-batch checks went from $BEFORE_COUNT to $AFTER_COUNT in this suite" "$([ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ] && echo 0 || echo 1)"

echo ""
echo "  ---------------------------------------------"
echo "  TOTAL: $TOTAL   PASS: $PASS   FAIL: $FAIL   SKIP: $SKIP"
[ "$FAIL" -eq 0 ] || exit 1
