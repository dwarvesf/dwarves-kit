#!/usr/bin/env bash
# test-known-failures.sh -- lib/gate/known-failures.sh: the lead-committed known-failures list and the
# affected-only node scope of a tiered mega-goal (docs/specs/SPEC-421-tiered-verification.md rules 1 and 2).
# Cases C1 to C5 of the spec's test plan. Offline: a throwaway repo from tests/lib/node-fixture.sh.
# Negative control: lib/gate/negctl.sh with this suite as the test command and `read` mutated to read
# the branch copy instead of the base copy; C2 must go red.
set -uo pipefail
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KF="$KIT/lib/gate/known-failures.sh"
# shellcheck source=tests/lib/node-fixture.sh
. "$KIT/tests/lib/node-fixture.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { if [ "$2" = 0 ]; then pass "$1"; else fail "$1"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export KIT_CONFIG_ROOT="$TMP/cfg-root" KIT_PROJECT_ROOT="$TMP/cfg-proj"
mkdir -p "$KIT_CONFIG_ROOT"; : > "$KIT_CONFIG_ROOT/kit.toml"
export STUB_LOG="$TMP/stub.log"; : > "$STUB_LOG"

D="$TMP/repo"; nf_init "$D"
W="$D/work"; BASE=origin/main
# A goal file committed at the base, and one outside the repo (the lead's own copy).
mkdir -p "$D/push/goals"; printf '# node\n' > "$D/push/goals/node.md"
nf_git "$D/push" add -A; nf_git "$D/push" commit -q -m "chore: goal file"; git -C "$D/push" push -q origin main 2>/dev/null
git -C "$W" fetch -q origin 2>/dev/null

# run_log <name> [env...]: run the stub suite in the push clone, keep its log and exit code.
run_log() {
  local name="$1"; shift
  ( cd "$D/push" && env -u STUB_LOG "$@" bash tests/suite.sh ) >| "$TMP/$name.log" 2>&1; echo $? >| "$TMP/$name.rc"
}
rc_of() { cat "$TMP/$1.rc"; }
cls() { bash "$KF" classify "$TMP/$1.log" "$W" "$BASE" --exit "$(rc_of "$1")" "${@:2}" 2>/dev/null; }

run_log known STUB_FAIL="Skim settings panel wrong" STUB_COUNT=148
run_log newfail STUB_FAIL="Skim settings panel wrong,Brand new break" STUB_COUNT=148
run_log green STUB_COUNT=149
run_log crash STUB_CRASH=1
printf "  FAIL: Skim settings panel wrong\n" > "$TMP/nosummary.log"; echo 1 > "$TMP/nosummary.rc"

# ---- C1 node-runs-affected: the work loop runs only the affected selection; no full-suite knob is left
wired=0
for f in commands/execute.md commands/ship.md commands/verify.md agents/task-verifier.md; do
  grep -qF 'bin/test-affected' "$KIT/$f" || { fail "C1: $f does not name the affected selection (bin/test-affected)"; wired=1; }
done
for f in commands/execute.md commands/ship.md commands/verify.md agents/task-verifier.md agents/recheck-verifier.md lib/gate/known-failures.sh; do
  grep -qE 'test\.suite|known-failures\.sh suite' "$KIT/$f" && { fail "C1: $f still reads a full-suite knob"; wired=1; }
done
[ "$wired" = 0 ] && pass "C1: execute, ship, verify and task-verifier run the affected selection; no test.suite knob is read"
bash "$KF" suite "$W" "$BASE" >/dev/null 2>&1; [ $? = 64 ] && pass "C1: the suite verb is gone (usage exit 64)" || fail "C1: known-failures.sh still answers suite"
git -C "$W" checkout -q chore/run 2>/dev/null

# ---- C2 known-failures-read-at-base: a branch edit of the list does not change classify; the base copy decides
git -C "$W" checkout -q -b feat/edit origin/main 2>/dev/null
printf 'Skim settings panel wrong\nBrand new break\n' > "$W/tests/known-failures.txt"
nf_git "$W" commit -q -am "chore: branch edits the list"
out=$(bash "$KF" read "$W" "$BASE" | tr '\n' '|')
[ "$out" = "Skim settings panel wrong|" ] && pass "C2: read returns the base list, not the branch copy" || fail "C2: read -> '$out'"
out=$(cls newfail)
[ "$out" = fail ] && pass "C2: a failure only the branch lists is a new failure (fail)" || fail "C2: classify newfail -> '$out'"
out=$(cls known)
[ "$out" = known ] && pass "C2: a failure the base lists is known" || fail "C2: classify known -> '$out'"

# ---- C3 known-failures-edit-guarded
bash "$KF" guard "$W" "$BASE" "$TMP/goal-plain.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && pass "C3: a diff touching the list with no declaration fails guard" || fail "C3: guard rc=$rc"
printf '# SG-06\nKnown-failures: edit fixes the settings panel\n' > "$TMP/goal-edit.md"
bash "$KF" guard "$W" "$BASE" "$TMP/goal-edit.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && pass "C3: with 'Known-failures: edit <reason>' declared it passes" || fail "C3: declared guard rc=$rc"
printf '# SG-06\nKnown-failures: edit\n' > "$TMP/goal-noreason.md"
bash "$KF" guard "$W" "$BASE" "$TMP/goal-noreason.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && pass "C3: a declaration with no reason does not count" || fail "C3: reasonless guard rc=$rc"
# the node cannot declare for itself: an in-repo goal file is read as the base has it
printf '# node\nKnown-failures: edit self-declared\n' > "$W/goals/node.md"
nf_git "$W" commit -q -am "chore: node edits its own goal file"
bash "$KF" guard "$W" "$BASE" goals/node.md >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && pass "C3: a declaration added on the node's branch is not read" || fail "C3: self-declared guard rc=$rc"
git -C "$W" checkout -q -b feat/clean origin/main 2>/dev/null
echo x > "$W/x.txt"; nf_git "$W" add -A; nf_git "$W" commit -q -m "feat: unrelated"
bash "$KF" guard "$W" "$BASE" "$TMP/goal-plain.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && pass "C3: a diff that leaves the list alone passes guard" || fail "C3: clean guard rc=$rc"
git -C "$W" checkout -q chore/run 2>/dev/null

# ---- C4 known-failure-no-retry
out=$(cls known)
[ "$out" = known ] && pass "C4: an all-known run with a non-zero count is known (no retry)" || fail "C4: known -> '$out'"
out=$(cls known --prev-count 149)
[ "$out" = known ] && pass "C4: a count equal to the previous run (149) is known" || fail "C4: equal count -> '$out'"
out=$(cls known --prev-count 150)
[ "$out" = fail ] && pass "C4: a dropped count (150 then 149) is fail" || fail "C4: dropped -> '$out'"
out=$(cls nosummary)
[ "$out" = fail ] && pass "C4: a red run with no executed count in the log is fail" || fail "C4: nosummary -> '$out'"
out=$(cls green)
[ "$out" = pass ] && pass "C4: exit 0 is pass" || fail "C4: green -> '$out'"
out=$(bash "$KF" classify "$TMP/green.log" "$W" "$BASE" 2>/dev/null)
[ "$out" = fail ] && pass "C4: with no --exit given, a clean log is not pass" || fail "C4: no --exit -> '$out'"

out=$(cls known --base-count 149)
[ "$out" = known ] && pass "C4: a count equal to the base run's (149) is known" || fail "C4: base-count equal -> '$out'"
out=$(cls known --base-count 150)
[ "$out" = fail ] && pass "C4: a count below the base run's (149 under 150) is fail even though every failure is known" || fail "C4: base-count above -> '$out'"
out=$(cls known --base-count "")
[ "$out" = fail ] && pass "C4: with no usable base count the run is not proven (fail)" || fail "C4: empty base-count -> '$out'"
git -C "$D/push" checkout -q -b base-nocount main 2>/dev/null
grep -v '^count_line' "$D/push/.kit.toml" > "$TMP/nocount.toml"; cp "$TMP/nocount.toml" "$D/push/.kit.toml"; nf_git "$D/push" commit -q -am "chore: no count_line"
git -C "$D/push" push -q origin base-nocount 2>/dev/null; git -C "$W" fetch -q origin 2>/dev/null
out=$(bash "$KF" classify "$TMP/known.log" "$W" origin/base-nocount --exit 1 2>/dev/null)
[ "$out" = fail ] && pass "C4: a suite with no count line is not proven even when its failures are known" || fail "C4: no count_line -> '$out'"

# ---- C5 crash-not-masked
out=$(cls crash)
[ "$out" = fail ] && [ "$(rc_of crash)" = 1 ] && pass "C5: exit 1 with no parsed failure is fail" || fail "C5: crash -> '$out'"
# a base without failure_line: a red run is a plain failure, even when the failure is listed
git -C "$D/push" checkout -q -b base-nocfg main 2>/dev/null
printf '[mega]\nverify = "tiered"\n' > "$D/push/.kit.toml"; nf_git "$D/push" commit -q -am "chore: no test keys"
git -C "$D/push" push -q origin base-nocfg 2>/dev/null; git -C "$W" fetch -q origin 2>/dev/null
out=$(bash "$KF" classify "$TMP/known.log" "$W" origin/base-nocfg --exit 1 2>/dev/null)
[ "$out" = fail ] && pass "C5: without failure_line at the base a red run is a plain failure" || fail "C5: no failure_line -> '$out'"

echo "---"; [ "$fails" = 0 ] && echo "All known-failures tests passed." || echo "$fails failed."
exit "$fails"
