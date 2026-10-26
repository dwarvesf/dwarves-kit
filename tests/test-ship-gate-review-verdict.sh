#!/usr/bin/env bash
# test-ship-gate-review-verdict.sh -- the ship-gate refuses a push while the branch spec's last
# `## Review` verdict is DO NOT SHIP, or differs from the last verdict a review recorded in the run
# ledger (ship_rule_review_verdict in lib/gate/ship-rules.sh).
# No Review section, no verdict, an unreadable spec, no ledger verdict, or [gate] review_verdict = false passes.
# Drives hooks/ship-gate.sh with crafted stdin (same harness as test-ship-gate-impl-notes.sh).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"   # quality gates are opt-in; exercise them ON
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1   # isolate the gate-ledger store and ship-gate.log
LEDGER="$KIT/lib/gate/gate-ledger.sh"

mkrepo() { # $1=dir $2=slug $3=spec-body-after-header -> repo on feat/<slug> with the spec committed
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  mkdir -p "$1/docs/specs"
  : > "$1/.keep"; git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" switch -qc "feat/$2"
  printf '# Spec: x\nStatus: DRAFT\nLane: tiny\n\n- [ ] TASK-1: x\n%b' "$3" > "$1/docs/specs/SPEC-001-$2.md"
  git -C "$1" add -A; git -C "$1" commit -qm spec
  while read -r g; do   # every tiny-lane gate recorded, so only the verdict rule can stop the push
    DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" record "$2" "$g" ran "test" >/dev/null 2>&1
  done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" required tiny)
}
gate() { # $1=cwd $2=command $3=stderr-capture -> echoes exit code
  ( cd "$1" && printf '{"tool_input":{"command":"%s"}}' "$2" \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$3"; echo $? )
}
case_push() { # $1=label $2=slug $3=spec-body $4=expected-rc $5=grep-pattern-or-empty [$6=cmd]
  local R e rc; R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; e="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1
  mkrepo "$R" "$2" "$3"
  rc="$(gate "$R" "${6:-git push -u origin HEAD}" "$e")"
  if [ "$rc" = "$4" ] && { [ -z "$5" ] || grep -q -- "$5" "$e"; }; then ok "$1"
  else no "$1 (want rc=$4 /$5/; got rc=$rc, stderr: $(tr '\n' ' ' < "$e"))"; fi
}

BLOCK='BLOCKED: ship-gate. The .## Review. section of spec'

# the verdict values the review commands write
case_push "DO NOT SHIP blocks and names the spec" v1 '\n## Review\n\n### Verdict: DO NOT SHIP\n' 2 "$BLOCK .v1.*DO NOT SHIP"
case_push "the block message names SPEC-001-v1.md and how to clear it" v1b '\n## Review\n\n### Verdict: DO NOT SHIP\n' 2 'SPEC-001-v1b.md'
case_push "the block message says to re-run /kit:review" v1c '\n## Review\n\n### Verdict: DO NOT SHIP\n' 2 're-run /kit:review'
case_push "SHIP passes" v2 '\n## Review\n\n### Verdict: SHIP\n' 0 ''
case_push "FIX THEN SHIP passes" v3 '\n## Review\n\n### Verdict: FIX THEN SHIP\n' 0 ''
case_push "no Review section passes" v4 '\n## Notes\n\nnothing here\n' 0 ''
case_push "Review section without a verdict passes" v5 '\n## Review\n\nDate: today\n\n### Findings\nnone\n' 0 ''
case_push "gh pr create blocks too" v6 '\n## Review\n\n### Verdict: DO NOT SHIP\n' 2 'DO NOT SHIP' 'gh pr create --fill'

# the last verdict wins when two Review blocks exist
case_push "last wins: DO NOT SHIP then SHIP passes" w1 '\n## Review\n### Verdict: DO NOT SHIP\n\n## Notes\nfixed\n\n## Review\n### Verdict: SHIP\n' 0 ''
case_push "last wins: SHIP then DO NOT SHIP blocks" w2 '\n## Review\n### Verdict: SHIP\n\n## Notes\nregressed\n\n## Review\n### Verdict: DO NOT SHIP\n' 2 'DO NOT SHIP'
case_push "last wins inside one block: FIX THEN SHIP after DO NOT SHIP passes" w3 '\n## Review\n### Verdict: DO NOT SHIP\n\nround 2\n### Verdict: FIX THEN SHIP\n' 0 ''

# format variants the specs carry
case_push "bold verdict line blocks" f1 '\n## Review\n\n**Verdict: DO NOT SHIP.**\n' 2 'DO NOT SHIP'
case_push "bold value blocks" f2 '\n## Review\n\nVerdict: **DO NOT SHIP**\n' 2 'DO NOT SHIP'
case_push "hyphenated value blocks" f3 '\n## Review\n\n### Verdict: DO-NOT-SHIP\n' 2 'DO NOT SHIP'
case_push "the unfilled template line is not a DO NOT SHIP" f4 '\n## Review\n\n### Verdict: SHIP / FIX THEN SHIP / DO NOT SHIP\n' 0 ''
case_push "a non-ship word does not clear an earlier DO NOT SHIP" f5 '\n## Review\n### Verdict: DO NOT SHIP\n\nLens\nVerdict: SECURE\n' 2 'DO NOT SHIP'

# only the Review section counts
case_push "a DO NOT SHIP verdict outside Review is ignored" o1 '\n## Spec validation\n\n### Verdict: DO NOT SHIP\n' 0 ''
case_push "a section named Review disposition is not Review" o2 '\n## Review disposition\n\n### Verdict: DO NOT SHIP\n' 0 ''
case_push "a verdict inside a code fence is ignored" o3 '\n## Review\n\n```\n### Verdict: DO NOT SHIP\n```\n' 0 ''
case_push "DO NOT SHIP mentioned in prose is not a verdict" o4 '\n## Review\n\nA DO NOT SHIP verdict would block.\n### Verdict: SHIP\n' 0 ''

# lines that only look like a verdict
case_push "a tilde-fenced verdict is ignored" o5 '\n## Review\n\n~~~\n### Verdict: DO NOT SHIP\n~~~\n' 0 ''
case_push "a quoted verdict is ignored" o6 '\n## Review\n\n> Verdict: DO NOT SHIP (round 1)\n' 0 ''
case_push "an indented code verdict is ignored" o7 '\n## Review\n\n    Verdict: DO NOT SHIP\n' 0 ''
case_push "prose that merely contains Verdict is ignored" o8 '\n## Review\n\nVerdict reached after a long talk: DO NOT SHIP\n' 0 ''
case_push "a history bullet after the verdict is ignored" o10 '\n## Review\n### Verdict: SHIP\n\n- Verdict: DO NOT SHIP (round 1)\n' 0 ''
case_push "a history bullet does not clear a DO NOT SHIP" o11 '\n## Review\n### Verdict: DO NOT SHIP\n\n- Verdict: SHIP (round 1)\n' 2 'DO NOT SHIP'
case_push "Verdict after fixes: SHIP reads as SHIP" o9 '\n## Review\n### Verdict: DO NOT SHIP\n\nVerdict after fixes: SHIP\n' 0 ''

# a fence indented 1-3 spaces (a list item) is still a fence: CommonMark allows up to 3
case_push "a verdict in a 3-space indented fence is ignored" i1 '\n## Review\n### Verdict: SHIP\n\n- Example:\n\n   ```\n   Verdict: DO NOT SHIP\n   ```\n' 0 ''
case_push "a verdict in a 2-space indented fence is ignored" i2 '\n## Review\n### Verdict: SHIP\n\n- Example:\n\n  ```\n  Verdict: DO NOT SHIP\n  ```\n' 0 ''
case_push "a verdict in a 1-space indented tilde fence is ignored" i3 '\n## Review\n### Verdict: SHIP\n\n ~~~\n Verdict: DO NOT SHIP\n ~~~\n' 0 ''
case_push "a heading inside an indented fence does not end the Review section" i4 '\n## Review\n### Verdict: DO NOT SHIP\n\n- notes:\n\n  ```\n  ## Notes\n  ```\n\n### Verdict: SHIP\n' 0 ''
case_push "a fence marker indented 4 spaces is code, not a fence: the verdict after it still blocks" i5 '\n## Review\n\n    ```\n\n### Verdict: DO NOT SHIP\n' 2 'DO NOT SHIP'
case_push "a real verdict after an indented fence still counts" i6 '\n## Review\n\n  ```\n  Verdict: SHIP\n  ```\n\n### Verdict: DO NOT SHIP\n' 2 'DO NOT SHIP'

# the spec is read as committed at the pushed head, not as edited in the working tree
R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkrepo "$R" c1 '\n## Review\n\n### Verdict: DO NOT SHIP\n'
sed -i.bak 's/DO NOT SHIP/SHIP/' "$R/docs/specs/SPEC-001-c1.md"; command rm -f "$R/docs/specs/SPEC-001-c1.md.bak"
E="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; RC="$(gate "$R" 'git push -u origin HEAD' "$E")"
[ "$RC" = 2 ] && ok "an uncommitted edit to SHIP does not clear a committed DO NOT SHIP" || no "uncommitted edit must not clear a committed DO NOT SHIP (rc=$RC)"
R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkrepo "$R" c2 '\n## Review\n\n### Verdict: SHIP\n'
sed -i.bak 's/Verdict: SHIP/Verdict: DO NOT SHIP/' "$R/docs/specs/SPEC-001-c2.md"; command rm -f "$R/docs/specs/SPEC-001-c2.md.bak"
E="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; RC="$(gate "$R" 'git push -u origin HEAD' "$E")"
[ "$RC" = 0 ] && ok "an uncommitted DO NOT SHIP does not block a committed SHIP" || no "uncommitted DO NOT SHIP must not block a committed SHIP (rc=$RC)"

# an unreadable spec must not crash the hook: nothing to read, nothing to block on
R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkrepo "$R" u1 '\n## Review\n\n### Verdict: DO NOT SHIP\n'
chmod 000 "$R/docs/specs/SPEC-001-u1.md"; E="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
RC="$(gate "$R" 'git push -u origin HEAD' "$E")"; chmod 644 "$R/docs/specs/SPEC-001-u1.md"
if [ "$(id -u)" = 0 ]; then ok "unreadable spec skipped (root reads it anyway)"
elif [ "$RC" = 0 ]; then ok "unreadable spec: the hook neither crashes nor blocks on this rule"
else no "unreadable spec must pass (rc=$RC: $(tr '\n' ' ' < "$E"))"; fi

# the key: [gate] review_verdict = false, committed on the default branch, switches the rule off and logs it.
# The switch is read at the merge base, so a branch cannot turn off the check it is being held to.
R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkrepo "$R" k1 '\n## Review\n\n### Verdict: DO NOT SHIP\n'
git -C "$R" checkout -q master; printf '[gate]\nreview_verdict = false\n' > "$R/.kit.toml"; git -C "$R" add -A; git -C "$R" commit -qm "chore: opt out"
git -C "$R" checkout -q feat/k1; git -C "$R" rebase -q master
E="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
RC="$(gate "$R" 'git push -u origin HEAD' "$E")"
[ "$RC" = 0 ] && ok "key off (on the default branch): DO NOT SHIP passes" || no "key off (on the default branch): DO NOT SHIP passes (rc=$RC: $(tr '\n' ' ' < "$E"))"
grep -q 'OFF-BY-CONFIG | review-verdict | k1' "$LOGDIR/hooks/ship-gate.log" && ok "key off is logged as OFF-BY-CONFIG" || no "key off is logged as OFF-BY-CONFIG"

# an opt-out the branch carries itself, committed or not, counts for nothing
R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkrepo "$R" k2 '\n## Review\n\n### Verdict: DO NOT SHIP\n'
printf '[gate]\nreview_verdict = false\n' > "$R/.kit.toml"; E="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
RC="$(gate "$R" 'git push -u origin HEAD' "$E")"
[ "$RC" = 2 ] && ok "key off but uncommitted: still blocks" || no "key off but uncommitted: still blocks (rc=$RC)"
git -C "$R" add -A; git -C "$R" commit -qm "chore: opt out on the branch"
RC="$(gate "$R" 'git push -u origin HEAD' "$E")"
[ "$RC" = 2 ] && ok "key off committed only on the branch: still blocks" || no "key off committed only on the branch: still blocks (rc=$RC)"

# the ledger cross-check: the last verdict a review recorded in the run ledger must match the spec's.
# case_ledger <label> <slug> <spec-verdict-or-empty> <ledger-record-reasons...> -- the expected rc is set by the caller via WANT
case_ledger() { # $1=label $2=slug $3=spec-body $4=expected-rc $5=grep-pattern-or-empty, then the ledger reasons (one `review ran` each)
  local label="$1" slug="$2" body="$3" want="$4" pat="$5" R e rc r; shift 5
  R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; e="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1
  mkrepo "$R" "$slug" "$body"
  for r in "$@"; do DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" record "$slug" review ran "$r" >/dev/null 2>&1; done
  rc="$(gate "$R" 'git push -u origin HEAD' "$e")"
  if [ "$rc" = "$want" ] && { [ -z "$pat" ] || grep -q -- "$pat" "$e"; }; then ok "$label"
  else no "$label (want rc=$want /$pat/; got rc=$rc, stderr: $(tr '\n' ' ' < "$e"))"; fi
}
MISMATCH='BLOCKED: ship-gate. The spec .*disagree on the review verdict'
case_ledger "ledger DO NOT SHIP, spec edited to SHIP: blocks and names both" l1 '\n## Review\n\n### Verdict: SHIP\n' 2 "$MISMATCH" "DO NOT SHIP findings=3 rejected=0 actor=t"
case_ledger "the mismatch message shows the ledger verdict and says to re-run review" l1b '\n## Review\n\n### Verdict: SHIP\n' 2 'run ledger says: *DO NOT SHIP' "DO NOT SHIP findings=3"
case_ledger "the mismatch message says to re-run review" l1c '\n## Review\n\n### Verdict: SHIP\n' 2 'Re-run /kit:review' "DO NOT SHIP findings=3"
case_ledger "ledger DO NOT SHIP, spec Review section deleted: blocks" l2 '\n## Notes\n\nnothing\n' 2 "$MISMATCH" "DO NOT SHIP findings=3"
case_ledger "ledger FIX THEN SHIP, spec SHIP: blocks" l3 '\n## Review\n\n### Verdict: SHIP\n' 2 "$MISMATCH" "FIX THEN SHIP findings=1"
case_ledger "ledger SHIP, spec FIX THEN SHIP: blocks (any difference)" l4 '\n## Review\n\n### Verdict: FIX THEN SHIP\n' 2 "$MISMATCH" "SHIP findings=0"
case_ledger "ledger SHIP, spec has no Review verdict: passes (nothing softened)" l14 '\n## Notes\n\nnothing\n' 0 '' "SHIP findings=0"
case_ledger "ledger and spec agree on SHIP: passes" l5 '\n## Review\n\n### Verdict: SHIP\n' 0 '' "SHIP findings=0 rejected=0 actor=t"
case_ledger "ledger and spec agree on FIX THEN SHIP: passes" l6 '\n## Review\n\n### Verdict: FIX THEN SHIP\n' 0 '' "FIX THEN SHIP findings=2"
case_ledger "the last ledger record wins: re-review SHIP after DO NOT SHIP passes" l7 '\n## Review\n\n### Verdict: SHIP\n' 0 '' "DO NOT SHIP findings=3" "SHIP findings=0"
case_ledger "a later unparseable ledger record does not hide an earlier verdict" l8 '\n## Review\n\n### Verdict: SHIP\n' 2 "$MISMATCH" "DO NOT SHIP findings=3" "ok"
case_ledger "no ledger verdict (unparseable record only): spec alone decides, SHIP passes" l9 '\n## Review\n\n### Verdict: SHIP\n' 0 '' "ok"
case_ledger "no ledger verdict: spec alone, DO NOT SHIP still blocks" l10 '\n## Review\n\n### Verdict: DO NOT SHIP\n' 2 "$BLOCK .l10.*DO NOT SHIP" "ok"
case_ledger "spec DO NOT SHIP with a matching ledger record keeps the DO NOT SHIP block" l11 '\n## Review\n\n### Verdict: DO NOT SHIP\n' 2 "$BLOCK .l11.*DO NOT SHIP" "DO NOT SHIP findings=1"
case_ledger "battery records count as the review verdict" l12 '\n## Review\n\n### Verdict: SHIP\n' 0 '' "SHIP arms=3 caught=0"
grep -q 'BLOCKED | ship-gate | l1 (review verdict mismatch' "$LOGDIR/hooks/ship-gate.log" && ok "the mismatch block is written to ship-gate.log" || no "the mismatch block is written to ship-gate.log"

# key off (committed on the default branch) also switches the cross-check off
R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkrepo "$R" l13 '\n## Review\n\n### Verdict: SHIP\n'
DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" record l13 review ran "DO NOT SHIP findings=3" >/dev/null 2>&1
git -C "$R" checkout -q master; printf '[gate]\nreview_verdict = false\n' > "$R/.kit.toml"; git -C "$R" add -A; git -C "$R" commit -qm "chore: opt out"
git -C "$R" checkout -q feat/l13; git -C "$R" rebase -q master
E="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; RC="$(gate "$R" 'git push -u origin HEAD' "$E")"
[ "$RC" = 0 ] && ok "key off: the ledger cross-check is off too" || no "key off: the ledger cross-check is off too (rc=$RC: $(tr '\n' ' ' < "$E"))"

# the block is logged like the other rules
grep -q 'BLOCKED | ship-gate | v1 (review verdict DO NOT SHIP)' "$LOGDIR/hooks/ship-gate.log" && ok "the block is written to ship-gate.log" || no "the block is written to ship-gate.log"

# the rule is a kit default: no config names the key and it resolves ON
KIT_CONFIG_OPERATOR=/nonexistent bash "$KIT/lib/gate/gate-policy.sh" enabled review_verdict "$KIT" && ok "review_verdict resolves ON by default" || no "review_verdict resolves ON by default"
bash "$KIT/lib/gate/gate-policy.sh" keys | grep -qx review_verdict && ok "review_verdict is a known gate key" || no "review_verdict is a known gate key"

echo "pass=$PASS fail=$FAIL"; [ "$FAIL" = 0 ]
