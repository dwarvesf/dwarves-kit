#!/usr/bin/env bash
# test-whole-spec-dispatch.sh -- whole-spec dispatch for /kit:execute (AC-1 to AC-7, AC-10 fixture).
#
# Structural checks on commands/execute.md, the trial fixture check, and a negative control:
# the same checks run against the pre-change execute.md (base commit c5981b0f) must go red.
#
# Run: bash tests/test-whole-spec-dispatch.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXDIR="$KIT_DIR/tests/fixtures/whole-spec-dispatch"
BASE_SHA="c5981b0f"
PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

# structural <execute.md path>: prints one "<label>|<rc>" line per check (AC-1..AC-7).
structural() {
  local ex="$1" rc
  has() { grep -qF -- "$1" "$ex"; }
  hasi() { grep -qiE -- "$1" "$ex"; }
  rc=0; [ "$(wc -c < "$ex")" -le 30000 ] || rc=1; echo "T1 execute.md at most 30000 bytes|$rc"
  rc=0; has 'Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.' \
    && has '**Routes**' && has '**Territory**' && has 'confirmed-by:' \
    && hasi 'workers dispatch at .?sonnet.? by default' || rc=1; echo "T2 brief labels, grant, confirmed-by, sonnet tier|$rc"
  rc=0; has 'unresolved-decision' && has 'territory-conflict' && has 'fork-risk' && has 'PROGRESS: done=' \
    && has 'split: <reason>' && has 'more than 6 tasks' && has 'git log <base>..HEAD' && has 'At most 2 continuations' || rc=1; echo "T3 split closed list, threshold, PROGRESS|$rc"
  rc=0; ! grep -qE 'Mode C|2b-0|kit:meta-agent|bite-sized' "$ex" && has 'role-classify.sh agent-for' || rc=1
  echo "T4 no persona dispatch, agent-for kept|$rc"
  rc=0; has 'kit:task-verifier' && hasi 'every task' && has 'kit:acceptance-verifier' && has 'kit:integration-verifier' \
    && has 'check-edited:' && has 'check-edit.sh' && has 'LANE-SUGGEST' && has 'Verify at each slice boundary' && hasi 'NEGATIVE CONTROL' && has 'rid=<rid>' && has '(lead-run)' || rc=1
  echo "T5 one end pass, acceptance, integration, check-edit, negative control, rid|$rc"
  rc=0; has 'kit_config_get_root execute.recheck_sample 5' && has 'recheck-sample.sh decide' && has 'unverifiable' && has 'recheck: sampled key=' && has '(self-attested)' \
    && has 'Re-audit: SKIPPED (sampled out' || rc=1; echo "T6 sampled recheck wording|$rc"
  rc=0; has 'Result: PARTIAL' && hasi 'scope creep' && has 'file:line' || rc=1; echo "T7 PARTIAL wording|$rc"
}

echo "=== whole-spec dispatch: structural checks on commands/execute.md ==="
while IFS='|' read -r label rc; do assert "$label" "$rc"; done < <(structural "$KIT_DIR/commands/execute.md")

if git -C "$KIT_DIR" cat-file -e "$BASE_SHA:commands/execute.md" 2>/dev/null; then
  BASE_MD="$(mktemp)"
  git -C "$KIT_DIR" show "$BASE_SHA:commands/execute.md" >| "$BASE_MD"
  assert "base execute.md at $BASE_SHA is 36055 bytes" "$([ "$(wc -c < "$BASE_MD")" -eq 36055 ] && echo 0 || echo 1)"
  echo ""
  echo "=== negative control: the same checks on the base execute.md must go red ==="
  RED_COUNT=$(structural "$BASE_MD" | grep -c '|1$')
  assert "base execute.md fails at least 5 of the 7 structural checks (got $RED_COUNT)" "$([ "$RED_COUNT" -ge 5 ] && echo 0 || echo 1)"
  mv -f "$BASE_MD" "${BASE_MD}.done"
else
  echo "  SKIP base commit $BASE_SHA not in this clone (shallow); size and negative-control checks need it"
fi

echo ""
echo "=== fixture: the unmeetable spec is unmeetable, the meetable spec is meetable ==="
CHK="$FIXDIR/check.sh"
T="$(mktemp -d)"
mkdir -p "$T/tests/fixtures/whole-spec-dispatch"
cp "$CHK" "$T/tests/fixtures/whole-spec-dispatch/check.sh"
printf 'hello' >| "$T/hello.txt"
OUT="$(cd "$T" && bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable 2>&1)"; RC=$?
assert "check.sh unmeetable exits non-zero on a tree holding hello.txt" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
assert "check.sh unmeetable prints AC-3: FAIL" "$(printf '%s' "$OUT" | grep -qF 'AC-3: FAIL' && echo 0 || echo 1)"
(cd "$T" && bash tests/fixtures/whole-spec-dispatch/check.sh meetable >/dev/null 2>&1); RC=$?
assert "check.sh meetable exits 0 on a tree holding hello.txt" "$RC"
printf 'nope' >| "$T/hello.txt"
(cd "$T" && bash tests/fixtures/whole-spec-dispatch/check.sh meetable >/dev/null 2>&1); RC=$?
assert "check.sh meetable exits non-zero when hello.txt is wrong (not an always-pass check)" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
mv -f "$T" "${T}.done"
for f in SPEC-900-unmeetable.md SPEC-901-meetable.md; do
  assert "$f is a VALIDATED tiny-lane spec with a Verification section" "$(grep -q '^Status: VALIDATED' "$FIXDIR/$f" && grep -q '^Lane: tiny' "$FIXDIR/$f" && grep -q '^## Verification' "$FIXDIR/$f" && echo 0 || echo 1)"
done
assert "SPEC-900 carries AC-3, SPEC-901 does not" "$(grep -q 'AC-3' "$FIXDIR/SPEC-900-unmeetable.md" && ! grep -q 'AC-3' "$FIXDIR/SPEC-901-meetable.md" && echo 0 || echo 1)"


echo ""
echo "=== behavior: recheck-sample.sh decide ==="
RS="$KIT_DIR/lib/gate/recheck-sample.sh"
WT="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$WT/log"
d() { bash "$RS" decide "$@" 2>/dev/null; }
assert "N=0 never samples" "$([ "$(d rid-a 0)" = skipped ] && [ "$(d rid-b 0)" = skipped ] && echo 0 || echo 1)"
assert "N=1 samples every run" "$([ "$(d rid-a 1)" = sampled ] && [ "$(d rid-b 1)" = sampled ] && echo 0 || echo 1)"
assert "a non-numeric N falls back to 5, not to an error" "$([ "$(d rid-a abc)" = "$(d rid-a 5)" ] && echo 0 || echo 1)"
SEEN_S=""; SEEN_K=""
for c in a b c d e f g h i j k l m n o p; do
  v="$(d "rid-$c" 2)"; [ "$v" = sampled ] && SEEN_S=1; [ "$v" = skipped ] && SEEN_K=1
done
assert "N=2 over 16 rids yields both sampled and skipped" "$([ -n "$SEEN_S" ] && [ -n "$SEEN_K" ] && echo 0 || echo 1)"
assert "the decision is deterministic for one rid" "$([ "$(d rid-fixed 3)" = "$(d rid-fixed 3)" ] && [ "$(d rid-fixed 3)" = "$(d rid-fixed 3)" ] && echo 0 || echo 1)"
SUM="$(printf '%s' rid-fixed | cksum | cut -d' ' -f1)"; WANT=skipped; [ $((SUM % 3)) -eq 0 ] && WANT=sampled
assert "the key is cksum of the rid (printf %s, first field, modulo N)" "$([ "$(d rid-fixed 3)" = "$WANT" ] && echo 0 || echo 1)"
bash "$RS" decide rid-ledger 0 >/dev/null 2>&1
assert "the decision is recorded as 'recheck: skipped key=<rid>' in the ledger" "$(bash "$KIT_DIR/lib/gate/gate-ledger.sh" show rid-ledger 2>/dev/null | grep -qF 'recheck: skipped key=rid-ledger' && echo 0 || echo 1)"
mkdir -p "$WT/root" "$WT/proj" "$WT/noop"
printf '[execute]\nrecheck_sample = 1\n' >| "$WT/root/kit.toml"
printf '[execute]\nrecheck_sample = 0\n' >| "$WT/proj/.kit.toml"
assert "no N arg: the root kit.toml default is read (1 -> sampled)" "$([ "$(KIT_CONFIG_ROOT="$WT/root" KIT_CONFIG_OPERATOR="$WT/noop" d rid-a)" = sampled ] && echo 0 || echo 1)"
assert "no N arg: a project .kit.toml recheck_sample = 0 is ignored (root-only)" "$([ "$(KIT_CONFIG_ROOT="$WT/root" KIT_CONFIG_OPERATOR="$WT/noop" KIT_PROJECT_ROOT="$WT/proj" d rid-a)" = sampled ] && echo 0 || echo 1)"
bash "$RS" decide >/dev/null 2>&1; assert "no rid is a usage error (exit 64)" "$([ $? -eq 64 ] && echo 0 || echo 1)"

echo ""
echo "=== behavior: check-edit.sh ==="
CE="$KIT_DIR/lib/gate/check-edit.sh"
R="$WT/repo"; mkdir -p "$R/tests" "$R/src"
(cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'assert 1\n' >| tests/t.sh && printf 'x\n' >| src/a.sh && printf 'v\n' >| verify.sh \
  && git add -A && git commit -q -m base && git tag base)
ce() { (cd "$R" && bash "$CE" base "$@" 2>&1); }
(cd "$R" && printf 'y\n' >> src/a.sh && git commit -q -am "feat: src only")
assert "a source-only change with no named path gives empty output" "$([ -z "$(ce verify.sh)" ] && echo 0 || echo 1)"
(cd "$R" && printf 'z\n' >> verify.sh && git commit -q -am "edit check")
assert "a named Verification file edit is flagged check-edited" "$(ce verify.sh | grep -qF 'check-edited: verify.sh' && echo 0 || echo 1)"
(cd "$R" && git reset -q --hard HEAD~1 && printf 'assert 2\n' >> tests/t.sh && git commit -q -am "touch test")
assert "a modified test file that exists at base is flagged even when unnamed" "$(ce | grep -qF 'check-edited: tests/t.sh' && echo 0 || echo 1)"
(cd "$R" && git reset -q --hard HEAD~1 && printf 'assert 3\n' >| tests/new.sh && git add -A && git commit -q -m "new test")
assert "a NEW test file is not flagged" "$([ -z "$(ce)" ] && echo 0 || echo 1)"
for w in 'cmd || true' '@pytest.mark.skip' 'it.only(x)' '# assert 1' 'xit(y)'; do
  (cd "$R" && git reset -q --hard HEAD~1 && printf '%s\n' "$w" >> tests/new.sh && git add -A && git commit -q -m "weaken")
  (cd "$R" && git reset -q --hard HEAD~1 && printf 'ok\n' >| tests/new.sh && git add -A && git commit -q -m "new test again")
  (cd "$R" && printf '%s\n' "$w" >> tests/new.sh && git commit -q -am "weaken")
  assert "added '$w' in a test file is flagged check-weakened" "$(ce | grep -qF "check-weakened: tests/new.sh: $w" && echo 0 || echo 1)"
done
(cd "$R" && git reset -q --hard HEAD~1 && printf 'cmd || true\n' >> src/a.sh && git commit -q -am "src true")
assert "'|| true' in a plain source file is not flagged" "$([ -z "$(ce)" ] && echo 0 || echo 1)"
assert "an unknown base ref exits 64" "$(cd "$R" && bash "$CE" nope >/dev/null 2>&1; [ $? -eq 64 ] && echo 0 || echo 1)"
mv -f "$WT" "${WT}.done"
unset DWARVES_KIT_LOG_DIR
echo ""
echo "=== $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
