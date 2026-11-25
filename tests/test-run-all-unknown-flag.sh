#!/usr/bin/env bash
# run-all.sh must refuse an unknown mode or flag (exit 64, one usage line on stderr) BEFORE it
# takes the per-host test lock and before any suite starts.
#
# It used to read any unknown first argument as "the full glob": `bash tests/run-all.sh --help`
# queued on the host lock and started the 25 minute run, past the local --all refusal. --help
# and -h now print the header and exit 0, as bin/test-affected and tests/lib/suite-times.sh do.
#
# Every case runs a COPY of run-all.sh inside a throwaway tree that holds one sentinel suite and a
# stub run-lock.sh, under a hard timeout. The stub records that the lock was asked for and the
# sentinel records that a suite ran, so a refusal that came too late is visible and the real
# suites and the real host lock are out of reach, red or green.
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
g() { git -c user.name=t -c user.email=t@t "$@"; }
source "$DIR/tests/lib/timeout.sh"

# A committed kit-shaped repo: the real run-all.sh, a sentinel suite, a stub lock.
K="$TMP/kit"
mkdir -p "$K/tests/lib" "$K/bin"
cp "$RA" "$K/tests/run-all.sh"; cp "$TA" "$K/bin/test-affected"
cp "$DIR/tests/lib/job-count.sh" "$DIR/tests/lib/suites.sh" "$DIR/tests/lib/timeout.sh" "$K/tests/lib/"
# The markers live outside the repo, so they never read as a diff to --changed.
MARK="$TMP/marks"; mkdir -p "$MARK"
printf 'run_lock_exec() { : >"%s/lock-taken"; return 0; }\n' "$MARK" >"$K/tests/lib/run-lock.sh"
printf '#!/usr/bin/env bash\n# always: fixture, so --changed picks it too\n: >"%s/suite-ran"\nexit 0\n' "$MARK" >"$K/tests/test-sentinel.sh"
( cd "$K" && g init -q -b master && g add -A && g commit -qm init )

# RA_RUN <args...>: sets RC, OUT (stdout), ERR (stderr); LOCK / RAN say what the run touched.
RA_RUN() {
  rm -f "$MARK/lock-taken" "$MARK/suite-ran"
  local so="$TMP/so" se="$TMP/se"
  ( unset CI KIT_RUN_ALL KIT_TEST_LOCK_HELD; cd "$K" && kit_timeout 30 bash "$K/tests/run-all.sh" "$@" ) >"$so" 2>"$se"
  RC=$?; OUT="$(cat "$so")"; ERR="$(cat "$se")"
  LOCK=0; [ -e "$MARK/lock-taken" ] && LOCK=1
  RAN=0; [ -e "$MARK/suite-ran" ] && RAN=1
}

echo "[1] an unknown or misplaced argument exits 64 with a usage line, before the lock and any suite"
for args in "--bogus" "--alll" "bogus" "--only" "--time --bogus" "--bogus --time" "--changed main extra" \
            "--failed extra" "--time --times p95" "--only a b" "--changed --bogus" "--only --bogus"; do
  # shellcheck disable=SC2086
  RA_RUN $args
  if [ "$RC" -eq 64 ] && [ "$LOCK" -eq 0 ] && [ "$RAN" -eq 0 ] && [ -z "$OUT" ] \
     && [ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" = 1 ] && grep -q 'usage: bash tests/run-all.sh' <<<"$ERR"; then
    ok "refused: $args"
  else no "'$args': rc=$RC lock=$LOCK ran=$RAN out=$OUT err=$ERR"; fi
done

echo "[2] --all with a stray argument is refused even where --all itself is allowed"
rm -f "$MARK/lock-taken" "$MARK/suite-ran"
( unset KIT_RUN_ALL KIT_TEST_LOCK_HELD; cd "$K" && CI=true kit_timeout 30 bash "$K/tests/run-all.sh" --all extra ) >"$TMP/so" 2>"$TMP/se"; RC=$?
if [ "$RC" -eq 64 ] && [ ! -e "$MARK/lock-taken" ] && [ ! -e "$MARK/suite-ran" ] && grep -q 'usage: bash tests/run-all.sh' "$TMP/se"; then
  ok "--all extra: exit 64, nothing ran"
else no "--all extra: rc=$RC err=$(cat "$TMP/se")"; fi

echo "[3] --help and -h print the usage header and exit 0, before the lock and any suite"
for h in --help -h; do
  RA_RUN "$h"
  if [ "$RC" -eq 0 ] && [ "$LOCK" -eq 0 ] && [ "$RAN" -eq 0 ] && grep -q '^Usage: bash tests/run-all.sh' <<<"$OUT"; then
    ok "$h: usage on stdout, exit 0"
  else no "$h: rc=$RC lock=$LOCK ran=$RAN out=$OUT err=$ERR"; fi
done

echo "[4] every documented form is still accepted, takes the lock, and runs the suite"
for args in "--only sentinel" "--time --only sentinel" "--only sentinel --time" "--changed HEAD" "--changed HEAD --time" "--time --changed" ""; do
  # shellcheck disable=SC2086
  RA_RUN $args
  if [ "$RC" -eq 0 ] && [ "$LOCK" -eq 1 ] && [ "$RAN" -eq 1 ]; then ok "accepted: ${args:-<bare>}"
  else no "'${args:-<bare>}': rc=$RC lock=$LOCK ran=$RAN out=$OUT err=$ERR"; fi
done
rm -f "$MARK/lock-taken" "$MARK/suite-ran"
( unset KIT_RUN_ALL KIT_TEST_LOCK_HELD; cd "$K" && CI=true kit_timeout 30 bash "$K/tests/run-all.sh" --all --time ) >"$TMP/so" 2>"$TMP/se"; RC=$?
if [ "$RC" -eq 0 ] && [ -e "$MARK/lock-taken" ] && [ -e "$MARK/suite-ran" ]; then ok "accepted: --all --time (CI=true)"
else no "--all --time: rc=$RC err=$(cat "$TMP/se")"; fi

echo "[5] --failed and --times are not refused as unknown (this tree has no suite-times.sh, so they stop for that reason)"
for args in "--failed" "--times p95"; do
  # shellcheck disable=SC2086
  RA_RUN $args
  if [ "$RC" -ne 64 ] && ! grep -q 'usage: bash tests/run-all.sh' <<<"$ERR"; then ok "not refused: $args (rc=$RC)"
  else no "'$args': rc=$RC err=$ERR"; fi
done

if [ "$fail" -gt 0 ]; then echo "test-run-all-unknown-flag: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-run-all-unknown-flag: all $pass passed"
