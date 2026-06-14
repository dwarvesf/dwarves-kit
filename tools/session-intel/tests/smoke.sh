#!/usr/bin/env bash
# cc-intel smoke. Fixture ledger/glossary/transcripts + stubbed cc-observe/repo-sweep
# (via env) exercise the digest assembly, synthesis (dup proposals), and repeat-detect
# (3-gram proposals), with negative controls. Stdlib only (python3).
#
# Run: bash tests/smoke.sh   Pass: "smoke: all N passed", exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/bin/cc-intel"
run(){ python3 "$BIN" "$@"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ledger with a normalized duplicate ("Same Origin Policy" vs "same-origin-policy")
LED="$TMP/ledger.md"
cat > "$LED" <<'EOF'
# learned-ledger
| field | values | note |
| 2026-06-01 | Same Origin Policy | concept | til | queued |
| 2026-06-02 | same-origin-policy | insight | til | queued |
| 2026-06-03 | Idempotency key | concept | glossary:web | queued |
EOF
GLO="$TMP/glossaries/web"; mkdir -p "$GLO"
printf '## Same-Origin Policy\n\nthe rule.\n' > "$GLO/GLOSSARY.md"

# clean ledger: distinct items only
LED_CLEAN="$TMP/ledger-clean.md"
cat > "$LED_CLEAN" <<'EOF'
# learned-ledger
| 2026-06-01 | Alpha thing | concept | til | queued |
| 2026-06-02 | Beta thing | insight | til | queued |
EOF

# transcripts with a repeated A=>B=>C 3-gram (x3 in one file)
bashev(){ printf '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$1"; }
TD="$TMP/transcripts/p1"; mkdir -p "$TD"
{ for _ in 1 2 3; do bashev "git fetch origin"; bashev "git rebase origin/main"; bashev "pnpm test"; done; } > "$TD/s.jsonl"
# clean transcripts: no repeats
TDC="$TMP/tclean/p1"; mkdir -p "$TDC"
{ bashev "ls"; bashev "pwd"; bashev "whoami"; bashev "date"; } > "$TDC/s.jsonl"

pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] synthesis flags a normalized duplicate across ledger + glossary"
out="$(run synthesis --ledger "$LED" --glossaries "$TMP/glossaries" 2>&1)"
if grep -qi 'merge candidate' <<<"$out" && grep -qi 'same.origin' <<<"$out"; then ok "dup flagged"; else no "synthesis: $out"; fi

echo "[2] synthesis clean: distinct items -> no candidates (negative control)"
out="$(run synthesis --ledger "$LED_CLEAN" --glossaries "$TMP/none" 2>&1)"
if grep -q 'no merge candidates' <<<"$out"; then ok "no false merge"; else no "false merge: $out"; fi

echo "[3] repeat-detect flags a 3-gram repeated >=3"
out="$(run repeat --transcripts "$TMP/transcripts" --min 3 2>&1)"
if grep -q 'git fetch origin => git rebase origin/main => pnpm test' <<<"$out"; then ok "repeat flagged"; else no "repeat: $out"; fi

echo "[4] repeat-detect clean: no repeats (negative control)"
out="$(run repeat --transcripts "$TMP/tclean" --min 3 2>&1)"
if grep -q 'no repeated sequences' <<<"$out"; then ok "no false repeat"; else no "false repeat: $out"; fi

echo "[5] run assembles a dated digest with all 4 sections + stub observe/sweep"
OUT="$TMP/out"
env CC_INTEL_DATE=2026-06-15 CC_INTEL_OBSERVE_CMD="echo OBSERVE_STUB" CC_INTEL_SWEEP_CMD="echo SWEEP_STUB" \
  python3 "$BIN" run --out "$OUT" --ledger "$LED" --glossaries "$TMP/glossaries" --transcripts "$TMP/transcripts" --min 3 >/dev/null 2>&1
F="$OUT/intel-2026-06-15.md"
if [[ -f "$F" ]] && grep -q 'cc-observe' "$F" && grep -q 'OBSERVE_STUB' "$F" && grep -q 'SWEEP_STUB' "$F" && grep -qi 'merge proposals' "$F" && grep -q 'extract-workflow' "$F" && grep -q 'git fetch origin' "$F"; then ok "digest complete"; else no "digest: $(head -25 "$F" 2>&1)"; fi

echo "[6] run degrades gracefully when observe/sweep fail"
OUT2="$TMP/out2"
env CC_INTEL_DATE=2026-06-15 CC_INTEL_OBSERVE_CMD="false" CC_INTEL_SWEEP_CMD="false" \
  python3 "$BIN" run --out "$OUT2" --ledger "$LED_CLEAN" --glossaries "$TMP/none" --transcripts "$TMP/tclean" --min 3 >/dev/null 2>&1
if grep -q '_unavailable_' "$OUT2/intel-2026-06-15.md"; then ok "unavailable sections marked"; else no "no degrade: $(head "$OUT2/intel-2026-06-15.md" 2>&1)"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
