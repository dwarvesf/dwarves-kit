#!/usr/bin/env bash
# test-wrap-flick7b.sh -- `wrap flick-7b`, the mechanical call behind step 7b's shadow second opinion.
# Shares the harness in tests/lib/wrap-stub.sh (chk, TMPD, the operator-config pin).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-flick.sh lib/wrap/report-lint.sh lib/decide/flick.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

echo
echo "=== wrap flick-7b ==="
CFG_ON="$TMPD/cfg-on"; mkdir -p "$CFG_ON"; printf '[decide]\nbackend = "none"\npoints = "wrap-7b"\n' > "$CFG_ON/kit.toml"
CFG_OFF="$TMPD/cfg-off"; mkdir -p "$CFG_OFF"; printf '[decide]\npoints = ""\n' > "$CFG_OFF/kit.toml"

# A flick stand-in that records what it was sent and answers with a fixed batch.
STUBBIN="$TMPD/flick-stub"
cat > "$STUBBIN" <<'STUB'
#!/usr/bin/env bash
cat > "$FLICK_STUB_REQ"
printf '%s\n' '{"backend":"jev","model":"m","latency_ms":9,"mode":"shadow","answers":{},"error":"","counts":{"answered":2,"denied":1,"error":0}}'
STUB
chmod +x "$STUBBIN"
REQ="$TMPD/req.json"

out="$(printf 'cand-a board enhance\n' | KIT_CONFIG_OPERATOR="$CFG_OFF" bash "$WRAP" flick-7b 2>&1)"; rc=$?
chk "point off: exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "point off: prints the off state" "$out" "flick wrap-7b: off"

out="$(KIT_CONFIG_OPERATOR="$CFG_ON" bash "$WRAP" flick-7b </dev/null 2>&1)"; rc=$?
chk "point on, no pairs: exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "point on, no pairs: prints the no-pairs row" "$out" "flick wrap-7b: no pairs"

: > "$REQ"
out="$(printf 'cand-a board enhance\ncand-b wrap new\ncand-c board none\n' | KIT_CONFIG_OPERATOR="$CFG_ON" WRAP_FLICK_BIN="$STUBBIN" FLICK_STUB_REQ="$REQ" bash "$WRAP" flick-7b 2>&1)"; rc=$?
chk "point on, pairs: exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the row carries the counts and backend" "$out" "flick wrap-7b: 2 answered, 1 denied, 0 error (jev)"
chk "flick got ONE request holding all three pairs" "$(jq -e '.point == "wrap-7b" and (.questions | length) == 3 and .questions[1] == {id:"p2",candidate:"cand-b",hit:"wrap",existing:"new"}' "$REQ" >/dev/null; echo $?)"

# The real flick, backend none: it fails open, and the row still names the outcome. FLICK_TEST=1 is the
# switch that lets flick honour the scratch config; the log dir is pinned so no real log line is written.
out="$(printf 'cand-a board enhance\n' | KIT_CONFIG_OPERATOR="$CFG_ON" KIT_CONFIG_ROOT="$TMPD/no-root" FLICK_TEST=1 DWARVES_KIT_LOG_DIR="$TMPD/flick-log" bash "$WRAP" flick-7b 2>&1)"; rc=$?
chk "real flick, backend none: exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "real flick, backend none: the row says error and the reason" "$out" "flick wrap-7b: 0 answered, 0 denied, 1 error (none, backend_none)"

# A missing flick is a visible error row, never a crash and never silence.
out="$(printf 'cand-a board enhance\n' | KIT_CONFIG_OPERATOR="$CFG_ON" WRAP_FLICK_BIN="$TMPD/does-not-exist" bash "$WRAP" flick-7b 2>&1)"; rc=$?
chk "missing flick: exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "missing flick: the row says no result" "$out" "flick wrap-7b: error (none, no result from flick)"

# The row the verb prints is the row the lint accepts.
row="$(printf 'cand-a board enhance\n' | KIT_CONFIG_OPERATOR="$CFG_ON" WRAP_FLICK_BIN="$STUBBIN" FLICK_STUB_REQ="$REQ" bash "$WRAP" flick-7b 2>&1)"
report="$(printf '## Wrap: t\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**FYI:**\n| Tag | Fact | Home |\n|---|---|---|\n| STATE | %s | |\n' "$row")"
out="$(printf '%s\n' "$report" | KIT_CONFIG_OPERATOR="$CFG_ON" bash "$KIT_DIR/lib/wrap/report-lint.sh" 2>&1)"; rc=$?
chk "the printed row satisfies report-lint" "$([ "$rc" -eq 0 ]; echo $?)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-flick7b: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-flick7b: all $PASS passed"
