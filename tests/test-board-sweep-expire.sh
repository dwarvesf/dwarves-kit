#!/usr/bin/env bash
# test-board-sweep-expire.sh -- the expiry leg of `board sweep`: one
# `board mirror-cleanup --expire-only` call per tick against the mirror's Hermes
# store. The board command is a stub; no real hermes, board, or kanban is touched.
#
#   AC1  --expire-kinds-file + --mirror-hermes-home -> the leg runs with --apply, the pinned
#        home and the kinds file, and its output line reaches the sweep log
#   AC2  --dry-run drops --apply
#   AC3  a failing leg is logged and never flips the exit code
#   NC1  without --expire-kinds-file the leg is off (a mirror-only sweep behaves as before)
#   NC2  without --mirror-hermes-home there is no store, so the leg is off
#   NC3  no hermes CLI -> an honest skip line, mirror-cleanup never called
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="$HERE/../lib/sync/sweep/board-sweep"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
mkdir -p "$WORK/_meta" "$WORK/.local/bin"
: > "$WORK/boards.txt"
echo '[]' > "$WORK/kinds.json"

cat > "$WORK/board" <<'STUB'
#!/usr/bin/env bash
echo "board called: $*" >> "$FAKE_CALL_LOG"
echo "board env HERMES_HOME=${HERMES_HOME:-UNSET}" >> "$FAKE_CALL_LOG"
if [ "${1:-}" = "mirror-cleanup" ]; then
  echo "expired 4 cards on social (limit 14d)"
  exit "${FAKE_EXPIRE_RC:-0}"
fi
exit 0
STUB
chmod +x "$WORK/board"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/.local/bin/hermes"
chmod +x "$WORK/.local/bin/hermes"
export FAKE_CALL_LOG FAKE_EXPIRE_RC

run_sweep() {
  HOME="$WORK" PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
    "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/board" --repo-root "$WORK" "$@"
}

echo "AC1: the leg runs and applies"
FAKE_CALL_LOG="$WORK/c1.log"; : > "$FAKE_CALL_LOG"
out="$(run_sweep --mirror-hermes-home "$WORK/home" --expire-kinds-file "$WORK/kinds.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exits 0" || bad "sweep exited $rc"
grep -qxF "board called: mirror-cleanup --expire-only --hermes-home $WORK/home --kinds-file $WORK/kinds.json --apply" "$FAKE_CALL_LOG" \
  && ok "argv: --expire-only, the store, the kinds file, --apply" || bad "argv: $(grep mirror-cleanup "$FAKE_CALL_LOG")"
grep -qxF "board env HERMES_HOME=$WORK/home" <(grep 'env HERMES_HOME' "$FAKE_CALL_LOG" | tail -1) \
  && ok "HERMES_HOME pinned to the mirror store" || bad "HERMES_HOME: $(grep 'env HERMES_HOME' "$FAKE_CALL_LOG" | tail -1)"
grep -q "expire rc=0" <<<"$out" && grep -q "expired 4 cards on social (limit 14d)" <<<"$out" \
  && ok "the leg's one line reaches the sweep log" || bad "log: $out"

echo "AC2: --dry-run only reports"
FAKE_CALL_LOG="$WORK/c2.log"; : > "$FAKE_CALL_LOG"
run_sweep --dry-run --mirror-hermes-home "$WORK/home" --expire-kinds-file "$WORK/kinds.json" >/dev/null 2>&1
grep -q "board called: mirror-cleanup" "$FAKE_CALL_LOG" && ok "the leg still runs on a dry run" || bad "leg did not run"
grep -q "board called: mirror-cleanup.* --apply" "$FAKE_CALL_LOG" && bad "--apply passed on a dry run" || ok "no --apply on a dry run"

echo "AC3: a failing leg never flips the exit code"
FAKE_CALL_LOG="$WORK/c3.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_EXPIRE_RC=1 run_sweep --mirror-hermes-home "$WORK/home" --expire-kinds-file "$WORK/kinds.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep still exits 0" || bad "sweep exited $rc"
grep -q "expire rc=1" <<<"$out" && ok "the failure is logged" || bad "log: $out"

echo "NC1: no --expire-kinds-file, no leg"
FAKE_CALL_LOG="$WORK/n1.log"; : > "$FAKE_CALL_LOG"
out="$(run_sweep --mirror-hermes-home "$WORK/home" 2>&1)"
grep -q "mirror-cleanup" "$FAKE_CALL_LOG" && bad "mirror-cleanup called without the flag" || ok "mirror-cleanup never called"
grep -q "expire" <<<"$out" && bad "the leg spoke without being asked: $out" || ok "no expire output"

echo "NC2: no store, no leg"
FAKE_CALL_LOG="$WORK/n2.log"; : > "$FAKE_CALL_LOG"
run_sweep --expire-kinds-file "$WORK/kinds.json" >/dev/null 2>&1
grep -q "mirror-cleanup" "$FAKE_CALL_LOG" && bad "mirror-cleanup called with no store" || ok "mirror-cleanup never called"

echo "NC3: no hermes on PATH"
mv -f "$WORK/.local/bin/hermes" "$WORK/hermes.away"
FAKE_CALL_LOG="$WORK/n3.log"; : > "$FAKE_CALL_LOG"
out="$(run_sweep --mirror-hermes-home "$WORK/home" --expire-kinds-file "$WORK/kinds.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exits 0" || bad "sweep exited $rc"
grep -q "expire skipped: hermes CLI not on PATH" <<<"$out" && ok "honest skip line" || bad "log: $out"
grep -q "mirror-cleanup" "$FAKE_CALL_LOG" && bad "mirror-cleanup called without hermes" || ok "mirror-cleanup never called"

echo
echo "  TOTAL: $((PASS+FAIL))   PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
