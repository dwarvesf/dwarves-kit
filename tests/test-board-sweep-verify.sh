#!/usr/bin/env bash
# test-board-sweep-verify.sh -- lib/sync/sweep/board-sweep-verify (`board sweep verify`).
#
#   AC1  --last-tick reads the newest sweep tick only, never sweeps
#   AC2  per-repo summary (counts + BLOCKED flag) and the single-repo detail view
#   AC3  a still-running tick, an unknown repo (exit 1), a missing log (exit 2)
#   AC4  --run: a sweep that leaves every board byte-identical is VERIFIED (exit 0)
#   AC5  NEGATIVE CONTROL: a sweep that writes back into a board is DAMAGE (exit 1)
#   AC6  --no-run diffs two snapshots with no sweep between them
#
# Fixtures, never a real log or a real board.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
VERIFY="${HERE}/../lib/sync/sweep/board-sweep-verify"
TMP=$(mktemp -d)
trap 'command rm -rf "$TMP"' EXIT

fail=0
assert() {  # $1 label, $2 expected substring, $3 actual
  case "$3" in
    *"$2"*) echo "ok   $1" ;;
    *) echo "FAIL $1: expected '$2' in:"; printf '%s\n' "$3" | sed 's/^/       /'; fail=1 ;;
  esac
}
assert_not() {  # $1 label, $2 forbidden substring, $3 actual
  case "$3" in
    *"$2"*) echo "FAIL $1: did not expect '$2' in:"; printf '%s\n' "$3" | sed 's/^/       /'; fail=1 ;;
    *) echo "ok   $1" ;;
  esac
}

# ---- fixture log: an older finished tick, a newer finished tick (the one
# --last-tick must pick), each with noise this feature must drop -------------
LOG="$TMP/board-sweep.log"
cat > "$LOG" <<'EOF'
[2026-09-16 09:00:00] board-sweep: start
  preflight: all boards enrolled
  alpha rc=0
    synced hermes: 1 spoke items, 1 board rows
      · note      orphan item (no board row): 'stale ticket'
[2026-09-16 09:02:00] board-sweep: end rc=0
[2026-09-17 17:52:18] board-sweep: start
  preflight: all boards enrolled
  alpha rc=0
    synced hermes: 634 spoke items, 121 board rows
      ✓ board     ID-650 -> shipped
      · note      orphan item (no board row): 'stale ticket'
      · note      refused 56 board status flips from hermes (cap 10): reasons
    ============ BLOCKED: commit on checked-out main ============
    board publish: commit failed for _meta/BACKLOG.md
  beta rc=0
    synced reminders: 4 spoke items, 4 board rows
  mirror rc=1 (home=/srv/hermes/home)
    board-mirror: skip XY-21 (gamma): status 'shipped' not bridged
    mirror: applied 0 create, 0 change, 2 complete, 7 error(s)
[2026-09-17 17:54:33] board-sweep: end rc=0
EOF

out=$("$VERIFY" --last-tick --log "$LOG" 2>&1)
assert "picks the newer start" "2026-09-17 17:52:18" "$out"
assert_not "ignores the older tick" "2026-09-16 09:00:00" "$out"
assert "prints the end line" "board-sweep: end rc=0" "$out"
assert "alpha board flip count" "alpha rc=0 board=1 refused=1" "$out"
assert "alpha BLOCKED flag" "[BLOCKED]" "$out"
assert "beta summary present" "beta rc=0 board=0 refused=0" "$out"
assert "mirror summary present" "mirror rc=1 board=0 refused=0" "$out"

out_repo=$("$VERIFY" --last-tick alpha --log "$LOG" 2>&1)
assert "repo detail keeps the board flip" "✓ board     ID-650 -> shipped" "$out_repo"
assert "repo detail keeps BLOCKED marker" "BLOCKED: commit on checked-out main" "$out_repo"
assert_not "repo detail drops orphan-item noise" "orphan item (no board row)" "$out_repo"
assert "repo detail ends with a summary line" "alpha rc=0 board=1 refused=1" "$out_repo"

out_mirror=$("$VERIFY" --last-tick mirror --log "$LOG" 2>&1)
assert_not "mirror detail drops board-mirror: skip noise" "board-mirror: skip" "$out_mirror"
assert "mirror detail keeps the applied line" "mirror: applied 0 create" "$out_mirror"

LOG2="$TMP/running.log"
cat > "$LOG2" <<'EOF'
[2026-09-17 18:00:00] board-sweep: start
  preflight: all boards enrolled
  alpha rc=0
EOF
out_running=$("$VERIFY" --last-tick --log "$LOG2" 2>&1)
assert "still-running tick says so" "(still running)" "$out_running"

"$VERIFY" --last-tick nope-repo --log "$LOG" >/dev/null 2>"$TMP/err.txt"
rc=$?
assert "unknown repo exits 1" "1" "$rc"
assert "unknown repo names itself" "unknown repo 'nope-repo'" "$(cat "$TMP/err.txt")"

"$VERIFY" --last-tick --log "$TMP/no-such.log" >/dev/null 2>"$TMP/err2.txt"
rc2=$?
assert "missing log exits 2" "2" "$rc2"
assert "missing log names the path" "no log at $TMP/no-such.log" "$(cat "$TMP/err2.txt")"

# --name picks the label the log's start/end lines carry
sed 's/board-sweep:/nightly:/' "$LOG" > "$TMP/nightly.log"
out_name=$("$VERIFY" --last-tick --name nightly --log "$TMP/nightly.log" 2>&1)
assert "--name matches a custom sweep label" "nightly: end rc=0" "$out_name"

# ---- --run: byte-identical vs damage ------------------------------------------
mkdir -p "$TMP/a" "$TMP/b"
printf '| ID-1 | row | n | queued |\n' > "$TMP/a/BACKLOG.md"
printf '| ID-2 | row | n | queued |\n' > "$TMP/b/BACKLOG.md"
printf 'alpha  %s/a/BACKLOG.md  on\nbeta  %s/b/BACKLOG.md\nghost  %s/none/BACKLOG.md\n' "$TMP" "$TMP" "$TMP" > "$TMP/boards.txt"

printf '#!/bin/bash\nexit 0\n' > "$TMP/sweep-clean"
printf '#!/bin/bash\nprintf "| ID-1 | row | n | shipped |\\n" > "%s/a/BACKLOG.md"\nexit 0\n' "$TMP" > "$TMP/sweep-damage"
chmod +x "$TMP/sweep-clean" "$TMP/sweep-damage"

out_clean=$("$VERIFY" --registry "$TMP/boards.txt" --run "$TMP/sweep-clean" 2>&1); rc_clean=$?
assert "a clean sweep is VERIFIED" "VERIFIED: every board byte-identical after the sweep" "$out_clean"
assert "a clean sweep exits 0" "0" "$rc_clean"

out_dmg=$("$VERIFY" --registry "$TMP/boards.txt" --run "$TMP/sweep-damage" 2>&1); rc_dmg=$?
assert "a sweep that writes back is DAMAGE" "DAMAGE: these boards changed during the sweep" "$out_dmg"
assert "the damaged board is named" "alpha" "$out_dmg"
assert_not "an untouched board is not named as damaged" "beta " "$(printf '%s\n' "$out_dmg" | grep -E '^    [<>]')"
assert "a damaging sweep exits 1" "1" "$rc_dmg"

out_nr=$("$VERIFY" --registry "$TMP/boards.txt" --no-run 2>&1); rc_nr=$?
assert "--no-run with no sweep between snapshots is VERIFIED" "VERIFIED" "$out_nr"
assert "--no-run exits 0" "0" "$rc_nr"

"$VERIFY" --registry "$TMP/boards.txt" >/dev/null 2>"$TMP/err3.txt"; rc3=$?
assert "no --run and no --no-run is refused" "2" "$rc3"
assert "the refusal says what to pass" "need --run" "$(cat "$TMP/err3.txt")"

exit "$fail"
