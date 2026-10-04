#!/usr/bin/env bash
# test-battery-gate.sh -- /kit:battery size gate (lib/gate/battery-gate.sh).
# Proves: a small diff SKIPs; a large diff RUNs; a small diff on a hard path RUNs; markdown and
# docs/verification growth does not flip SKIP to RUN; the env and .kit.toml floors win; the
# working tree counts; the gate always exits 0. Throwaway git fixtures in a fresh mktemp dir.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${BATTERY_GATE:-$KIT/lib/gate/battery-gate.sh}"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT
export KIT_CONFIG_ROOT="$WORK/nocfg-root" KIT_CONFIG_OPERATOR="$WORK/nocfg-op"
unset BATTERY_SMALL_FLOOR

# make_repo <dir>: committed base on master, then a feat branch.
make_repo() {
  local d="$1"
  mkdir -p "$d/lib" "$d/docs"
  git -C "$d" init -q -b master
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo "base() { :; }" > "$d/lib/thing.sh"
  echo "# readme"      > "$d/README.md"
  printf '[battery]\nsize_floor = 5\n' > "$d/.kit.toml.lowfloor"
  git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" checkout -qb feat/x
}
gen() { local i; for i in $(seq 1 "$2"); do echo "line $i"; done >> "$1"; }
run() { bash "$GATE" "$1" master; echo "exit=$?"; }
has() { { trap '' PIPE; printf '%s' "$1" 2>/dev/null || :; } | grep -qF -- "$2"; }

D="$WORK/small"; make_repo "$D"; gen "$D/lib/thing.sh" 10; git -C "$D" commit -qam small
OUT="$(run "$D")"
has "$OUT" "SKIP: small change (10 changed lines, 1 files); owe proof of done, not the battery" && has "$OUT" "exit=0" \
  && pass "T1 small diff -> SKIP, exit 0" || fail "T1 got: $OUT"

D="$WORK/large"; make_repo "$D"; gen "$D/lib/thing.sh" 200; git -C "$D" commit -qam large
OUT="$(run "$D")"
has "$OUT" "RUN" && ! has "$OUT" "SKIP" && has "$OUT" "exit=0" && pass "T2 large diff -> RUN" || fail "T2 got: $OUT"

D="$WORK/hard"; make_repo "$D"; mkdir -p "$D/db/migrations"; echo "alter table t add c int;" > "$D/db/migrations/001.sql"
git -C "$D" add -A; git -C "$D" commit -qm hard
OUT="$(run "$D")"
has "$OUT" "RUN" && ! has "$OUT" "SKIP" && pass "T3 small diff on a hard path -> RUN" || fail "T3 got: $OUT"

D="$WORK/md"; make_repo "$D"; gen "$D/lib/thing.sh" 10; gen "$D/README.md" 500
mkdir -p "$D/docs/verification"; gen "$D/docs/verification/p.txt" 500; git -C "$D" add -A; git -C "$D" commit -qm md
OUT="$(run "$D")"
has "$OUT" "SKIP: small change (10 changed lines, 1 files)" && pass "T4 markdown + docs/verification growth does not flip SKIP" || fail "T4 got: $OUT"

D="$WORK/wt"; make_repo "$D"; gen "$D/lib/thing.sh" 200
OUT="$(run "$D")"
has "$OUT" "RUN" && ! has "$OUT" "SKIP" && pass "T5 uncommitted working-tree lines count" || fail "T5 got: $OUT"

D="$WORK/envfloor"; make_repo "$D"; gen "$D/lib/thing.sh" 10; git -C "$D" commit -qam small
OUT="$(BATTERY_SMALL_FLOOR=5 run "$D")"
has "$OUT" "RUN" && ! has "$OUT" "SKIP" && pass "T6 BATTERY_SMALL_FLOOR overrides the default" || fail "T6 got: $OUT"

D="$WORK/toml"; make_repo "$D"; git -C "$D" mv .kit.toml.lowfloor .kit.toml; git -C "$D" commit -qm cfg
gen "$D/lib/thing.sh" 10; git -C "$D" commit -qam small
OUT="$(bash "$GATE" "$D" master)"
has "$OUT" "RUN" && pass "T7 [battery] size_floor in .kit.toml overrides the default" || fail "T7 got: $OUT"

[ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAIL"; exit 1; }
