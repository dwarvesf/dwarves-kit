#!/usr/bin/env bash
# run-all.sh --changed must run only the suites the diff touches.
#
# The full glob is 13-15 minutes sequential on a Mac. A branch that touches one lib file
# needs the handful of suites that name it, and the pre-push check was paying for all of
# them. Selection: a suite whose CODE lines name a changed file's basename, a changed suite
# itself, tests/test-<mod>*.sh for lib/<mod>/, plus every suite with an `# always:` header
# (the tree-wide lints, which a diff-derived pick can never reach).
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
  printf '#!/usr/bin/env bash\nf=lib/foo/foo.sh\nexit 0\n' > "$1/tests/test-foo.sh"
  printf '#!/usr/bin/env bash\n# a comment naming foo.sh is not a dependency\nexit 0\n' > "$1/tests/test-bar.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-baz.sh"
  printf '#!/usr/bin/env bash\n# always: fixture tree-wide lint\nexit 0\n' > "$1/tests/test-lint.sh"
  echo 'x=1' > "$1/lib/foo/foo.sh"
  echo 'y=1' > "$1/lib/baz/inner.sh"
  echo '# doc' > "$1/docs/x.md"
  ( cd "$1" && g init -q -b master && g add -A && g commit -qm init )
}
ran() { grep -E "^$1 +ok" <<<"$2" >/dev/null; }   # did suite $1 run (and pass) in output $2

echo "[1] an uncommitted lib change picks the suite whose code names the file, plus the always-on lint"
K="$TMP/k1"; mkkit "$K"; echo 'x=2' > "$K/lib/foo/foo.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-foo "$OUT" && ran test-lint "$OUT" && ! ran test-bar "$OUT" && ! ran test-baz "$OUT" \
   && grep -q '1 changed files -> 2 suites (1 named' <<<"$OUT"; then
  ok "test-foo + test-lint; the comment-only mention in test-bar does not pick it"
else no "rc=$RC out=$OUT"; fi

echo "[2] a docs change no suite names runs only the always-on lint and says so"
K="$TMP/k2"; mkkit "$K"; echo '# more' >> "$K/docs/x.md"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-lint "$OUT" && ! ran test-foo "$OUT" && ! ran test-bar "$OUT" \
   && grep -q 'no suite names any of the changed files' <<<"$OUT" && grep -q 'docs/x.md' <<<"$OUT"; then
  ok "test-lint alone, the unnamed file listed"
else no "rc=$RC out=$OUT"; fi

echo "[3] a changed suite picks itself"
K="$TMP/k3"; mkkit "$K"; echo '# touched' >> "$K/tests/test-bar.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-bar "$OUT" && ! ran test-foo "$OUT"; then
  ok "test-bar picked"
else no "rc=$RC out=$OUT"; fi

echo "[4] lib/<mod>/ picks tests/test-<mod>*.sh even when no suite names the file"
K="$TMP/k4"; mkkit "$K"; echo 'y=2' > "$K/lib/baz/inner.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-baz "$OUT" && ! ran test-foo "$OUT"; then
  ok "test-baz via the module name"
else no "rc=$RC out=$OUT"; fi

echo "[5] no diff runs everything and says so"
K="$TMP/k5"; mkkit "$K"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'found no diff.*running everything' <<<"$OUT" \
   && grep -q '^run-all: all 4 suites passed' <<<"$OUT"; then
  ok "full glob on an empty diff"
else no "rc=$RC out=$OUT"; fi

echo "[5b] a bare invocation is --changed, and --all is the full glob"
K="$TMP/k5b"; mkkit "$K"; echo 'x=2' > "$K/lib/foo/foo.sh"
OUT="$(bash "$K/tests/run-all.sh" 2>&1)"; RC=$?
OUT2="$(bash "$K/tests/run-all.sh" --all 2>&1)"; RC2=$?
if [ "$RC" -eq 0 ] && grep -q -- '--changed against' <<<"$OUT" && ! ran test-bar "$OUT" \
   && [ "$RC2" -eq 0 ] && grep -q '^run-all: all 4 suites passed' <<<"$OUT2"; then
  ok "bare picks, --all runs everything"
else no "rc=$RC rc2=$RC2 out=$OUT out2=$OUT2"; fi

echo "[6] an explicit base scopes the diff to the commits after it"
K="$TMP/k6"; mkkit "$K"; echo 'x=3' > "$K/lib/foo/foo.sh"; ( cd "$K" && g commit -qam foo )
OUT="$(bash "$K/tests/run-all.sh" --changed HEAD~1 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && ran test-foo "$OUT" && ! ran test-bar "$OUT"; then
  ok "test-foo from the committed change"
else no "rc=$RC out=$OUT"; fi

echo "[7] a red always-on lint fails the run even when the diff names nothing"
K="$TMP/k7"; mkkit "$K"; printf '#!/usr/bin/env bash\n# always: fixture tree-wide lint\necho "FAIL: orphan"\nexit 1\n' > "$K/tests/test-lint.sh"
( cd "$K" && g commit -qam red-lint ); echo 'z=1' > "$K/lib/foo/orphan.sh"
OUT="$(bash "$K/tests/run-all.sh" --changed 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q '^run-all: FAILED ->.*test-lint' <<<"$OUT"; then
  ok "the pinned lint is not skippable"
else no "rc=$RC out=$OUT"; fi

if [ "$fail" -gt 0 ]; then echo "test-run-all-changed: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-run-all-changed: all $pass passed"
