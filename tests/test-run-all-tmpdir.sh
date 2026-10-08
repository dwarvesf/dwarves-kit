#!/usr/bin/env bash
# run-all.sh must build its scratch dir under $TMPDIR and stop when it cannot.
#
# macOS `mktemp -d` ignores $TMPDIR and uses /var/folders, which a sandbox may deny. The
# runner then kept an empty OUTDIR, wrote to /runlist and /parallel, ran zero suites and
# printed "all  suites passed". Now the scratch dir is made from an explicit $TMPDIR template
# and a failure to make it exits non-zero with one clear line.
#
# Each case builds a throwaway kit dir (tests/run-all.sh plus a fixture suite) and runs the
# REAL script against it, so nothing here touches the repo's own tests/.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RA="$DIR/tests/run-all.sh"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rat.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export DWARVES_KIT_LOG_DIR="$TMP/logs"

K="$TMP/kit"; mkdir -p "$K/tests/lib"
cp "$RA" "$K/tests/run-all.sh"; cp "$DIR/tests/lib/job-count.sh" "$K/tests/lib/"
# The fixture suite runs while run-all's scratch dir exists, so it can record where it is.
cat > "$K/tests/test-where.sh" <<'SUITE'
#!/usr/bin/env bash
ls -d "$TMPDIR"/run-all.* > "$TMPDIR/seen" 2>/dev/null
exit 0
SUITE

echo "[1] the scratch dir lands under \$TMPDIR"
T1="$TMP/t1"; mkdir -p "$T1"
OUT1="$(TMPDIR="$T1" bash "$K/tests/run-all.sh" --only where 2>&1)"; RC1=$?
if [ "$RC1" -eq 0 ] && grep -q '^run-all: all 1 suites passed' <<<"$OUT1" \
   && grep -q "^$T1/run-all\.[A-Za-z0-9]*\$" "$T1/seen" 2>/dev/null \
   && [ -z "$(ls -d "$T1"/run-all.* 2>/dev/null)" ]; then
  ok "scratch under TMPDIR during the run, removed after"
else no "rc=$RC1 seen=$(cat "$T1/seen" 2>&1) out=$OUT1"; fi

echo "[2] an uncreatable \$TMPDIR fails loudly, runs nothing"
OUT2="$(TMPDIR="$TMP/does-not-exist" bash "$K/tests/run-all.sh" --only where 2>&1)"; RC2=$?
if [ "$RC2" -ne 0 ] && grep -q '^run-all: cannot create a scratch dir under ' <<<"$OUT2" \
   && ! grep -q 'suites passed' <<<"$OUT2"; then
  ok "non-zero exit, one clear line, no false pass"
else no "rc=$RC2 out=$OUT2"; fi

if [ "$fail" -gt 0 ]; then echo "test-run-all-tmpdir: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-run-all-tmpdir: all $pass passed"
