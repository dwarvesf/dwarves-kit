#!/usr/bin/env bash
# test-bin-forwarders.sh -- SPEC-194 (ADR-0034 decisions 1/7): the bin/ census and every
# forwarder's dispatch chain, exercised THROUGH the stable entrypoints (not the deep lib
# paths the per-tool suites already cover).
#
#   1. CENSUS: bin/ contains exactly the ADR-0034 set (11 subsystem entries, 2 module CLIs, and
#      the standalone executables the 2026-09-06 amendment names
#      + 2 module CLIs; `config` lands in SG-08), and every retired entry stays gone.
#   2. DISPATCH: each new/changed forwarder routes a real invocation end to end:
#      learn debt (the relocated weekend-batch), every session <verb>, board promote,
#      spec/goal/mega/queue/stats.
#   3. `learn propose` (SPEC-195) and `learn drain` (SPEC-196) are both LIVE; their dispatch
#      is smoke-tested here (deep behavior: tests/test-learn-propose.sh, test-learn-drain.sh).
#      The unknown-verb NC below still proves the router refuses what it does not own.
#
# Hermetic: learn-debt reads point DWARVES_KIT_LOG_DIR at a temp dir; board promote runs
# in an empty temp repo. `stats` needs uv (the module's own dependency) -- SKIPs cleanly
# where uv is absent, same precedent as tests/test-stats-no-persist.sh.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ok: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }
assert_true() { if [ "$2" = "0" ]; then ok "$1"; else bad "$1"; fi; }

echo "== census: bin/ is exactly the ADR-0034 SG-04 target set =="
# +plugin-check, +skill-improve, +skill-review (SPEC-200 C2, 2026-07-14): each was a module
# executable reachable from NO operator surface. The contract lint (C2) now fails on that, and
# this census is the other half of the same guarantee: bin/ may not grow silently either.
# activate and release are standalone executables (ADR-0034, amendment 2026-09-06), not
# SPEC-184 forwarders; the census names them because the DISPATCH block below proves each
# answers with its own contract. A bin/ entry with no such block is still the drift this
# census exists to catch.
EXPECTED="activate board classify config gate goal learn mega plugin-check precedent prose-rag queue release session skill-improve skill-review spec stats worktree-provision wrap"
ACTUAL="$(ls -1 "$KIT_DIR/bin" | sort | tr '\n' ' ' | sed 's/ $//')"
EXPECTED_SORTED="$(printf '%s\n' $EXPECTED | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$ACTUAL" = "$EXPECTED_SORTED" ]; then
  ok "bin/ census matches ($ACTUAL)"
else
  bad "bin/ census drifted. expected: $EXPECTED_SORTED / actual: $ACTUAL"
fi

echo "== census NC: every retired entry stays gone =="
for retired in add-backlog session-intel session-observe session-recall session-report session-semantic; do
  assert_true "bin/$retired absent" "$([ ! -e "$KIT_DIR/bin/$retired" ]; echo $?)"
done

echo "== activate + release: the two non-forwarder CLIs in bin/ answer with their own contract =="
out="$("$KIT_DIR/bin/activate" 2>&1)"; rc=$?
assert_true "bin/activate with no args prints its usage line" "$(grep -q 'usage: bin/activate' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/release" --help 2>&1)"; rc=$?
assert_true "bin/release rejects a non-semver argument with its own message" "$(grep -q 'semver required' <<<"$out"; echo $?)"

echo "== learn: debt dispatches to the relocated weekend-batch =="
TMPLOG="$(mktemp -d)"
out="$(DWARVES_KIT_LOG_DIR="$TMPLOG" "$KIT_DIR/bin/learn" debt list 2>&1)"; rc=$?
assert_true "learn debt list exits 0 through bin/learn (empty ledger)" "$rc"
out="$(DWARVES_KIT_LOG_DIR="$TMPLOG" "$KIT_DIR/bin/learn" debt collect --all-repos 2>&1)"; rc=$?
assert_true "learn debt collect exits 0 through bin/learn" "$rc"
assert_true "learn debt collect emits the digest header" "$(grep -q 'Weekend batch: debt paydown' <<<"$out"; echo $?)"
out="$(DWARVES_KIT_LOG_DIR="$TMPLOG" "$KIT_DIR/bin/learn" debt mark-paid no-such-rid 2>&1)"; rc=$?
assert_true "learn debt mark-paid reaches the engine (engine's own no-ledger error, nonzero)" "$([ $rc -ne 0 ] && grep -q 'mark-paid: no ledger file' <<<"$out"; echo $?)"

echo "== learn: propose dispatches to the SPEC-195 distiller (deep behavior: test-learn-propose.sh) =="
out="$("$KIT_DIR/bin/learn" propose --help 2>&1)"; rc=$?
assert_true "learn propose exits 0 through bin/learn (--help)" "$rc"
assert_true "learn propose reaches the distiller (its own usage, not a refusal)" "$(grep -q 'usage: learn propose' <<<"$out"; echo $?)"

echo "== learn: drain dispatches to the SPEC-196 render (deep behavior: test-learn-drain.sh) =="
TMPSTAGE="$(mktemp -d)/backlog-staging.md"
out="$(BACKLOG_STAGE_STAGING="$TMPSTAGE" "$KIT_DIR/bin/learn" drain 2>&1)"; rc=$?
assert_true "learn drain exits 0 through bin/learn (no staging file)" "$rc"
assert_true "learn drain reports nothing staged (honest-empty)" "$(grep -q 'nothing staged' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/learn" bogus-verb 2>&1)"; rc=$?
assert_true "learn rejects an unknown verb (exit 1)" "$([ $rc -eq 1 ]; echo $?)"

echo "== session: all five verbs route through the one dispatcher =="
out="$("$KIT_DIR/bin/session" observe --help 2>&1)"
assert_true "session observe reaches its tool" "$(grep -q 'usage: session-observe' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/session" intel --help 2>&1)"
assert_true "session intel reaches its tool" "$(grep -q 'usage: session-intel' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/session" recall 2>&1 || true)"
assert_true "session recall reaches its tool" "$(grep -q 'usage: session-recall' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/session" report --help 2>&1)"
assert_true "session report reaches its tool" "$(grep -q 'usage: session-report' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/session" semantic --help 2>&1)"
assert_true "session semantic reaches its tool" "$(grep -q 'usage: session-semantic' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/session" bogus-verb 2>&1)"; rc=$?
assert_true "session rejects an unknown verb (exit 1)" "$([ $rc -eq 1 ]; echo $?)"

echo "== board: promote folds the human gate (ex add-backlog) =="
EMPTY="$(mktemp -d)"
out="$(cd "$EMPTY" && "$KIT_DIR/bin/board" promote 2>&1)"; rc=$?
assert_true "board promote exits 0 in an empty repo" "$rc"
assert_true "board promote reports nothing staged" "$(grep -qE 'no staged candidates|nothing staged' <<<"$out"; echo $?)"

echo "== spec/goal/mega/queue: forwarders reach their engines =="
out="$("$KIT_DIR/bin/spec" --help 2>&1)"
assert_true "spec forwarder reaches spec.sh" "$(grep -q 'spec.sh index' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/goal" --help 2>&1)"
assert_true "goal forwarder reaches goal.sh" "$(grep -q 'goal.sh draft' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/mega" --help 2>&1)"
assert_true "mega forwarder reaches mega.sh" "$(grep -q 'mega status' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/queue" --help 2>&1 || true)"
assert_true "queue forwarder reaches queue.sh" "$(grep -q 'usage: queue.sh run' <<<"$out"; echo $?)"

echo "== precedent: forwarder reaches precedent.sh (records + inventory surfaces, SPEC-245) =="
out="$("$KIT_DIR/bin/precedent" --help 2>&1)"; rc=$?
assert_true "precedent forwarder reaches precedent.sh usage" "$rc"
assert_true "precedent --help prints precedent.sh's own usage" "$(grep -q 'precedent.sh --' <<<"$out"; echo $?)"
EMPTY_PRECEDENT="$(mktemp -d)"
out="$(cd "$EMPTY_PRECEDENT" && "$KIT_DIR/bin/precedent" find "spec drift" --surface records 2>&1)"; rc=$?
assert_true "precedent find --surface records dispatches end to end (empty repo, no hits)" "$rc"
out="$("$KIT_DIR/bin/precedent" find x --surface bogus 2>&1)"; rc=$?
assert_true "precedent find rejects an unknown surface (exit 64)" "$([ $rc -eq 64 ]; echo $?)"

echo "== wrap: forwarder reaches wrap.sh (deep behavior: test-wrap.sh) =="
out="$("$KIT_DIR/bin/wrap" --help 2>&1)"; rc=$?
assert_true "wrap forwarder exits 0 (--help)" "$rc"
assert_true "wrap --help prints wrap.sh's own usage" "$(grep -q 'wrap.sh scan' <<<"$out"; echo $?)"
WRAP_EMPTY="$(mktemp -d)"
out="$("$KIT_DIR/bin/wrap" scan "$WRAP_EMPTY" 2>&1)"; rc=$?
assert_true "wrap scan dispatches end to end (non-repo argument, exit 0)" "$rc"
assert_true "wrap scan prints the not-a-repo skip line" "$(grep -q 'not a git repo, skipped' <<<"$out"; echo $?)"
out="$("$KIT_DIR/bin/wrap" bogus-verb 2>&1)"; rc=$?
assert_true "wrap rejects an unknown verb (exit 64)" "$([ $rc -eq 64 ]; echo $?)"

echo "== stats: forwarder reaches the uv CLI (SKIP without uv) =="
if command -v uv >/dev/null 2>&1; then
  out="$("$KIT_DIR/bin/stats" --help 2>&1)"; rc=$?
  assert_true "stats forwarder exits 0 through uv" "$rc"
  assert_true "stats forwarder prints the CLI usage" "$(grep -q 'Read-only DuckDB lens' <<<"$out"; echo $?)"
else
  skip "stats forwarder (uv not on PATH; the module's own dependency)"
fi

echo
if [ $FAIL -gt 0 ]; then echo "test-bin-forwarders: $PASS passed, $FAIL FAILED, $SKIP skipped" >&2; exit 1; fi
echo "test-bin-forwarders: all $PASS passed, $SKIP skipped"
