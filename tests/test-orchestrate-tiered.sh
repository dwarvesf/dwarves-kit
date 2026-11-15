#!/usr/bin/env bash
# test-orchestrate-tiered.sh -- the wave join of a tiered mega-goal (docs/specs/SPEC-421-tiered-verification.md
# rules 3 and 4): cases C6 to C9 of the spec's test plan, plus the mega-merge --expect-head refusal (C7).
# Offline: a throwaway repo from tests/lib/node-fixture.sh, a gh stub and a merge-hook recorder.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
MM="$KIT/lib/goal/mega-merge.sh"
# shellcheck source=tests/lib/node-fixture.sh
. "$KIT/tests/lib/node-fixture.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export STUB_LOG="$TMP/stub.log" GH_STATE=MERGED PANE_VIEWER=none WAVE_ROLLING=0 WAVE_CAP=2

# converge <dir> <id>...: run _wave_converge in a fresh shell so the env and the sourced functions stay scoped.
converge() {
  local d="$1"; shift
  ( bash -c 'source "$1"; shift; _wave_converge "$@"' _ "$ORCH" "$d/work/mega" "$@" ) >| "$d/out.txt" 2>&1
}
runs() { grep -c '^suite' "$STUB_LOG" 2>/dev/null || true; }
events() { cut -f2,3 "$1/work/mega/.orchestrate/events.log" 2>/dev/null | tr '\t\n' ': ' ; }
hooklines() { grep -c . "$HOOK_LOG" 2>/dev/null || true; }

# mk_case <name> <verify> : repo with SG-01 (a.txt, PR 11) and SG-02 (b.txt, PR 12), the stubs exported;
# the path lands in CASE_DIR (no command substitution: the exports must reach this shell).
mk_case() {
  local d="$TMP/$1"
  nf_init "$d"
  if [ "$2" = off ]; then
    sed 's/^verify = "tiered"/verify = "off"/' "$d/push/.kit.toml" > "$d/kit.off"; cp "$d/kit.off" "$d/push/.kit.toml"
    nf_git "$d/push" commit -q -am "chore: verify off"; git -C "$d/push" push -q origin main 2>/dev/null
    git -C "$d/work" fetch -q origin 2>/dev/null
  fi
  nf_node "$d" feat/node-a a.txt one
  nf_node "$d" feat/node-b b.txt two
  nf_mega "$d" SG-01:feat/node-a:11 SG-02:feat/node-b:12
  nf_heads "$d" 11:feat/node-a 12:feat/node-b
  nf_env "$d"
  : > "$STUB_LOG"
  CASE_DIR="$d"
}

# ---- C6 join-once-merged-tree
mk_case semantic tiered; D=$CASE_DIR
converge "$D" SG-01 SG-02; rc=$?
if [ "$rc" = 1 ] && [ "$(runs)" = 2 ] && [ "$(hooklines)" = 0 ]; then pass "C6: the semantic-conflict pair is red on the merged tree, two suite runs, nothing merged"
else fail "C6: rc=$rc runs=$(runs) hook=$(hooklines) out: $(tr '\n' ' ' < "$D/out.txt")"; fi
if [ "$(sed -n 1p "$STUB_LOG" | grep -c 'cwd=.*/base$')" = 1 ] && [ "$(sed -n 2p "$STUB_LOG" | grep -c 'cwd=.*/merged$')" = 1 ]; then pass "C6: the first run is the base tree, the second the merged tree"
else fail "C6: run order: $(cat "$STUB_LOG")"; fi
grep -q 'new failure: a and b conflict' "$D/out.txt" && pass "C6: the new failure is named" || fail "C6: no named failure: $(cat "$D/out.txt")"
[ "$(events "$D")" = "wave:blocked " ] && pass "C6: one blocked event for the wave, no merged event" || fail "C6: events '$(events "$D")'"

mk_case green tiered; D=$CASE_DIR
nf_node "$D" feat/node-c c.txt three; nf_node "$D" feat/node-d d.txt four
nf_mega "$D" SG-01:feat/node-c:11 SG-02:feat/node-d:12; nf_heads "$D" 11:feat/node-c 12:feat/node-d
converge "$D" SG-01 SG-02; rc=$?
h1=$(cat "$D/heads/11"); h2=$(cat "$D/heads/12")
if [ "$rc" = 0 ] && [ "$(runs)" = 2 ] && grep -qx "11 node-c full --expect-head $h1" "$HOOK_LOG" && grep -qx "12 node-d full --expect-head $h2" "$HOOK_LOG"; then pass "C6: a clean wave runs the suite twice and merges each pinned head"
else fail "C6 green: rc=$rc runs=$(runs) hook: $(cat "$HOOK_LOG")"; fi
[ "$(events "$D")" = "SG-01:merged SG-02:merged " ] && pass "C6: both sub-goals recorded merged" || fail "C6 green events '$(events "$D")'"

mk_case baseline tiered; D=$CASE_DIR
nf_node "$D" feat/node-c c.txt three; nf_node "$D" feat/node-d d.txt four
nf_mega "$D" SG-01:feat/node-c:11 SG-02:feat/node-d:12; nf_heads "$D" 11:feat/node-c 12:feat/node-d
STUB_FAIL="Skim settings panel wrong" converge "$D" SG-01 SG-02; rc=$?
[ "$rc" = 0 ] && [ "$(hooklines)" = 2 ] && pass "C6: a failure the base run also has does not stop the wave" || fail "C6 baseline: rc=$rc hook=$(hooklines) out: $(tr '\n' ' ' < "$D/out.txt")"
: > "$STUB_LOG"; : > "$HOOK_LOG"
STUB_CRASH=1 converge "$D" SG-01 SG-02; rc=$?
[ "$rc" = 0 ] && [ "$(hooklines)" = 0 ] && fail "C6 crash control: a crash merged" || pass "C6: a crash on both trees is not read as a known baseline (nothing merged)"

# ---- C7 join-head-moved-refused
mk_case moved tiered; D=$CASE_DIR
nf_node "$D" feat/node-c c.txt three; nf_node "$D" feat/node-d d.txt four; nf_node "$D" feat/node-d2 d2.txt four-again
nf_mega "$D" SG-01:feat/node-c:11 SG-02:feat/node-d:12; nf_heads "$D" 11:feat/node-c 12:feat/node-d
git -C "$D/work" rev-parse feat/node-d2 > "$D/heads/12.new"
cat > "$D/hook" <<EOF
#!/usr/bin/env bash
# the PR head moves right after the join: the first call for PR 12 moves it, then refuses like mega-merge does
echo "\$*" >> "\$HOOK_LOG"
pr="\$1"; exp=""
while [ \$# -gt 0 ]; do [ "\$1" = "--expect-head" ] && exp="\$2"; shift; done
if [ "\$pr" = 12 ] && [ ! -f "$D/moved" ]; then touch "$D/moved"; cp "$D/heads/12.new" "\$NF_HEADS/12"; fi
[ -n "\$exp" ] && [ "\$(cat "\$NF_HEADS/\$pr")" != "\$exp" ] && exit 75
exit 0
EOF
old12=$(cat "$D/heads/12")
converge "$D" SG-01 SG-02; rc=$?
new12=$(cat "$D/heads/12")
if [ "$rc" = 0 ] && [ "$(runs)" = 4 ] && grep -qx "12 node-d full --expect-head $old12" "$HOOK_LOG" && grep -qx "12 node-d full --expect-head $new12" "$HOOK_LOG" && [ "$old12" != "$new12" ]; then
  pass "C7: a head that moved after the join is refused, the join reruns (4 suite runs) and only the rejoined head merges"
else fail "C7 moved: rc=$rc runs=$(runs) hook: $(cat "$HOOK_LOG") out: $(tr '\n' ' ' < "$D/out.txt")"; fi
[ "$(events "$D")" = "SG-01:merged SG-02:blocked SG-02:merged " ] && pass "C7: SG-02 is blocked once, then merged on the rejoined head" || fail "C7 events '$(events "$D")'"

mk_case movingtarget tiered; D=$CASE_DIR
nf_node "$D" feat/node-c c.txt three; nf_node "$D" feat/node-d d.txt four; nf_node "$D" feat/node-d2 d2.txt four-again
nf_mega "$D" SG-01:feat/node-c:11 SG-02:feat/node-d:12; nf_heads "$D" 11:feat/node-c 12:feat/node-d
cp "$D/heads/12" "$D/heads/12.a"; git -C "$D/work" rev-parse feat/node-d2 > "$D/heads/12.b"
cat > "$D/hook" <<EOF
#!/usr/bin/env bash
# the head moves on every call: no rejoin can ever land it
echo "\$*" >> "\$HOOK_LOG"
pr="\$1"; exp=""
while [ \$# -gt 0 ]; do [ "\$1" = "--expect-head" ] && exp="\$2"; shift; done
if [ "\$pr" = 12 ]; then if [ "\$(cat "\$NF_HEADS/12")" = "\$(cat "$D/heads/12.a")" ]; then cp "$D/heads/12.b" "\$NF_HEADS/12"; else cp "$D/heads/12.a" "\$NF_HEADS/12"; fi; fi
[ -n "\$exp" ] && [ "\$(cat "\$NF_HEADS/\$pr")" != "\$exp" ] && exit 75
exit 0
EOF
converge "$D" SG-01 SG-02; rc=$?
if [ "$rc" = 1 ] && [ "$(runs)" = 4 ] && ! grep -q 'SG-02:merged' <<<"$(events "$D")"; then pass "C7: a head that keeps moving stops the wave after one rerun, SG-02 never merged"
else fail "C7 moving: rc=$rc runs=$(runs) events '$(events "$D")'"; fi

# mega-merge itself: --expect-head refuses a moved head before anything else, and never reaches gh
mkdir -p "$TMP/mm-bin"
printf '#!/usr/bin/env bash\ntouch "%s/gh-called"\nexit 1\n' "$TMP" > "$TMP/mm-bin/gh"; chmod +x "$TMP/mm-bin/gh"
A=$(printf 'a%.0s' $(seq 40)); B=$(printf 'b%.0s' $(seq 40))
printf '#!/usr/bin/env bash\necho %s\n' "$B" > "$TMP/head-cmd"; chmod +x "$TMP/head-cmd"
out=$(PATH="$TMP/mm-bin:$PATH" MEGA_MERGE_PR_HEAD_CMD="$TMP/head-cmd" MEGA_MERGE_GATE_LEDGER=/bin/true bash "$MM" merge 7 somerid full --execute --expect-head "$A" 2>&1); rc=$?
if [ "$rc" = 75 ] && printf '%s' "$out" | grep -q 'head moved since the wave join' && [ ! -f "$TMP/gh-called" ]; then pass "C7: mega-merge merge --expect-head refuses a moved head (exit 75) without calling gh"
else fail "C7 mega-merge: rc=$rc gh-called=$([ -f "$TMP/gh-called" ] && echo yes || echo no) out: $out"; fi
out=$(PATH="$TMP/mm-bin:$PATH" MEGA_MERGE_PR_HEAD_CMD="$TMP/head-cmd" MEGA_MERGE_GATE_LEDGER=/bin/true bash "$MM" merge 7 somerid full --expect-head="$B" 2>&1) || :
printf '%s' "$out" | grep -q 'head moved since the wave join' && fail "C7: a matching --expect-head was refused" || pass "C7: a matching --expect-head is not refused by the pin"

rm -f "$TMP/gh-called"
for bad in "" "zz" "${A:0:12}"; do
  out=$(PATH="$TMP/mm-bin:$PATH" MEGA_MERGE_PR_HEAD_CMD="$TMP/head-cmd" MEGA_MERGE_GATE_LEDGER=/bin/true bash "$MM" merge 7 somerid full --execute --expect-head "$bad" 2>&1); rc=$?
  [ "$rc" = 64 ] && [ ! -f "$TMP/gh-called" ] && pass "C7: --expect-head '$bad' is refused, never read as no expectation" || fail "C7 bad expect '$bad': rc=$rc out: $out"
done
out=$(PATH="$TMP/mm-bin:$PATH" MEGA_MERGE_PR_HEAD_CMD="$TMP/head-cmd" MEGA_MERGE_GATE_LEDGER=/bin/true bash "$MM" merge 7 somerid full --execute --expect-head 2>&1); rc=$?
[ "$rc" = 64 ] && pass "C7: a trailing --expect-head with no value is refused" || fail "C7 trailing flag: rc=$rc out: $out"

# ---- C8 rolling-refused
mk_case rolling tiered; D=$CASE_DIR
printf '#!/usr/bin/env bash\necho dispatched >> "%s/claude.log"\nexit 0\n' "$TMP" > "$TMP/claude-stub"; chmod +x "$TMP/claude-stub"
WAVE_ROLLING=1 CLAUDE_CMD="$TMP/claude-stub" bash "$ORCH" run "$D/work/mega" >| "$D/roll.txt" 2>&1; rc=$?
if [ "$rc" != 0 ] && grep -q 'does not support rolling waves' "$D/roll.txt" && [ ! -f "$TMP/claude.log" ]; then pass "C8: verify = tiered with WAVE_ROLLING=1 exits non-zero before any dispatch"
else fail "C8: rc=$rc dispatched=$([ -f "$TMP/claude.log" ] && echo yes || echo no) out: $(cat "$D/roll.txt")"; fi
mk_case rollingoff off; D=$CASE_DIR
WAVE_ROLLING=1 bash "$ORCH" run "$D/work/mega" --dry-run >| "$D/roll.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && ! grep -q 'does not support rolling' "$D/roll.txt" && pass "C8: verify = off with WAVE_ROLLING=1 is not refused" || fail "C8 off: rc=$rc out: $(cat "$D/roll.txt")"

# ---- C9 tiered-off-golden
bash "$KIT/tests/lib/orchestrate-golden.sh" >| "$TMP/golden.out" 2>&1
if command diff "$TMP/golden.out" "$KIT/tests/fixtures/orchestrate-golden/off.txt" >| "$TMP/golden.diff"; then pass "C9: with verify = off the orchestrator output equals the committed golden"
else fail "C9: output differs from the golden"; head -20 "$TMP/golden.diff"; fi
mk_case off off; D=$CASE_DIR
: > "$STUB_LOG"
converge "$D" SG-01 SG-02; rc=$?
if [ "$rc" = 0 ] && [ ! -s "$STUB_LOG" ] && ! grep -q 'expect-head' "$HOOK_LOG" && [ "$(hooklines)" = 2 ]; then pass "C9: with verify = off the converge runs no suite and passes no --expect-head"
else fail "C9 off converge: rc=$rc runs=$(runs) hook: $(cat "$HOOK_LOG")"; fi

echo "---"; [ "$fails" = 0 ] && echo "All tiered orchestrate tests passed." || echo "$fails failed."
exit "$fails"
