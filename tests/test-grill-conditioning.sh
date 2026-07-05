#!/usr/bin/env bash
# test-grill-conditioning.sh -- SPEC-138, mega-goal kit-absorptions sub-goal 04 (ID-247).
#
# Two things are proven here, honestly kept separate:
#
#  A) The ONE real code change: `lib/gate/gate-ledger.sh record()`'s new write-time guard that
#     refuses a `grill`+`skipped` ledger line unless its reason starts with
#     reason=<home-turf|density-low|operator-wave>. This is genuine shell logic, asserted
#     directly (checks 1-7 in SPEC-138's Test plan).
#
#  B) The 3-signal precheck itself (`commands/grill.md` Step 0/0b) is PROSE, not code -- an
#     agent runs `git log`/`rg` itself and applies the fire rule by judgment, the same honest
#     limitation `tests/test-design-record.sh` and `tests/test-references-field.sh` already
#     document for other prompt-text logic in this kit. What this file CAN do, and does, is
#     reproduce the rule's two purely-mechanical legs (S1's git-history check, and the fire
#     rule's arithmetic) as harness-only functions and prove them unambiguous at the exact
#     boundaries the over-test asks for (checks 10-17). These functions are NOT shipped code;
#     they exist only so the boundary claims in SPEC-138 are checkable, not asserted on faith.
#
# Isolation: every gate-ledger.sh call runs under a fresh DWARVES_KIT_LOG_DIR so the real
# machine corpus is never touched by this suite. (The one REAL ledger line SPEC-138 requires
# as proof is captured separately, by hand, against the real log dir -- see the spec's
# Verification section and the PR body, not this file.)
#
# Run: bash tests/test-grill-conditioning.sh   (exit 0 = all checks green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
assert_eq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

LOGD=""
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" "$@"; }
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }

echo "=== grill-conditioning (SPEC-138) ==="
echo "--- Section A: gate-ledger.sh record() reason= enum guard ---"

# Check 1: reason=home-turf accepted, token lands in the ledger line
new_log
gl record fixA grill skipped "reason=home-turf: 0 signals fired" >/dev/null 2>&1
assert "check1: reason=home-turf accepted" $? "(exit $?)"
LINE="$(grep '| GATE | grill | skipped' "$LOGD/runs/fixA.log" 2>/dev/null)"
case "$LINE" in *"reason=home-turf"*) ok=0;; *) ok=1;; esac
assert "check1b: ledger line carries reason=home-turf" "$ok"

# Check 2: reason=density-low accepted
new_log
gl record fixA grill skipped "reason=density-low: only S1 fired" >/dev/null 2>&1
assert "check2: reason=density-low accepted" $?

# Check 3: reason=operator-wave accepted
new_log
gl record fixA grill skipped "reason=operator-wave: operator declined despite 2 signals" >/dev/null 2>&1
assert "check3: reason=operator-wave accepted" $?

# Check 4 (negative control): no reason token at all -> refused, no ledger line written
new_log
gl record fixA grill skipped "no reason token here" >/dev/null 2>&1
rc=$?
assert "check4: bare-text grill skip refused (exit 64)" "$([ "$rc" -eq 64 ] && echo 0 || echo 1)"
LINECOUNT=0; [ -f "$LOGD/runs/fixA.log" ] && LINECOUNT="$(wc -l < "$LOGD/runs/fixA.log")"
assert_eq "check4b: refused skip writes NOTHING to the ledger" "${LINECOUNT//[[:space:]]/}" "0"

# Check 5 (negative control): a garbage token -> refused
new_log
gl record fixA grill skipped "reason=bogus-token: whatever" >/dev/null 2>&1
rc=$?
assert "check5: garbage reason= token refused (exit 64)" "$([ "$rc" -eq 64 ] && echo 0 || echo 1)"

# Check 5b (negative control, security review finding): a LOOK-ALIKE token that merely starts
# with a valid token's letters, but is not the token itself or the token+':' -- must ALSO be
# refused (a prefix-only match would wrongly accept this; the enum must be closed, not a prefix)
new_log
gl record fixA grill skipped "reason=home-turfish-nonsense: not a real token" >/dev/null 2>&1
rc=$?
assert "check5b: look-alike token (prefix, not exact) refused (exit 64)" "$([ "$rc" -eq 64 ] && echo 0 || echo 1)"

# Check 6 (regression): grill+ran needs no reason= token
new_log
gl record fixA grill ran "3 questions, 0 contradictions, banks: spec-feature" >/dev/null 2>&1
assert "check6: grill+ran unaffected by the enum guard" $?

# Check 7 (regression): a non-grill phase's skip is unaffected (free text still allowed)
new_log
gl record fixA spec skipped "matrix fully captured in the spec body, no separate skip reason needed" >/dev/null 2>&1
assert "check7: non-grill phase skip still accepts free text" $?

echo "--- Section B: precheck boundary walkthroughs (harness-only reproduction) ---"
echo "    (S1/S2/S3 are prose in commands/grill.md; these functions exist only to prove the"
echo "    boundary claims below are unambiguous, mirroring test-design-record.sh's honest limit)"

# S1 mirrors commands/grill.md Step 0 EXACTLY: empty `git log --oneline -5 -- <paths>`, or the
# newest commit strictly more than 90 days old.
s1_fired() {
  local repo="$1"; shift
  local log; log="$(git -C "$repo" log --oneline -5 -- "$@" 2>/dev/null)"
  if [ -z "$log" ]; then echo yes; return; fi
  local newest_epoch now_epoch age_days
  newest_epoch="$(git -C "$repo" log -1 --format=%ct -- "$@" 2>/dev/null)"
  now_epoch="$(date +%s)"
  age_days=$(( (now_epoch - newest_epoch) / 86400 ))
  if [ "$age_days" -gt 90 ]; then echo yes; else echo no; fi
}

# The fire rule from commands/grill.md Step 0: >=2 signals fired, OR S3 alone.
fire_rule() {
  local s1="$1" s2="$2" s3="$3" n=0
  [ "$s1" = yes ] && n=$((n+1))
  [ "$s2" = yes ] && n=$((n+1))
  if [ "$n" -ge 2 ] || [ "$s3" = yes ]; then echo fire; return; fi
  if [ "$n" -eq 0 ]; then echo "skip:home-turf"; return; fi
  echo "skip:density-low"
}

# Exact-epoch date helper (test-coverage review HIGH finding, hardened past just the fix
# suggested): a calendar-day construction like `date -v-91d +...T12:00:00` is TWO ways flaky --
# (a) with no `Z`/offset suffix, `git commit` parses GIT_AUTHOR_DATE/GIT_COMMITTER_DATE in the
# LOCAL system timezone regardless of `date -u` generating the string, so the boundary silently
# shifts by the host's UTC offset (reproduced RED under `TZ=UTC`, which is what GitHub Actions
# runners default to); (b) even WITH a correct UTC suffix, pinning the commit to a fixed
# wall-clock hour ("noon") means `age_days = floor((now - commit)/86400)` depends on the
# CURRENT time-of-day relative to that fixed hour, so the exact N-day boundary can round down
# to N-1 depending on when the suite happens to run. Fixed by computing the timestamp as an
# EXACT epoch offset (`now_epoch - n*86400`) instead of a calendar day: the resulting age is
# always exactly `n` days (mod the sub-second gap between capturing `now_epoch` here and
# `s1_fired`'s own `date +%s` call later, which is never large enough to cross a day boundary).
# `date -r <epoch>` (BSD) / `date -d @<epoch>` (GNU) both format an epoch as UTC under `-u`.
epoch_days_ago_iso() {
  local n="$1" target
  target=$(( $(date +%s) - n * 86400 ))
  date -u -r "$target" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$target" +%Y-%m-%dT%H:%M:%SZ
}

mk_repo() {
  local d; d="$(_mk)"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "Test"
  printf '%s' "$d"
}

commit_dated() {
  local repo="$1" file="$2" days="$3" date_iso
  date_iso="$(epoch_days_ago_iso "$days")"
  printf 'x\n' >> "$repo/$file"
  git -C "$repo" add "$file"
  GIT_AUTHOR_DATE="$date_iso" GIT_COMMITTER_DATE="$date_iso" git -C "$repo" commit -q -m "touch $file"
}

# --- Fixture 1: home-turf (0 signals) -> AUTO-SKIP reason=home-turf ---
R1="$(mk_repo)"
commit_dated "$R1" target.txt 2   # 2 days ago: fresh -> S1 no
echo "the existing widget already covers this domain" > "$R1/CONTEXT.md"
S1="$(s1_fired "$R1" target.txt)"
S2=no  # given: task nouns ("widget") already present in CONTEXT.md
S3=no  # given: operator states no novelty
DECISION="$(fire_rule "$S1" "$S2" "$S3")"
assert_eq "fixture1 (home-turf): S1=no" "$S1" "no"
assert_eq "fixture1 (home-turf): decision" "$DECISION" "skip:home-turf"
new_log
gl record fix1 grill skipped "reason=home-turf: recent commit + known domain nouns, 0 signals" >/dev/null 2>&1
assert "fixture1: ledger accepts the resulting reason=home-turf skip" $?

# --- Fixture 2: declared-novelty (S3 alone) -> fires ---
R2="$(mk_repo)"
commit_dated "$R2" target.txt 2   # fresh, familiar territory otherwise
S1_2="$(s1_fired "$R2" target.txt)"
S2_2=no
S3_2=yes   # given: operator says "I'm new to this"
DECISION2="$(fire_rule "$S1_2" "$S2_2" "$S3_2")"
assert_eq "fixture2 (declared-novelty): S3 alone fires" "$DECISION2" "fire"

# --- Fixture 3: S2 domain-novelty + a 2nd signal -> fires, blindspot pass required ---
R3="$(mk_repo)"
# no commit at all touching this path -> S1 fires (empty git log)
S1_3="$(s1_fired "$R3" brand-new-module.txt)"
S2_3=yes   # given: task nouns absent from repo + specs/ADRs
S3_3=no
DECISION3="$(fire_rule "$S1_3" "$S2_3" "$S3_3")"
BLINDSPOT_REQUIRED="$([ "$S2_3" = yes ] && echo yes || echo no)"
assert_eq "fixture3 (S2 domain-novelty): S1 also fires (no history)" "$S1_3" "yes"
assert_eq "fixture3: exactly-2-signals fires" "$DECISION3" "fire"
assert_eq "fixture3: blindspot pass required (S2 fired)" "$BLINDSPOT_REQUIRED" "yes"

echo "--- Section C: threshold edges ---"

# S3-only edge (same shape as fixture 2, restated as its own edge per the over-test table)
assert_eq "edge: S3-only fires with 0 other signals" "$(fire_rule no no yes)" "fire"

# exactly-2-signals edge (S1+S2, no S3), distinct combination from fixture 3
assert_eq "edge: exactly 2 signals (S1+S2) fires" "$(fire_rule yes yes no)" "fire"

# 1-signal auto-skip -> density-low
assert_eq "edge: exactly 1 signal (S1 only) -> density-low" "$(fire_rule yes no no)" "skip:density-low"
assert_eq "edge: exactly 1 signal (S2 only) -> density-low" "$(fire_rule no yes no)" "skip:density-low"

# S1's 90-day boundary: 89 days ago is fresh (no fire), 91 days ago is stale (fires)
R4="$(mk_repo)"
commit_dated "$R4" old.txt 89
assert_eq "edge: commit 89 days ago -> S1 does NOT fire (fresh)" "$(s1_fired "$R4" old.txt)" "no"

R5="$(mk_repo)"
commit_dated "$R5" old.txt 91
assert_eq "edge: commit 91 days ago -> S1 DOES fire (stale)" "$(s1_fired "$R5" old.txt)" "yes"

echo
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
