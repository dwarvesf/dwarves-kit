#!/usr/bin/env bash
# test-run-lock.sh -- the machine-wide test lock in tests/lib/run-lock.sh.
# Uses a private lock path (KIT_TEST_LOCK_DIR), never the real lock.
# modules under test: tests/lib/run-lock.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0; TOTAL=0
chk() { # chk <label> <rc>
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3"; echo $?)"; }
chk_no()  { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3" && echo 1 || echo 0)"; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-run-lock-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
LOCK="$TMPD/lock"

# job.sh locks, then reports what it saw. hold.sh does the same and then holds for 2s.
for j in job hold; do
  cat >"$TMPD/$j.sh" <<EOF
#!/usr/bin/env bash
source "$KIT_DIR/tests/lib/run-lock.sh"
run_lock_exec "\$0" "\$@"
echo "ran held=\${KIT_TEST_LOCK_HELD:-unset} lock=\$([ -d "$LOCK" ] && echo present || echo absent)"
EOF
done
printf 'sleep 2\ntouch "%s/hold.done"\n' "$TMPD" >>"$TMPD/hold.sh"
echo 'if [ -f "'"$TMPD"'/hold.done" ]; then echo after-holder; fi' >>"$TMPD/job.sh"

# run_job <env assignments...>: a clean environment plus the private lock path and a fast poll.
run_job() { env -u CI -u KIT_TEST_LOCK -u KIT_TEST_LOCK_HELD KIT_TEST_LOCK_DIR="$LOCK" KIT_TEST_LOCK_POLL=1 "$@" bash "$TMPD/job.sh" 2>"$TMPD/err"; }
# fake_holder <pid>: a lock directory owned by <pid>.
fake_holder() { rm -rf "$LOCK"; mkdir "$LOCK"; printf '%s\nfake cmd\n2026-01-01 00:00:00\n' "$1" >"$LOCK/info"; }

echo "=== acquire and release ==="
out="$(run_job)"; rc=$?
chk "a lone run exits 0" "$rc"
chk_has "the child runs holding the lock" "$out" "ran held=1 lock=present"
chk "the lock is gone after the run" "$([ ! -d "$LOCK" ]; echo $?)"
chk_no "no wait line when the lock is free" "$(cat "$TMPD/err")" "waiting for test lock"

echo
echo "=== a second run waits for the first ==="
env -u CI -u KIT_TEST_LOCK -u KIT_TEST_LOCK_HELD KIT_TEST_LOCK_DIR="$LOCK" bash "$TMPD/hold.sh" >/dev/null 2>&1 &
holder=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$LOCK/info" ] && break; sleep 0.5; done
out="$(run_job KIT_TEST_LOCK_WAIT=30)"; rc=$?
wait "$holder"
chk "the waiter exits 0" "$rc"
chk_has "the waiter says who holds the lock" "$(cat "$TMPD/err")" "waiting for test lock held by pid"
chk_has "the waiter ran after the holder finished" "$out" "after-holder"
chk_has "the waiter ran under the lock" "$out" "ran held=1"
chk "the lock is gone at the end" "$([ ! -d "$LOCK" ]; echo $?)"

echo
echo "=== stale holder ==="
deadpid="$(bash -c 'echo $$')"
fake_holder "$deadpid"
out="$(run_job KIT_TEST_LOCK_WAIT=30)"; rc=$?
chk "a dead holder is taken over (exit 0)" "$rc"
chk_has "the takeover run held the lock" "$out" "ran held=1 lock=present"
chk_no "no wait line for a dead holder" "$(cat "$TMPD/err")" "waiting for test lock"
chk "the lock is gone after the takeover" "$([ ! -d "$LOCK" ]; echo $?)"

echo
echo "=== skips ==="
fake_holder "$$"
out="$(run_job KIT_TEST_LOCK_HELD=1 KIT_TEST_LOCK_WAIT=30)"; rc=$?
chk "a nested run (KIT_TEST_LOCK_HELD) skips locking" "$rc"
chk_has "the nested run ran at once" "$out" "ran held=1"
chk_no "the nested run did not wait" "$(cat "$TMPD/err")" "waiting for test lock"
out="$(run_job KIT_TEST_LOCK=0 KIT_TEST_LOCK_WAIT=30)"; rc=$?
chk "KIT_TEST_LOCK=0 skips locking" "$rc"
chk_has "KIT_TEST_LOCK=0 ran inline" "$out" "ran held=unset"
chk_no "KIT_TEST_LOCK=0 did not wait" "$(cat "$TMPD/err")" "waiting for test lock"
out="$(run_job CI=1 KIT_TEST_LOCK_WAIT=30)"; rc=$?
chk "CI skips locking" "$rc"
chk_has "CI ran inline" "$out" "ran held=unset"
chk "a skipped run leaves the other holder's lock alone" "$([ "$(sed -n 1p "$LOCK/info")" = "$$" ]; echo $?)"

echo
echo "=== give up and run anyway ==="
fake_holder "$$"
out="$(run_job KIT_TEST_LOCK_WAIT=1)"; rc=$?
chk "a timed-out wait still exits 0" "$rc"
chk_has "the timed-out run ran" "$out" "ran held=unset"
chk_has "the wait line names the holder" "$(cat "$TMPD/err")" "waiting for test lock held by pid $$"
chk_has "the give-up warning is printed" "$(cat "$TMPD/err")" "running anyway"
chk "a non-owner does not release the holder's lock" "$([ "$(sed -n 1p "$LOCK/info")" = "$$" ]; echo $?)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-run-lock: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-run-lock: all $PASS passed"
