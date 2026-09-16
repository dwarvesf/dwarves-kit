#!/usr/bin/env bash
# run-all.sh --changed must run only the suites the diff touches.
#
# The full glob is 13-15 minutes sequential on a Mac. A branch that touches one lib file
# needs the handful of suites that name it, and the pre-push check was paying for all of
# them. Selection is a basename text match plus tests/test-<mod>*.sh for lib/<mod>/, with
# test-meta riding along for anything outside lib/.
#
# Each case builds a throwaway kit-shaped git repo (tests/run-all.sh plus fixture suites)
# and runs the REAL script against it, so nothing here touches the repo's own tests/.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RA="$DIR/tests/run-all.sh"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -c user.name=t -c user.email=t@t "$@"; }

mkkit() {  # $1 = dir ; a committed kit-shaped repo holding the real run-all.sh
  mkdir -p "$1/tests" "$1/lib/foo" "$1/lib/baz" "$1/docs"
  cp "$RA" "$1/tests/run-all.sh"
  printf '#!/usr/bin/env bash\n# covers lib/foo/foo.sh\nexit 0\n' > "$1/tests/test-foo.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-bar.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-baz.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-meta.sh"
  echo 'x=1' > "$1/lib/foo/foo.sh"
  echo 'y=1' > "$1/lib/baz/inner.sh"
  echo '# doc' > "$1/docs/x.md"
  ( cd "$1" && g init -q -b master && g add -A && g commit -qm init )
}
ran() { grep -E "^$1 +ok" <<<"$2" >/dev/null; }   # did suite $1 run (and pass) in output $2

echo "[1] an uncommitted lib change picks only the suite that names the file"
K="$TMP/k1"; mkkit "$K"; echo 'x=2' > "$K/lib/foo/foo.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-foo "$OUT" && ! ran test-bar "$OUT" && ! ran test-meta "$OUT" \
   && grep -q '1 changed files -> 1 suites' <<<"$OUT"; then
  ok "test-foo alone"
else no "rc=$RC out=$OUT"; fi

echo "[2] a docs change picks test-meta and nothing else"
K="$TMP/k2"; mkkit "$K"; echo '# more' >> "$K/docs/x.md"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-meta "$OUT" && ! ran test-foo "$OUT" && ! ran test-bar "$OUT"; then
  ok "test-meta alone"
else no "rc=$RC out=$OUT"; fi

echo "[3] a changed suite picks itself"
K="$TMP/k3"; mkkit "$K"; echo '# touched' >> "$K/tests/test-bar.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-bar "$OUT" && ! ran test-foo "$OUT"; then
  ok "test-bar picked (test-meta rides along: tests/ is outside lib/)"
else no "rc=$RC out=$OUT"; fi

echo "[4] lib/<mod>/ picks tests/test-<mod>*.sh even when no suite names the file"
K="$TMP/k4"; mkkit "$K"; echo 'y=2' > "$K/lib/baz/inner.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-baz "$OUT" && ! ran test-foo "$OUT" && ! ran test-meta "$OUT"; then
  ok "test-baz via the module name"
else no "rc=$RC out=$OUT"; fi

echo "[5] no diff runs everything and says so"
K="$TMP/k5"; mkkit "$K"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'found no diff.*running everything' <<<"$OUT" \
   && grep -q '^run-all: all 4 suites passed' <<<"$OUT"; then
  ok "full glob on an empty diff"
else no "rc=$RC out=$OUT"; fi

echo "[6] an explicit base scopes the diff to the commits after it"
K="$TMP/k6"; mkkit "$K"; echo 'x=3' > "$K/lib/foo/foo.sh"; ( cd "$K" && g commit -qam foo )
OUT="$(bash "$K/tests/run-all.sh" --changed HEAD~1 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-foo "$OUT" && ! ran test-bar "$OUT"; then
  ok "test-foo from the committed change"
else no "rc=$RC out=$OUT"; fi

echo "[7] a lib change no suite covers runs nothing and names the file"
K="$TMP/k7"; mkkit "$K"; echo 'z=1' > "$K/lib/foo/orphan.sh"; rm "$K/tests/test-foo.sh"
( cd "$K" && g commit -qam drop-foo-suite )
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'no suite names any of the changed files' <<<"$OUT" \
   && grep -q 'lib/foo/orphan.sh' <<<"$OUT" && ! grep -q 'suites passed' <<<"$OUT"; then
  ok "orphan named, nothing run"
else no "rc=$RC out=$OUT"; fi

if [ "$fail" -gt 0 ]; then echo "test-run-all-changed: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-run-all-changed: all $pass passed"
