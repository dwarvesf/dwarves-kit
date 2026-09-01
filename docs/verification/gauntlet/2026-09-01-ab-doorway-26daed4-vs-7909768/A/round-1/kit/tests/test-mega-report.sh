#!/usr/bin/env bash
# test-mega-report.sh -- `mega report <slug>` (the RUN_REPORT telemetry generator).
# Hermetic: a temp megagoals root + a temp KIT_LOG_DIR; never touches the live ledgers.
# Proves: header counts, matrix cell vocabulary (ran/skip/absent), the honest all-dash
# row for a rid-less sub-goal (NC), Proof-line-only SPEC resolution (NC: a body cross-ref
# is NOT attributed), the extra-gate note, --out, and read-only-over-sources.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
assert_grep()   { if grep -qF "$2" <<<"$3"; then ok "$1"; else bad "$1 (missing: $2)"; fi; }
assert_nogrep() { if grep -qF "$2" <<<"$3"; then bad "$1 (unexpected: $2)"; else ok "$1"; fi; }

TD="$(mktemp -d)"
MROOT="$TD/megagoals"; LOGS="$TD/logs"
mkdir -p "$MROOT/demo/goals" "$LOGS/runs"

cat > "$MROOT/demo/ROADMAP.md" <<'EOF'
# Mega-goal: demo
## Sub-goals
- [x] 01-alpha-widget, builds the widget, `auto`, PR #10 merged abc1234 (green)
- [ ] 02-beta-nothing, never started, `gate`, PR #
EOF

cat > "$MROOT/demo/goals/01-alpha-widget.md" <<'EOF'
# Sub-goal 01: alpha-widget
**Proof:** run-table (SPEC-123): fixture green. Body cross-ref below must NOT win.
See also SPEC-999 (a dependency, not this sub-goal's spec).
EOF

cat > "$LOGS/runs/feat-01-alpha-widget.log" <<'EOF'
2026-07-12T01:00:00Z | START | lane=normal classified=normal type=spec-feature repo=demo
2026-07-12T01:01:00Z | GATE | spec | ran | fixture
2026-07-12T01:02:00Z | GATE | build | ran | fixture
2026-07-12T01:03:00Z | GATE | grill | skipped | home-turf
2026-07-12T01:04:00Z | GATE | mystery-gate | ran | not-in-vocabulary
2026-07-12T01:05:00Z | TOKENS | in=100 out=200
EOF
LEDGER_BEFORE="$(shasum "$LOGS/runs/feat-01-alpha-widget.log")"

OUT="$(python3 "$KIT_DIR/lib/mega/mega-report.py" demo --megagoals-root "$MROOT" --log-dir "$LOGS" 2>&1)"; RC=$?

echo "== header + matrix from a real fixture ledger =="
[ $RC -eq 0 ] && ok "exit 0" || bad "exit $RC"
assert_grep "header counts 1/2 built · 1 merged" "(1/2 built · 1 merged)" "$OUT"
ROW01="$(grep '^01 ' <<<"$OUT")"
assert_grep "ran gates render ●" "●" "$ROW01"
assert_grep "skipped gate renders ○" "○" "$ROW01"
assert_grep "auto/gate tag column present" "auto" "$ROW01"
assert_grep "SPEC comes from the Proof line" "123" "$ROW01"
assert_nogrep "NC: a body SPEC cross-ref is NOT attributed" "999" "$ROW01"
assert_grep "unknown ledger gate lands in the extras note" "mystery-gate" "$OUT"
assert_grep "TOKENS rows surface in the worker-minutes block" "in=100 out=200" "$OUT"

echo "== NC: a sub-goal with no rid renders honest dashes, never a guess =="
ROW02="$(grep '^02 ' <<<"$OUT")"
assert_grep "rid-less row is flagged" "(no rid ledger matched)" "$ROW02"
assert_nogrep "rid-less row has zero ● cells" "●" "$ROW02"

echo "== --out + read-only contract =="
python3 "$KIT_DIR/lib/mega/mega-report.py" demo --megagoals-root "$MROOT" --log-dir "$LOGS" --out "$TD/r.md" >/dev/null 2>&1
[ -s "$TD/r.md" ] && ok "--out writes the report file" || bad "--out produced nothing"
[ "$(shasum "$LOGS/runs/feat-01-alpha-widget.log")" = "$LEDGER_BEFORE" ] \
  && ok "source ledger byte-identical after both runs (read-only)" \
  || bad "source ledger MUTATED"

echo "== launcher: bin/mega report dispatches =="
USAGE_OUT="$(bash "$KIT_DIR/bin/mega" report 2>&1)"; URC=$?
[ $URC -ne 0 ] && ok "report without a slug refuses (exit $URC)" || bad "slug-less report exited 0"
assert_grep "refusal names the requirement" "a <slug> is required" "$USAGE_OUT"

# ID-287 coverage: run cmd_report END-TO-END through the bash launcher (not the direct
# python entry the tests above use), so the re-anchored `source "$self_dir/../telemetry/
# kit-log-dir.sh"` in cmd_report is exercised. A wrong `..` after the lib/mega/ move fails
# the source and never renders the report -- this assertion goes RED, closing the blind spot
# the direct-python tests left (they bypass the launcher entirely).
echo "== launcher: bin/mega report <slug> runs cmd_report end-to-end (covers the telemetry anchor) =="
LAUNCH_OUT="$(DWARVES_KIT_LOG_DIR="$LOGS" bash "$KIT_DIR/bin/mega" report demo --megagoals-root "$MROOT" 2>&1)"; LRC=$?
[ $LRC -eq 0 ] && ok "bin/mega report demo exits 0 (cmd_report telemetry source resolved)" || bad "bin/mega report demo exit $LRC: $LAUNCH_OUT"
assert_grep "launcher path renders the same header as the direct python path" "(1/2 built · 1 merged)" "$LAUNCH_OUT"

echo
echo "TOTAL: $((PASS+FAIL))   PASS: $PASS   FAIL: $FAIL"
[ $FAIL -eq 0 ]
