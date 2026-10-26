#!/usr/bin/env bash
# Suite collection: run-all.sh and bin/test-affected collect tests/test-*.sh AND the module suites
# under lib/<m>/tests/, through one definition (tests/lib/suites.sh).
#
# Before this, only tests/test-*.sh was collected. About forty module suites (stats, skill-curator,
# session, goal, telemetry and others) ran in no runner and no CI job, so a regression in them
# showed nowhere. Cases 1-6 run the real scripts against throwaway kit-shaped repos; cases 7-8 pin
# the real tree so a new module suite cannot be dropped again.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RA="$DIR/tests/run-all.sh"
TA="$DIR/bin/test-affected"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export DWARVES_KIT_LOG_DIR="$TMP/logs" KIT_SUITE_TIMES_FILE="$TMP/times.tsv" KIT_TEST_LOCK=0
g() { git -c user.name=t -c user.email=t@t "$@"; }

mkkit() {  # $1 = dir ; a committed kit-shaped repo with tests/ and module suites
  mkdir -p "$1/tests/lib" "$1/bin" "$1/lib/m/tests/fixtures" "$1/lib/m/tests/lib" "$1/lib/m/sub/tests" "$1/lib/other/tests" "$1/lib/a/b/c/tests"
  cp "$RA" "$1/tests/run-all.sh"; cp "$TA" "$1/bin/test-affected"
  cp "$DIR"/tests/lib/{job-count,suites,timeout,run-lock,suite-times}.sh "$1/tests/lib/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-top.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-docs.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/smoke.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/tests/test-x.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/tests/test-docs.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/tests/smoke.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/sub/tests/test-y.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/other/tests/test-o.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/tests/notatest.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/tests/fixtures/test-fixture.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/m/tests/lib/test-helper.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/lib/a/b/c/tests/test-deep.sh"
  echo 'x=1' > "$1/lib/m/m.sh"; echo 'y=1' > "$1/lib/m/sub/s.sh"; echo 'z=1' > "$1/lib/other/o.sh"
  ( cd "$1" && g init -q -b master && g add -A && g commit -qm init )
}
ran() { grep -E "^$1 +ok" <<<"$2" >/dev/null; }

echo "[1] suite_list collects tests/ and module suites, and nothing else"
K="$TMP/k1"; mkkit "$K"
GOT="$(cd "$K" && . tests/lib/suites.sh && suite_list | paste -sd' ' -)"
WANT="tests/test-docs.sh tests/test-top.sh lib/m/tests/test-docs.sh lib/m/tests/test-x.sh lib/other/tests/test-o.sh lib/m/tests/smoke.sh lib/m/sub/tests/test-y.sh"
if [ "$GOT" = "$WANT" ]; then ok "tests/test-*.sh, lib/<m>/tests/{test-*,smoke}.sh, one nested level; fixtures, tests/lib, other names and deeper dirs left out"
else no "got: $GOT"; fi

echo "[2] suite_id is unique where basenames collide, and suite_path inverts it"
IDS="$(cd "$K" && . tests/lib/suites.sh && for s in $(suite_list); do suite_id "$s"; done | paste -sd' ' -)"
BACK="$(cd "$K" && . tests/lib/suites.sh && suite_path lib-m-test-docs; suite_path test-docs; suite_path lib-m-sub-test-y; suite_path nope || echo none)"
if [ "$IDS" = "test-docs test-top lib-m-test-docs lib-m-test-x lib-other-test-o lib-m-smoke lib-m-sub-test-y" ] \
   && [ "$BACK" = "$(printf 'lib/m/tests/test-docs.sh\ntests/test-docs.sh\nlib/m/sub/tests/test-y.sh\nnone')" ]; then
  ok "test-docs vs lib-m-test-docs; path lookup round-trips"
else no "ids: $IDS back: $BACK"; fi

echo "[3] run-all --all runs the module suites under their ids"
OUT="$(CI=true bash "$K/tests/run-all.sh" --all 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran lib-m-test-x "$OUT" && ran lib-m-smoke "$OUT" && ran lib-m-sub-test-y "$OUT" && ran lib-other-test-o "$OUT" \
   && ran test-docs "$OUT" && ran lib-m-test-docs "$OUT" && grep -q '^run-all: all 7 suites passed' <<<"$OUT" \
   && ! grep -q 'test-fixture\|test-helper\|test-deep\|notatest' <<<"$OUT"; then
  ok "7 suites: 2 under tests/, 5 module suites"
else no "rc=$RC out=$OUT"; fi

echo "[4] a red module suite fails the run and is named by id; --only filters by id"
K4="$TMP/k4"; mkkit "$K4"
printf '#!/usr/bin/env bash\necho "FAIL: a module assertion"\nexit 1\n' > "$K4/lib/m/sub/tests/test-y.sh"
OUT="$(CI=true bash "$K4/tests/run-all.sh" --all 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q '^run-all: FAILED -> lib-m-sub-test-y$' <<<"$OUT" && grep -q 'a module assertion' <<<"$OUT"; then
  ok "FAILED -> lib-m-sub-test-y, the assertion line shown"
else no "rc=$RC out=$OUT"; fi
OUT="$(bash "$K/tests/run-all.sh" --only lib-m-sub 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^run-all: 1 suites' <<<"$OUT" && ran lib-m-sub-test-y "$OUT"; then ok "--only lib-m-sub runs the one module suite"
else no "rc=$RC out=$OUT"; fi

echo "[5] --changed maps a changed lib/<m>/ path to that module's suites"
K5="$TMP/k5"; mkkit "$K5"; echo 'x=2' > "$K5/lib/m/m.sh"
LIST="$(cd "$K5" && bash bin/test-affected --base HEAD --list 2>&1)"
if grep -q 'lib/m/tests/test-x.sh  (module lib/m)' <<<"$LIST" && grep -q 'lib/m/tests/smoke.sh  (module lib/m)' <<<"$LIST" \
   && grep -q 'lib/m/sub/tests/test-y.sh  (module lib/m)' <<<"$LIST" && ! grep -q 'lib/other' <<<"$LIST"; then
  ok "lib/m/m.sh picks the four suites under lib/m, not lib/other"
else no "list: $LIST"; fi
OUT="$(bash "$K5/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran lib-m-test-x "$OUT" && ran lib-m-sub-test-y "$OUT" && ! ran lib-other-test-o "$OUT" && ! ran test-top "$OUT"; then
  ok "run-all --changed runs lib-m-test-x, lib-m-smoke, lib-m-sub-test-y and nothing else"
else no "rc=$RC out=$OUT"; fi

K6="$TMP/k6"; mkkit "$K6"; echo 'y=2' > "$K6/lib/m/sub/s.sh"
LIST="$(cd "$K6" && bash bin/test-affected --base HEAD --list 2>&1)"
if grep -q 'lib/m/sub/tests/test-y.sh  (module lib/m)' <<<"$LIST" && grep -q 'lib/m/tests/test-x.sh  (module lib/m)' <<<"$LIST" && ! grep -q 'lib/other' <<<"$LIST"; then
  ok "a nested path picks the whole module's suites, sub-tool ones included"
else no "list: $LIST"; fi

K7="$TMP/k7"; mkkit "$K7"; echo '# touched' >> "$K7/lib/other/tests/test-o.sh"
LIST="$(cd "$K7" && bash bin/test-affected --base HEAD --list 2>&1)"
if grep -q 'lib/other/tests/test-o.sh  (self)' <<<"$LIST" && ! grep -q 'lib/m/' <<<"$LIST"; then ok "a changed module suite picks itself only"
else no "list: $LIST"; fi

echo "[6] --failed reruns a module suite from the history by its id"
K8="$TMP/k8"; mkkit "$K8"
printf '2026-10-26T00:00:00Z\tabc1234\tlib-m-sub-test-y\t1\t1\t0.5\n2026-10-26T00:00:00Z\tabc1234\ttest-top\t1\t0\t0.5\n' > "$TMP/times.tsv"
OUT="$(bash "$K8/tests/run-all.sh" --failed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran lib-m-sub-test-y "$OUT" && ! ran test-top "$OUT" && grep -q '^run-all: all 1 suites passed' <<<"$OUT"; then
  ok "only lib-m-sub-test-y reran"
else no "rc=$RC out=$OUT"; fi

echo "[7] real tree: every module suite on disk is collected, ids are unique"
cd "$DIR" || exit 1
. tests/lib/suites.sh
COLLECTED="$(suite_list | sort)"
ONDISK="$(find lib -path '*/tests/*' -type f \( -name 'test-*.sh' -o -name 'smoke.sh' \) -not -path '*/fixtures/*' -not -path '*/tests/lib/*' -not -path '*/tests/*/*' | sort)"
MISSING="$(comm -13 <(printf '%s\n' "$COLLECTED") <(printf '%s\n' "$ONDISK"))"
DUPES="$(for s in $(suite_list); do suite_id "$s"; done | sort | uniq -d)"
if [ -z "$MISSING" ] && [ -z "$DUPES" ] && [ -n "$ONDISK" ]; then ok "no module suite is left out of suite_list; no duplicate id"
else no "missing: $MISSING dupes: $DUPES"; fi

echo "[8] real tree: every Python test under lib/ is reached by a tests/test-*.sh"
ORPH=""
for py in $(find lib -path '*/tests/test_*.py' -type f -not -path '*/fixtures/*'); do
  d="$(dirname "$py")"
  grep -lE "$(basename "$py")|${d%/tests}\b" tests/test-*.sh >/dev/null 2>&1 || ORPH="$ORPH $py"
done
if [ -z "$ORPH" ]; then ok "bench, sync, webcheck and session-recall each have a root entry"
else no "unreached:$ORPH"; fi

if [ "$fail" -gt 0 ]; then echo "test-suites-collect: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-suites-collect: all $pass passed"
