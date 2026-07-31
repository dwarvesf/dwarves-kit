#!/usr/bin/env bash
# test-self-grill-watcher.sh -- SPEC-217 (board row ID-457, the manager-loop pilot).
#
# Two halves, honestly kept apart:
#
#  A) The watcher (`lib/queue/watch-board.sh`) is real bash logic: marker matching, the
#     intersection with parse-board's allow-list, journal dedup, dry-run-by-default, and the
#     `--apply` handoff to the queue. All asserted directly against fixture boards.
#
#  B) Self-answer mode (`commands/grill.md` Step 2b) is PROSE: an agent reads it and behaves.
#     Its behavior cannot be honestly asserted here, the same limitation
#     tests/test-grill-conditioning.sh section B and tests/test-design-record.sh already
#     document for other prompt-text logic in this kit. What IS checkable, and is checked, is
#     the doc's MECHANICAL contract: the mode, the marker, the ledger verb, and the ID-450
#     reconciliation are all present.
#
# Isolation: every run points --journal at a temp file and WATCH_QUEUE_CMD at a mock, so the
# real machine journal is never read or written and no queue window ever opens.
#
# Run: bash tests/test-self-grill-watcher.sh   (exit 0 = all checks green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WATCH="$KIT_DIR/lib/queue/watch-board.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
assert_eq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }
has()    { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

# ---- fixture repo -----------------------------------------------------------------------------
# parse-board's repo self-consistency check compares the token's repo= against the name we pass,
# so the fixture repo is created under a fixed basename and referenced by --repo-name.
REPO=""; JOURNAL=""; LOGD=""
new_repo() {
  local base; base="$(_mk)"
  REPO="$base/fixboard"
  mkdir -p "$REPO/_meta/megagoals/pilot" "$REPO/_meta"
  printf 'pointer body\n' > "$REPO/_meta/megagoals/pilot/POINTER_PROMPT.md"
  LOGD="$base/logs"; mkdir -p "$LOGD"
  JOURNAL="$LOGD/queue-journal.tsv"
  : > "$JOURNAL"
}

# A board carrying every case at once.
write_board() {
  cat > "$REPO/_meta/BACKLOG.md" <<'EOF'
# Backlog

| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | auto + pointer | pilot row #auto #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |
| ID-002 | auto, no pointer token | operator marked it #auto but never pointed it | queued |
| ID-003 | pointer, no marker | #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |
| ID-004 | auto but claimed | #auto #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | claimed |
| ID-005 | lookalike marker | #automation is not the marker #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |
| ID-006 | auto + dangling pointer | #auto #queue{repo=fixboard,pointer=_meta/megagoals/pilot/GONE.md} | queued |
EOF
}

# A board with no #auto rows at all (the negative control).
write_board_no_auto() {
  cat > "$REPO/_meta/BACKLOG.md" <<'EOF'
# Backlog

| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-101 | ordinary queued row | #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |
| ID-102 | another one | no tags at all | queued |
EOF
}

MOCKLOG=""
watch() {
  env DWARVES_KIT_LOG_DIR="$LOGD" WATCH_QUEUE_CMD="${WATCH_QUEUE_CMD:-bash $MOCK}" \
    bash "$WATCH" --repo-root "$REPO" --repo-name fixboard --journal "$JOURNAL" "$@" 2>&1
}

echo "=== self-grill + watcher (SPEC-217) ==="
echo "--- Section A: the watcher ---"

# The queue mock: records its argv instead of opening a window.
MOCKDIR="$(_mk)"; MOCK="$MOCKDIR/mock-queue"; MOCKLOG="$MOCKDIR/invoked.log"
cat > "$MOCK" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MOCKLOG"
EOF
chmod +x "$MOCK"

# Check 1: the happy path -- only the auto-tagged, queued, pointered row is planned.
new_repo; write_board
OUT="$(watch)"
assert "check1: exit 0 on a populated board" $?
assert "check1b: ID-001 planned" "$(has 'ID-001 -> _meta/megagoals/pilot/POINTER_PROMPT.md' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"
assert "check1c: plan says 1 row" "$(has '1 row(s) to enqueue' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

# Check 2-5 (skip classes): nothing but ID-001 reaches the plan.
assert "check2: ID-002 (#auto, no pointer token) not planned" "$(has 'ID-002 ->' "$OUT" && echo 1 || echo 0)"
assert "check2b: ID-002 reported as skipped, not silently dropped" "$(has 'skip ID-002' "$OUT" && echo 0 || echo 1)"
assert "check3: ID-003 (pointer, no marker) not planned" "$(has 'ID-003' "$OUT" && echo 1 || echo 0)"
assert "check4: ID-004 (claimed, not queued) not planned" "$(has 'ID-004' "$OUT" && echo 1 || echo 0)"
assert "check5: ID-005 (#automation lookalike) not planned" "$(has 'ID-005' "$OUT" && echo 1 || echo 0)"
assert "check6: ID-006 (dangling pointer) not planned" "$(has 'ID-006 ->' "$OUT" && echo 1 || echo 0)"

# Check 7: dry-run is the DEFAULT -- the queue was never invoked.
assert_eq "check7: dry-run invoked the queue 0 times" "$( [ -f "$MOCKLOG" ] && wc -l < "$MOCKLOG" | tr -d ' ' || echo 0 )" "0"

# Check 8: --apply invokes the queue once, with the plan file and the cap.
: > "$MOCKLOG"
OUT="$(watch --apply --max 1)"
assert_eq "check8: --apply invoked the queue once" "$(wc -l < "$MOCKLOG" | tr -d ' ')" "1"
INV="$(cat "$MOCKLOG")"
assert "check8b: the queue got the plan tsv" "$(has 'watch-board-plan.tsv' "$INV" && echo 0 || echo 1)" "(got: $INV)"
assert "check8c: the budget cap is forwarded as --max-megas 1" "$(has -- '--max-megas 1' "$INV" && echo 0 || echo 1)" "(got: $INV)"

# Check 9: the default cap is 1 even when --max is omitted.
: > "$MOCKLOG"
watch --apply >/dev/null
assert "check9: default cap is --max-megas 1" "$(has -- '--max-megas 1' "$(cat "$MOCKLOG")" && echo 0 || echo 1)"

# Check 10-12 (dedup, SPEC-217 DEC-002): terminal verdicts skip, retryable ones re-plan.
new_repo; write_board
printf '%s\tfixboard__ID-001\tdone\t\n' "2026-07-31T00:00:00Z" > "$JOURNAL"
OUT="$(watch)"
assert "check10: a slug whose last verdict is done is skipped" "$(has 'skip ID-001: already done' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

printf '%s\tfixboard__ID-001\tgated\tneeds review\n' "2026-07-31T00:00:00Z" > "$JOURNAL"
OUT="$(watch)"
assert "check11: a slug whose last verdict is gated is skipped" "$(has 'skip ID-001: already gated' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

printf '%s\tfixboard__ID-001\terror\tlaunch failed\n' "2026-07-31T00:00:00Z" > "$JOURNAL"
OUT="$(watch)"
assert "check12: a slug whose last verdict is error is re-planned" "$(has 'ID-001 ->' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

# Check 13: last-verdict wins -- an old done followed by a newer error is retryable.
{ printf '%s\tfixboard__ID-001\tdone\t\n' "2026-07-30T00:00:00Z"
  printf '%s\tfixboard__ID-001\terror\t\n' "2026-07-31T00:00:00Z"; } > "$JOURNAL"
OUT="$(watch)"
assert "check13: dedup reads the LAST verdict, not any verdict" "$(has 'ID-001 ->' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

# Check 14: a slug named only inside another row's free-text reason never false-matches.
new_repo; write_board
printf '%s\tother-slug\tdone\tsuperseded fixboard__ID-001\n' "2026-07-31T00:00:00Z" > "$JOURNAL"
OUT="$(watch)"
assert "check14: journal dedup is field-exact, not substring" "$(has 'ID-001 ->' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

echo "--- Section A negative controls ---"

# Check 15 (NEGATIVE CONTROL): a board with zero #auto rows plans nothing and exits 0.
new_repo; write_board_no_auto
OUT="$(watch)"; rc=$?
assert_eq "check15: zero-#auto board exits 0" "$rc" "0"
assert "check15b: zero-#auto board plans nothing" "$(has '0 rows to enqueue' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"
assert "check15c: the eligible-but-unmarked row is NOT planned" "$(has 'ID-101 ->' "$OUT" && echo 1 || echo 0)"
: > "$MOCKLOG"
watch --apply >/dev/null
assert_eq "check15d: an empty plan never invokes the queue, even with --apply" "$(wc -l < "$MOCKLOG" | tr -d ' ')" "0"

# Check 16 (NEGATIVE CONTROL): a missing board is exit 0 with an empty plan, never a page.
new_repo
OUT="$(watch --board "$REPO/_meta/NOPE.md")"; rc=$?
assert_eq "check16: missing board exits 0" "$rc" "0"
assert "check16b: missing board plans nothing" "$(has '0 rows to enqueue' "$OUT" && echo 0 || echo 1)" "(got: $OUT)"

# Check 17: the watcher never mutates the board it read.
new_repo; write_board
BEFORE="$(shasum "$REPO/_meta/BACKLOG.md" | awk '{print $1}')"
watch --apply >/dev/null
AFTER="$(shasum "$REPO/_meta/BACKLOG.md" | awk '{print $1}')"
assert_eq "check17: the board is byte-identical after a run" "$AFTER" "$BEFORE"

echo "--- Section B: the self-answer contract in commands/grill.md (mechanical half only) ---"

G="$KIT_DIR/commands/grill.md"
for probe in \
  "Self-answer mode" \
  "#auto" \
  "gate-ledger.sh debt" \
  "verdict=wave" \
  "never answers its own questions" \
  "AUTONOMOUS" \
  "learn debt collect"
do
  grep -qF -- "$probe" "$G"
  assert "grill.md carries: $probe" $?
done

# The interactive default must survive: the mode is an exception, not a replacement.
grep -qF -- "ONE question per turn" "$G"
assert "grill.md still carries the interactive one-question-per-turn default" $?

echo
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
