#!/usr/bin/env bash
# session-intel smoke. Fixture ledger/glossary/transcripts + stubbed session-observe/repo-sweep
# (via env) exercise the digest assembly, synthesis (dup proposals), and repeat-detect
# (3-gram proposals), with negative controls. Stdlib only (python3).
#
# Run: bash tests/smoke.sh   Pass: "smoke: all N passed", exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/bin/session-intel"
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

echo "[5] run assembles a dated digest with all 5 sections + stub observe/sweep/digest"
OUT="$TMP/out"
env SESSION_INTEL_DATE=2026-06-15 SESSION_INTEL_OBSERVE_CMD="echo OBSERVE_STUB" SESSION_INTEL_SWEEP_CMD="echo SWEEP_STUB" SESSION_INTEL_DIGEST_CMD="echo DIGEST_STUB" \
  python3 "$BIN" run --out "$OUT" --ledger "$LED" --glossaries "$TMP/glossaries" --transcripts "$TMP/transcripts" --min 3 >/dev/null 2>&1
F="$OUT/intel-2026-06-15.md"
if [[ -f "$F" ]] && grep -q 'Harness scorecard' "$F" && grep -q 'DIGEST_STUB' "$F" && grep -q 'session-observe' "$F" && grep -q 'OBSERVE_STUB' "$F" && grep -q 'SWEEP_STUB' "$F" && grep -qi 'merge proposals' "$F" && grep -q 'extract-workflow' "$F" && grep -q 'git fetch origin' "$F"; then ok "digest complete"; else no "digest: $(head -25 "$F" 2>&1)"; fi

echo "[6] run degrades gracefully when observe/sweep/digest fail"
OUT2="$TMP/out2"
env SESSION_INTEL_DATE=2026-06-15 SESSION_INTEL_OBSERVE_CMD="false" SESSION_INTEL_SWEEP_CMD="false" SESSION_INTEL_DIGEST_CMD="false" \
  python3 "$BIN" run --out "$OUT2" --ledger "$LED_CLEAN" --glossaries "$TMP/none" --transcripts "$TMP/tclean" --min 3 >/dev/null 2>&1
if [[ "$(grep -c '_unavailable_' "$OUT2/intel-2026-06-15.md")" -eq 3 ]]; then ok "observe+sweep+digest sections degraded (count 3)"; else no "degrade count != 3: $(grep -c '_unavailable_' "$OUT2/intel-2026-06-15.md")"; fi

# ID-226: benign idiom chain dropped, genuine non-benign chain kept
TDB="$TMP/tbenign/p1"; mkdir -p "$TDB"
{ for _ in 1 2 3; do bashev "git add ."; bashev "git commit -m wip"; bashev "git push origin"; done
  for _ in 1 2 3; do bashev "make build"; bashev "make deploy"; bashev "curl localhost"; done; } > "$TDB/s.jsonl"

echo "[7] repeat-detect filters benign idioms (ID-226) but keeps a genuine chain"
out="$(run repeat --transcripts "$TMP/tbenign" --min 3 2>&1)"
if ! grep -q 'git add . => git commit -m wip => git push origin' <<<"$out" \
   && grep -q 'make build => make deploy => curl localhost' <<<"$out"; then
  ok "benign dropped, genuine kept"; else no "benign filter: $out"; fi

# ID-227: ranked top-N merge proposals with a truncation note.
# 12 count-2 groups + 1 count-3 group ("Top Concept") -> 13 total, top-10 shown.
LED_MANY="$TMP/ledger-many.md"
{ echo "# led"
  for i in $(seq 1 12); do
    printf '| 2026-06-01 | Concept %02d | c | til | queued |\n' "$i"
    printf '| 2026-06-02 | concept-%02d | c | til | queued |\n' "$i"
  done
  printf '| 2026-06-01 | Top Concept | c | til | queued |\n'
  printf '| 2026-06-02 | top-concept | c | til | queued |\n'
  printf '| 2026-06-03 | TOP CONCEPT | c | til | queued |\n'
} > "$LED_MANY"

echo "[8] synthesis ranks by match count, caps at top-10, notes truncation (ID-227)"
out="$(run synthesis --ledger "$LED_MANY" --glossaries "$TMP/none" 2>&1)"
shown="$(grep -c '^- merge candidate:' <<<"$out" || true)"
first="$(grep '^- merge candidate:' <<<"$out" | head -1)"
if [[ "$shown" -eq 10 ]] \
   && grep -qi 'top concept' <<<"$first" \
   && grep -q '3 more merge candidate' <<<"$out"; then
  ok "ranked top-10 + truncation note"; else no "rank/top-N: shown=$shown first=$first :: $out"; fi

# ---- SPEC-200 I1: the digest's proposals reach the Learn gate as staged blocks ---------------
# Before this, synthesis/repeat printed prose INSIDE the digest, so a human had to retype a
# finding to act on it. A lead nobody can promote is a lead nobody actions.
STAGING="$TMP/backlog-staging.md"; BOARD="$TMP/BACKLOG.md"
printf '# Board\n\n| ID | Item | Notes | Status |\n|---|---|---|---|\n' > "$BOARD"

echo "[9] propose: synthesis + repeat land as ## [staged] blocks"
out="$(SESSION_INTEL_DATE=2026-01-01 run propose --ledger "$LED" --glossaries "$GLO" \
        --transcripts "$TMP/transcripts" --min 3 --staging "$STAGING" --backlog "$BOARD" 2>&1)"
if grep -q '^## \[staged\] Merge duplicate concept:' "$STAGING" \
   && grep -q '^- Source: session intel 2026-01-01 | synthesis' "$STAGING"; then
  ok "merge candidate staged with a citation"; else no "merge not staged: $(cat "$STAGING" 2>&1)"; fi
if grep -q '^## \[staged\] Extract a workflow for the repeated sequence:' "$STAGING" \
   && grep -q '^- Source: session intel 2026-01-01 | repeat-detect' "$STAGING"; then
  ok "repeat sequence staged with a citation"; else no "repeat not staged: $(cat "$STAGING")"; fi
grep -q 'board promote' <<<"$out" && ok "propose points at the human gate" || no "no gate hint: $out"

echo "[10] propose is idempotent (dedup vs staging + board)"
before="$(grep -c '^## \[staged\]' "$STAGING")"
SESSION_INTEL_DATE=2026-01-01 run propose --ledger "$LED" --glossaries "$GLO" \
  --transcripts "$TMP/transcripts" --min 3 --staging "$STAGING" --backlog "$BOARD" >/dev/null 2>&1
after="$(grep -c '^## \[staged\]' "$STAGING")"
[[ "$before" -eq "$after" ]] && ok "re-run stages nothing new ($after blocks)" \
  || no "re-run duplicated blocks ($before -> $after)"

echo "[11] NEGATIVE CONTROL: --dry-run writes nothing"
DRY="$TMP/dry-staging.md"
SESSION_INTEL_DATE=2026-01-01 run propose --ledger "$LED" --glossaries "$GLO" \
  --transcripts "$TMP/transcripts" --min 3 --staging "$DRY" --backlog "$BOARD" --dry-run \
  | grep -q '^## \[staged\]' && ok "dry-run prints blocks" || no "dry-run printed nothing"
[[ ! -f "$DRY" ]] && ok "dry-run wrote NO file (NEGATIVE CONTROL)" || no "dry-run created $DRY"

echo "[12] NEGATIVE CONTROL: propose NEVER writes the board (propose-don't-dispose)"
board_sha_before="$(shasum -a 256 "$BOARD" | cut -d' ' -f1)"
SESSION_INTEL_DATE=2026-01-02 run propose --ledger "$LED_MANY" --glossaries "$GLO" \
  --transcripts "$TMP/transcripts" --min 3 --staging "$STAGING" --backlog "$BOARD" >/dev/null 2>&1
board_sha_after="$(shasum -a 256 "$BOARD" | cut -d' ' -f1)"
[[ "$board_sha_before" == "$board_sha_after" ]] && ok "board byte-identical after propose" \
  || no "propose MUTATED the board"

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
