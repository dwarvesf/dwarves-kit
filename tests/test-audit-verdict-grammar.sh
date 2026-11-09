#!/usr/bin/env bash
# test-audit-verdict-grammar.sh -- every audit-loop skill emits only the base five verdicts.
#
# The base set is OK / FIX / REMOVE / UNSURE / DANGER (docs/patterns/audit-loop.md). Skills used
# to carry their own words (DONE, KEEP, MERGE, STALE, FLAG, UNTESTABLE). Those are reasons now,
# written in parentheses after the verdict: `REMOVE (duplicate of ID-12)`.
#
# Also pins three prose fixes that ride with the grammar:
#   backlog-reconcile compares spec CLASSES against board CLASSES, not hardcoded board words;
#   commands/greenlight.md documents no terminal state it never emits;
#   commands/dispatch.md says DISCONNECTED is an attempt-state value, never a worker STATUS.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PATTERN="$KIT_DIR/docs/patterns/audit-loop.md"
BL="$KIT_DIR/lib/board/backlog.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }
check() { if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1"; fi; }

SKILLS="backlog-reconcile memory-tidy gauntlet-proof-audit web-drift repo-hygiene doc-drift ci-drift topology-drift"

# ---- 1. the rule is stated once, in the pattern doc ----
n="$(grep -c 'Every instance emits only these five words' "$PATTERN")"
check "audit-loop.md states the five-word rule exactly once (found $n)" "$([ "$n" = 1 ]; echo $?)"
grep -qF 'goes in the reason' "$PATTERN"
check "audit-loop.md says the old word goes in the reason" $?
! grep -qF 'is UNTESTABLE, never REMOVE' "$PATTERN" && grep -qF '`UNSURE (untestable from here)`, never REMOVE' "$PATTERN"
check "audit-loop.md no longer makes UNTESTABLE a verdict" $?
for s in $SKILLS; do
  c="$(grep -c 'Every instance emits only these five words' "$KIT_DIR/skills/$s/SKILL.md")"
  check "skills/$s does not restate the rule (found $c)" "$([ "$c" = 0 ]; echo $?)"
done

# ---- 2. no skill uses a private verdict word ----
# topology-drift's `echo STALE` is the registry check's own output, not a verdict.
for s in $SKILLS; do
  hits="$(grep -nE '\b(KEEP|MERGE|STALE|DONE|OBSOLETE|DUPLICATE|HAN|FLAG|FLAGGED|UNTESTABLE)\b' "$KIT_DIR/skills/$s/SKILL.md" \
    | grep -vE 'echo STALE|STALE means' || true)"
  if [ -z "$hits" ]; then pass "skills/$s uses only the base five verdict words"; else fail "skills/$s uses a private verdict word: $(printf '%s' "$hits" | head -3 | cut -c1-110 | tr '\n' '|')"; fi
done

# ---- 3. the old words survive as reasons, with the action unchanged ----
MT="$KIT_DIR/skills/memory-tidy/SKILL.md"
grep -qE '^[[:space:]]*\| OK \(keep\) \|' "$MT" && grep -qE '^[[:space:]]*\| REMOVE \(merged into' "$MT" \
  && grep -qE '^[[:space:]]*\| REMOVE \(stale\) \|' "$MT" && grep -qE '^[[:space:]]*\| UNSURE \|' "$MT"
check "memory-tidy table: OK (keep), REMOVE (merged into), REMOVE (stale), UNSURE" $?

BR="$KIT_DIR/skills/backlog-reconcile/SKILL.md"
grep -qF 'REMOVE (duplicate of' "$BR" && grep -qF 'REMOVE (done' "$BR" && grep -qF 'REMOVE (obsolete' "$BR" && grep -qF 'UNSURE (han' "$BR"
check "backlog-reconcile sweep: duplicate, done, obsolete, han are reasons" $?
grep -qF 'ONLY mutation' "$BR" && grep -qF 'backlog.sh set' "$BR" && grep -qF 'shipped' "$BR" && grep -qF 'dropped' "$BR"
check "backlog-reconcile sweep keeps its one mutation: set shipped / dropped" $?

GA="$KIT_DIR/skills/gauntlet-proof-audit/SKILL.md"
grep -qF 'OK / FIX / UNSURE / DANGER' "$GA"
check "gauntlet-proof-audit verdict list is OK / FIX / UNSURE / DANGER" $?
grep -qF 'UNSURE (untestable' "$GA"
check "gauntlet-proof-audit untestable axis is an UNSURE reason" $?

WD="$KIT_DIR/skills/web-drift/SKILL.md"
grep -qF 'UNSURE (untestable' "$WD"
check "web-drift unreachable site is UNSURE (untestable)" $?

# ---- 4. backlog-reconcile compares classes, not hardcoded board words ----
for cls in active hold terminal; do
  grep -qF "states --class $cls" "$BR"
  check "backlog-reconcile reads board class via states --class $cls" $?
done
! grep -qE '^\| `?DRAFT`?, `?APPROVED`? \|' "$BR" && ! grep -qF 'Maps to board `Status`' "$BR"
check "backlog-reconcile has no spec-keyword to board-word map table" $?
grep -qF 'spec closed but board active' "$BR" && ! grep -qF 'board terminal but spec DRAFT' "$BR"
check "backlog-reconcile flags only spec closed while the board row is active" $?
grep -qF 'header lags' "$BR" && grep -qF 'dropped row with a DRAFT spec' "$BR"
check "backlog-reconcile exempts header lag and a dropped row with a DRAFT spec" $?
# The commands the skill cites must run and return the classes it relies on.
a="$(bash "$BL" states --class active 2>/dev/null | tr '\n' ' ')"; h="$(bash "$BL" states --class hold 2>/dev/null | tr '\n' ' ')"; t="$(bash "$BL" states --class terminal 2>/dev/null | tr '\n' ' ')"
case " $a" in *" queued "*) case " $t" in *" shipped "*) case " $h" in *" parked "*) rc=0 ;; *) rc=1 ;; esac ;; *) rc=1 ;; esac ;; *) rc=1 ;; esac
check "states --class active|hold|terminal return queued / parked / shipped" "$rc"

AG="$KIT_DIR/agents/audit-scanner.md"
grep -qF '`UNSURE (untestable)`, never REMOVE' "$AG" && ! grep -qE '(/|\*\*)UNTESTABLE' "$AG"
check "audit-scanner agent agrees: untestable is an UNSURE reason, not a verdict" $?

# ---- 5. greenlight documents no terminal state it never emits ----
GL="$KIT_DIR/commands/greenlight.md"
! grep -qF 'stop_waiting_review' "$GL"
check "greenlight.md does not document stop_waiting_review" $?
for st in done stop_pr_closed stop_exhausted_retries stop_error; do
  grep -qF "\`$st\`" "$GL"
  check "greenlight.md still documents terminal state $st" $?
done

# ---- 6. dispatch: DISCONNECTED is an attempt-state value, never a worker STATUS ----
DP="$KIT_DIR/commands/dispatch.md"
grep -qF 'only an attempt-state value' "$DP" && grep -qF 'never a `STATUS:` a worker writes' "$DP"
check "dispatch.md: DISCONNECTED is only an attempt-state value, never a worker STATUS" $?
! grep -qE 'STATUS: (DISCONNECTED|FAILED)' "$DP"
check "dispatch.md signal block offers workers only READY and BLOCKED" $?

# ---- 7. negative control: a skill that brings back a private word trips the scan ----
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
sed 's/^\(.*\)REMOVE (stale)/\1STALE/' "$MT" > "$TMP/mut.md"
grep -qE '\bSTALE\b' "$TMP/mut.md" && ! cmp -s "$MT" "$TMP/mut.md"
check "negative control: reintroducing STALE is caught by the private-word scan" $?

[ "$FAILED" -eq 0 ] && { echo "All audit verdict grammar tests passed."; exit 0; }
echo "$FAILED failed."; exit 1
