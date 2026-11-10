#!/usr/bin/env bash
# test-host-slots.sh -- tests/lib/host-slots.sh: the host-wide slot semaphore the suite workers take.
# Proves: no more holders than slots at any instant, a dead holder's slot is reclaimed, a live
# holder's slot never is, and KIT_TEST_HOST_SLOTS=0 creates nothing. Temp dirs only, never the real
# default slot dir.
#
# NEGATIVE CONTROL: make host_slot_acquire return at once and the concurrency case goes red.
set -u
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT_DIR/tests/lib/host-slots.sh"
source "$KIT_DIR/tests/lib/timeout.sh"
PASS=0; FAIL=0
assert() { if [ "$2" -eq 0 ]; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/host-slots.XXXXXX")" || exit 1
trap 'mv -f "$T" "$T.done"' EXIT
# A runner above this suite may already hold a slot; the library would then skip the gate.
unset KIT_TEST_HOST_SLOT_HELD KIT_TEST_HOST_SLOTS KIT_TEST_SLOT_DIR

# A holder is its own bash process, as a --run-one worker is: its pid is what the slot records.
cat >"$T/holder.sh" <<'EOF'
#!/usr/bin/env bash
. "$1"
host_slot_acquire
trap host_slot_release EXIT
echo "enter $(date +%s) $$" >>"$2"
sleep "${3:-1}"
echo "leave $(date +%s) $$" >>"$2"
EOF

echo "=== never more holders than slots ==="
D1="$T/slots1"; EV1="$T/events1"; : >"$EV1"
for _ in 1 2 3 4 5; do
  KIT_TEST_HOST_SLOTS=2 KIT_TEST_SLOT_DIR="$D1" bash "$T/holder.sh" "$LIB" "$EV1" 1 &
done
wait
# Replay enter/leave in time order (a leave sorts before an enter in the same second: it ran first).
MAXC="$(awk '{ print $2, ($1 == "leave" ? 0 : 1), $1 }' "$EV1" | sort -k1,1n -k2,2n \
  | awk '{ if ($3 == "enter") c++; else c--; if (c > m) m = c } END { print m + 0 }')"
NENTER="$(grep -c '^enter ' "$EV1")"; NLEAVE="$(grep -c '^leave ' "$EV1")"
assert "all 5 holders finished (enter $NENTER, leave $NLEAVE)" "$([ "$NENTER" = 5 ] && [ "$NLEAVE" = 5 ] && echo 0 || echo 1)"
assert "max concurrency is exactly 2 (saw $MAXC)" "$([ "$MAXC" = 2 ] && echo 0 || echo 1)"
LEFT="$(find "$D1" -mindepth 1 -maxdepth 1 -name 'slot-*' | wc -l | tr -d ' ')"
assert "every slot released afterwards (left: $LEFT)" "$([ "$LEFT" = 0 ] && echo 0 || echo 1)"

echo "=== a dead holder's slot is reclaimed ==="
D2="$T/slots2"; mkdir -p "$D2/slot-0"
sleep 0 & DEAD=$!; wait "$DEAD"
echo "$DEAD" >"$D2/slot-0/pid"
EV2="$T/events2"; : >"$EV2"
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D2" kit_timeout 20 bash "$T/holder.sh" "$LIB" "$EV2" 0
assert "acquire got the slot a dead pid held" "$([ "$(grep -c '^leave ' "$EV2")" = 1 ] && echo 0 || echo 1)"

echo "=== a pid-less slot is reclaimed only once it is old ==="
D2B="$T/slots2b"; mkdir -p "$D2B/slot-0"
EV2B="$T/events2b"; : >"$EV2B"
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D2B" bash "$T/holder.sh" "$LIB" "$EV2B" 0 &
HP=$!
sleep 2
assert "a fresh pid-less slot is still waited on" "$(kill -0 "$HP" 2>/dev/null && echo 0 || echo 1)"
kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
touch -t 200001010000 "$D2B/slot-0"
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D2B" kit_timeout 20 bash "$T/holder.sh" "$LIB" "$EV2B" 0
assert "an old pid-less slot is reclaimed" "$([ "$(grep -c '^leave ' "$EV2B")" = 1 ] && echo 0 || echo 1)"

echo "=== a live holder's slot is never reclaimed ==="
D3="$T/slots3"; EV3="$T/events3"; : >"$EV3"
# The first holder sits on the only slot for 3 s; the second must enter after the first left.
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D3" bash "$T/holder.sh" "$LIB" "$EV3" 3 &
H1=$!
sleep 1
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D3" bash "$T/holder.sh" "$LIB" "$EV3" 0 &
H2=$!
sleep 1
assert "the waiter has not entered while the holder is alive" "$([ "$(grep -c '^enter ' "$EV3")" = 1 ] && echo 0 || echo 1)"
wait "$H1" "$H2"
FIRST_LEAVE="$(awk '$1 == "leave" { print $2; exit }' "$EV3")"
SECOND_ENTER="$(awk '$1 == "enter" { n++; if (n == 2) print $2 }' "$EV3")"
assert "the waiter entered only after the holder left" "$([ -n "$SECOND_ENTER" ] && [ "$SECOND_ENTER" -ge "$FIRST_LEAVE" ] && echo 0 || echo 1)"
WLOG="$T/wait.log"; : >"$WLOG"
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D3" bash "$T/holder.sh" "$LIB" "$EV3" 2 &
H3=$!
sleep 1
KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D3" bash -c '. "$1"; host_slot_acquire "$2"; host_slot_release' _ "$LIB" "$WLOG"
wait "$H3"
assert "a waiter notes its wait once in the log given (lines: $(grep -c 'host-slots: waiting' "$WLOG"))" "$([ "$(grep -c 'host-slots: waiting' "$WLOG")" = 1 ] && echo 0 || echo 1)"

echo "=== KIT_TEST_HOST_SLOTS=0 disables the gate ==="
D4="$T/slots4"
KIT_TEST_HOST_SLOTS=0 KIT_TEST_SLOT_DIR="$D4" bash -c '. "$1"; host_slot_acquire; host_slot_release' _ "$LIB"
assert "no slot dir is created" "$([ ! -e "$D4" ] && echo 0 || echo 1)"

echo "=== a nested acquire inside a held slot does not wait ==="
D5="$T/slots5"
OUT5="$(KIT_TEST_HOST_SLOTS=1 KIT_TEST_SLOT_DIR="$D5" bash -c '. "$1"; host_slot_acquire; host_slot_acquire; echo nested-ok; host_slot_release' _ "$LIB")"
assert "second acquire in the same process tree returns at once" "$([ "$OUT5" = nested-ok ] && echo 0 || echo 1)"

echo ""
echo "=== $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
