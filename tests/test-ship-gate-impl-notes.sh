#!/usr/bin/env bash
# test-ship-gate-impl-notes.sh -- the ship-gate's full-lane implementation-notes rule.
# A full-lane push in an adopted repo needs docs/implementation-notes/<slug>.md or
# <spec-basename>.md committed in HEAD, with at least one non-title line. Drives
# hooks/ship-gate.sh with crafted stdin (same harness as test-ship-gate-coverage-map.sh).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"   # quality gates are opt-in; exercise them ON
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

LOGDIR="$(mktemp -d)"   # isolate the gate-ledger store from the real one
LEDGER="$KIT/lib/gate/gate-ledger.sh"

mkrepo() { # $1=dir $2=slug $3=lane [$4=nomarker] -> repo on feat/<slug> with a spec committed
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  mkdir -p "$1/docs/specs" "$1/docs/implementation-notes"
  if [ "${4:-}" != nomarker ]; then mkdir -p "$1/docs/verification"; echo marker > "$1/docs/verification/README.md"; fi
  : > "$1/.keep"; git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" switch -qc "feat/$2"
  printf '# Spec: x\nStatus: DRAFT\nLane: %s\n' "$3" > "$1/docs/specs/SPEC-001-$2.md"
  git -C "$1" add -A; git -C "$1" commit -qm spec
}
notes() { # $1=repo $2=file-basename $3=content -> commit it
  printf '%b' "$3" > "$1/docs/implementation-notes/$2"
  git -C "$1" add -A; git -C "$1" commit -qm notes
}
gates() { # $1=slug $2=lane [$3=phase to leave out]
  while read -r g; do
    [ "$g" = "${3:-}" ] && continue
    DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" record "$1" "$g" ran "test" >/dev/null 2>&1
  done < <(DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" required "$2")
}
gate() { # $1=cwd $2=command $3=stderr-capture -> echoes exit code
  ( cd "$1" && printf '{"tool_input":{"command":"%s"}}' "$2" \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$3"; echo $? )
}
case_push() { # $1=label $2=repo $3=expected-rc $4=grep-pattern-or-empty [$5=cwd] [$6=cmd]
  local e rc; e="$(mktemp)"
  rc="$(gate "${5:-$2}" "${6:-git push -u origin HEAD}" "$e")"
  if [ "$rc" = "$3" ] && { [ -z "$4" ] || grep -q -- "$4" "$e"; }; then ok "$1"
  else no "$1 (want rc=$3 /$4/; got rc=$rc, stderr: $(tr '\n' ' ' < "$e"))"; fi
}

# 1 full lane, every gate recorded, no notes -> blocked, names MISSING-NOTES
R="$(mktemp -d)"; mkrepo "$R" n1 full; gates n1 full
case_push "1 full lane without notes blocks" "$R" 2 'MISSING-NOTES: docs/implementation-notes/n1.md'

# 2 notes with a ## entry -> pass; 2b a table-only note -> pass
R="$(mktemp -d)"; mkrepo "$R" n2 full; gates n2 full
notes "$R" n2.md '# Implementation notes -- n2\n\n## 2026-09-24 a decision\n- Why: x\n'
case_push "2 notes with a ## entry pass" "$R" 0 ''
R="$(mktemp -d)"; mkrepo "$R" n2b full; gates n2b full
notes "$R" n2b.md '# Notes\n\n| Decision | Why |\n|---|---|\n| a | b |\n'
case_push "2b table-only notes pass" "$R" 0 ''

# 3 zero-deviation line only -> pass
R="$(mktemp -d)"; mkrepo "$R" n3 full; gates n3 full
notes "$R" n3.md '# Implementation notes -- n3\n\nNo deviations; matches the spec verbatim\n'
case_push "3 zero-deviation line passes" "$R" 0 ''

# 4 title-only file -> blocked
R="$(mktemp -d)"; mkrepo "$R" n4 full; gates n4 full
notes "$R" n4.md '# Implementation notes -- n4\n\n   \n'
case_push "4 title-only notes block" "$R" 2 'MISSING-NOTES'

# 5 notes in the working tree, not committed -> blocked
R="$(mktemp -d)"; mkrepo "$R" n5 full; gates n5 full
printf '## entry\n' > "$R/docs/implementation-notes/n5.md"
case_push "5 uncommitted notes block" "$R" 2 'MISSING-NOTES'

# 6 normal lane, no notes -> pass
R="$(mktemp -d)"; mkrepo "$R" n6 normal; gates n6 normal
case_push "6 normal lane needs no notes" "$R" 0 ''

# 7 missing review gate AND no notes -> one message, both gaps
R="$(mktemp -d)"; mkrepo "$R" n7 full; gates n7 full review
E7="$(mktemp)"; RC7="$(gate "$R" 'git push -u origin HEAD' "$E7")"
[ "$RC7" = 2 ] && grep -q 'MISSING-GATE: review' "$E7" && grep -q 'MISSING-NOTES' "$E7" \
  && [ "$(grep -c '^BLOCKED' "$E7")" = 1 ] \
  && ok "7 ledger gap and notes gap share one BLOCKED message" \
  || no "7 want one BLOCKED with both gaps; got rc=$RC7: $(tr '\n' ' ' < "$E7")"

# 8 gate-ledger.sh itself is untouched by this rule
if git -C "$KIT" rev-parse --verify -q origin/master >/dev/null; then
  git -C "$KIT" diff --quiet origin/master -- lib/gate/gate-ledger.sh \
    && ok "8 gate-ledger.sh byte-identical to origin/master" || no "8 gate-ledger.sh changed"
else ok "8 skipped: no origin/master ref"; fi

# 10 docs name the rule; execute.md drops the contradicting clauses
grep -q 'implementation-notes' "$KIT/docs/WORKFLOW.md" && grep -q 'MISSING-NOTES\|impl-notes' "$KIT/docs/WORKFLOW.md" \
  && ok "10a WORKFLOW.md names the notes rule" || no "10a WORKFLOW.md lacks the notes rule"
sed -n '/^### Step 10/,/^### /p' "$KIT/commands/wrap.md" | grep -q 'docs/implementation-notes/' \
  && ok "10b wrap.md step 10 names the notes file" || no "10b wrap.md step 10 lacks the notes file"
! grep -q 'header only\|do not let it block your commit' "$KIT/commands/execute.md" \
  && grep -q 'ship-gate' "$KIT/commands/execute.md" \
  && ok "10c execute.md states the ship-gate rule, no header-only clause" || no "10c execute.md still contradicts the rule"

# 11 notes named after the spec file -> pass
R="$(mktemp -d)"; mkrepo "$R" n11 full; gates n11 full
notes "$R" SPEC-001-n11.md '# Notes\n\n## entry\n'
case_push "11 SPEC-NNN-<slug>.md notes pass" "$R" 0 ''

# 12 no notes, logged override -> pass
R="$(mktemp -d)"; mkrepo "$R" n12 full; gates n12 full
DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$LEDGER" override n12 impl-notes "test: notes waived" >/dev/null 2>&1
case_push "12 impl-notes override clears the gap" "$R" 0 ''

# 13 no proof marker -> advisory only
R="$(mktemp -d)"; mkrepo "$R" n13 full nomarker; gates n13 full
case_push "13 unadopted repo gets an advisory, not a block" "$R" 0 '\[advisory\] full-lane spec'

# 14 push via a leading cd from a foreign cwd checks THAT repo
R="$(mktemp -d)"; mkrepo "$R" n14 full; gates n14 full
case_push "14 cd <repo> && git push checks the target repo" "$R" 2 'MISSING-NOTES' "$(mktemp -d)" "cd $R && git push -u origin HEAD"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
