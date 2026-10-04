#!/usr/bin/env bash
# bin/test-affected: the pass cache sees paths a suite reads by glob, a `# runner:` suite is
# expanded into its area suites, and a run appends rows to the suite timing history.
#
#   1. A suite picked because it READS a changed path (a glob or scan, never named in its text)
#      is not CACHED once that path changes again. NEGATIVE CONTROL: with the picked-path part
#      dropped from the key, the stale PASS comes back CACHED.
#   2. A change that hits the runner fallback lists the area suites, never tests/test-meta.sh,
#      and each area runs under its own timeout.
#   3. A run appends one row per suite that ran (none for a CACHED one) and one run row.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TA="$KIT_DIR/bin/test-affected"
PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
has() { grep -qF -- "$2" <<<"$1" && ok "$3" || bad "$3 (missing '$2' in: $1)"; }
hasnt() { grep -qF -- "$2" <<<"$1" && bad "$3 (unexpected '$2' in: $1)" || ok "$3"; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export KIT_LOAD_WARN=100000 TA_MARK="$W/mark"
unset KIT_LEDGER_DIR
export DWARVES_KIT_LOG_DIR="$W/logs"
export KIT_SUITE_TIMES_FILE="$W/hist.tsv"

# The binary under test runs from $W/tabin so its siblings (the history helper, the log-dir lib)
# resolve inside the fixture, never in the real tree.
mkdir -p "$W/tabin" "$W/lib/telemetry" "$W/tests/lib"
cp "$TA" "$W/tabin/test-affected"
cp "$KIT_DIR/lib/telemetry/kit-log-dir.sh" "$W/lib/telemetry/"; mkdir -p "$W/lib/config"; cp "$KIT_DIR/lib/config/kit-config.sh" "$W/lib/config/"
cp "$KIT_DIR/tests/lib/suite-times.sh" "$W/tests/lib/"
TA2="$W/tabin/test-affected"

R="$W/repo"; mkdir -p "$R/tests" "$R/commands" "$R/lib/board"; cd "$R"
git init -q -b main . 2>/dev/null && git config user.email t@t && git config user.name t
echo 1.0.0 > VERSION
echo one > commands/c.md
echo one > lib/board/unnamed.sh
printf '#!/bin/bash\n# runner: relays the area suites\n# runner-suites: agents-commands docs-registry\nexit 0\n' > tests/test-meta.sh
# Each area reads commands/ by glob: it never names commands/c.md, so the reference scan cannot see it.
printf '#!/bin/bash\nfor f in commands/*.md; do :; done\necho run-ac >> "$TA_MARK"\nexit 0\n' > tests/test-meta-agents-commands.sh
printf '#!/bin/bash\nfor f in commands/*.md; do :; done\necho run-dr >> "$TA_MARK"\nexit 0\n' > tests/test-meta-docs-registry.sh
git add -A && git commit -qm base
BASE="$(git rev-parse HEAD)"

echo "== 1. a glob-read input that changes again is not served from the cache =="
echo two > commands/c.md
out="$(bash "$TA2" --base "$BASE" 2>&1)"
has   "$out" "PASS tests/test-meta-agents-commands.sh" "first run: the area that reads commands/ runs"
echo three > commands/c.md
out="$(bash "$TA2" --base "$BASE" 2>&1)"
has   "$out" "PASS tests/test-meta-agents-commands.sh" "the glob-read input changed again: the suite runs, not CACHED"
hasnt "$out" "CACHED tests/test-meta-agents-commands.sh" "no stale PASS for the area"
out="$(bash "$TA2" --base "$BASE" 2>&1)"
has   "$out" "CACHED tests/test-meta-agents-commands.sh" "an unchanged input still hits the cache"

echo "== 1b. NEGATIVE CONTROL: drop the picked-path part of the key and the stale PASS returns =="
mkdir -p "$W/mbin"
sed '/\$1 == t { print \$2 }/s|"\$TMP/pickers"|/dev/null|' "$TA" >"$W/mbin/test-affected"
if cmp -s "$TA" "$W/mbin/test-affected"; then bad "the mutation changed nothing (the key line moved?)"; else ok "mutant built: picked paths no longer feed the key"; fi
export DWARVES_KIT_LOG_DIR="$W/mlogs"
echo four > commands/c.md
bash "$W/mbin/test-affected" --base "$BASE" >/dev/null 2>&1
echo five > commands/c.md
out="$(bash "$W/mbin/test-affected" --base "$BASE" 2>&1)"
has   "$out" "CACHED tests/test-meta-agents-commands.sh" "mutant: the changed glob-read input comes back CACHED (the defect)"
export DWARVES_KIT_LOG_DIR="$W/logs"

echo "== 2. the runner fallback lists the area suites, each with its own timeout =="
git checkout -q -- commands/c.md
echo two > lib/board/unnamed.sh
out="$(bash "$TA2" --base "$BASE" --list 2>&1)"
has   "$out" "tests/test-meta-agents-commands.sh  (runner tests/test-meta.sh: reads lib/board/unnamed.sh (no area attributed))" "an area suite, with the runner named in its reason"
has   "$out" "tests/test-meta-docs-registry.sh  (runner tests/test-meta.sh: reads lib/board/unnamed.sh (no area attributed))" "the other area suite"
hasnt "$out" "tests/test-meta.sh  (" "tests/test-meta.sh itself is not listed"
printf '#!/bin/bash\nsleep 4\nfor f in commands/*.md; do :; done\nexit 0\n' > tests/test-meta-agents-commands.sh
printf '# header\ntest-meta-agents-commands 1\ntest-meta-docs-registry 99\n' > "$W/tabin/test-affected.timeouts"
out="$(bash "$TA2" --base "$BASE" --no-cache 2>&1)"
has   "$out" "TIMEOUT tests/test-meta-agents-commands.sh (limit 1s)" "the area suite runs under its own line of the timeouts file"
has   "$out" "PASS tests/test-meta-docs-registry.sh" "the other area passes under its own limit"

echo "== 3. a run appends suite rows and one run row to the history =="
printf '#!/bin/bash\nfor f in commands/*.md; do :; done\nexit 0\n' > tests/test-meta-agents-commands.sh
: >"$W/hist.tsv"
echo two > commands/c.md
bash "$TA2" --base "$BASE" --no-cache >/dev/null 2>&1; RC=$?
SUITE_ROWS="$(awk -F'\t' '$3 !~ /^run:/' "$W/hist.tsv" | wc -l | tr -d ' ')"
RUN_ROW="$(awk -F'\t' '$3 == "run:test-affected"' "$W/hist.tsv")"
[ "$RC" -eq 0 ] && ok "the run's exit code is the suites' verdict" || bad "rc=$RC"
[ "$SUITE_ROWS" = 2 ] && ok "one row per suite that ran (2)" || bad "suite rows=$SUITE_ROWS: $(cat "$W/hist.tsv")"
if [ "$(awk -F'\t' '{print NF}' <<<"$RUN_ROW")" = 8 ] && grep -q 'kind=run' <<<"$RUN_ROW" && grep -q 'selected=2' <<<"$RUN_ROW" && [ "$(cut -f5 <<<"$RUN_ROW")" = 0 ]; then ok "one run row: kind=run, selected=2, exit 0"
else bad "run row: $RUN_ROW"; fi
n0="$(wc -l <"$W/hist.tsv" | tr -d ' ')"
bash "$TA2" --base "$BASE" >/dev/null 2>&1
bash "$TA2" --base "$BASE" >/dev/null 2>&1
n1="$(wc -l <"$W/hist.tsv" | tr -d ' ')"
# run 1 of the pair misses the cache (the earlier run was --no-cache but still recorded PASS) or hits; either way the last run is all CACHED
LAST="$(tail -1 "$W/hist.tsv")"
grep -q 'run:test-affected' <<<"$LAST" && ok "a fully CACHED run appends only its run row" || bad "last row: $LAST"
bash "$TA2" --base "$BASE" --list >/dev/null 2>&1
[ "$(wc -l <"$W/hist.tsv" | tr -d ' ')" = "$n1" ] && ok "--list appends nothing" || bad "--list wrote history"
[ "$n1" -gt "$n0" ] && ok "history grew across runs" || bad "n0=$n0 n1=$n1"

echo
echo "test-affected-cache: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
