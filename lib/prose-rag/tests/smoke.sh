#!/usr/bin/env bash
# prose-rag smoke test. Builds a 2-doc temp corpus (a distinctive "flarnium" doc
# and an unrelated "pasta" doc), indexes it, and checks retrieval + the relevance
# floor + the UserPromptSubmit hook. Runs the tool via `uv run` (it needs the
# project venv for fastembed + sqlite-vec).
#
# Run: bash tests/smoke.sh   Pass: "smoke: all N passed", exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
pr() { uv run --project "$DIR" python "$DIR/bin/prose-rag" "$@"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/corpus"
printf '# Flarnium protocol\n\nThe flarnium protocol uses zorbnik handshakes for quetzal alignment in distributed widgets.\n' > "$TMP/corpus/A.md"
printf '# Cooking pasta\n\nBoil water, add salt, cook the pasta for ten minutes, then drain and serve.\n' > "$TMP/corpus/B.md"
DB="$TMP/idx.db"
SEED="flarnium zorbnik quetzal protocol"
NOISE="xyzzy plugh frobnicate gibberish nonsense"

pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] index builds"
if pr index --corpus "$TMP/corpus" --db "$DB" 2>&1 | grep -q 'indexed 2 chunks'; then ok "indexed 2 chunks"; else no "index failed"; fi

echo "[2] seeded query: A.md is top-1 with high sim"
if pr query "$SEED" --db "$DB" --floor 0.65 --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d and "A.md" in d[0]["source"] and d[0]["sim"]>=0.70 else 1)'; then ok "A.md top-1, sim>=0.70"; else no "seeded retrieval wrong"; fi

echo "[3] relevance floor: gibberish returns nothing above 0.65 (negative control)"
out="$(pr query "$NOISE" --db "$DB" --floor 0.65 2>/dev/null)"
if grep -q 'no matches above floor' <<<"$out"; then ok "gibberish filtered out"; else no "noise leaked: $out"; fi

echo "[4] floor filter works: seeded at floor 0.99 returns nothing"
out="$(pr query "$SEED" --db "$DB" --floor 0.99 2>/dev/null)"
if grep -q 'no matches above floor' <<<"$out"; then ok "floor 0.99 filters all"; else no "floor not applied: $out"; fi

echo "[5] hook injects on a search match (gate bypassed; tests retrieval, A.md present)"
out="$(printf '{"prompt":"%s"}' "$SEED" | pr hook --db "$DB" --floor 0.65 --force --no-gate 2>/dev/null)"
if grep -q 'A.md' <<<"$out"; then ok "hook injected A.md"; else no "hook silent on-topic: $out"; fi

echo "[6] hook stays silent on a non-match (gate bypassed; negative control)"
out="$(printf '{"prompt":"%s"}' "$NOISE" | pr hook --db "$DB" --floor 0.65 --force --no-gate 2>/dev/null)"
if [[ -z "$out" ]]; then ok "hook silent on gibberish"; else no "hook injected noise: $out"; fi

echo "[7] hook never errors on empty/junk payload"
set +e; echo '{}' | pr hook --db "$DB" --force >/dev/null 2>&1; rc1=$?; echo 'notjson' | pr hook --db "$DB" --force >/dev/null 2>&1; rc2=$?; set -e
if [[ $rc1 -eq 0 && $rc2 -eq 0 ]]; then ok "empty/junk payload exit 0"; else no "rc1=$rc1 rc2=$rc2"; fi

echo "[8] master switch OFF by default: silent even on a recall prompt (opt-in)"
# env -u: hermetic against a host shell that exports the master switch (a consumer
# with the rollout flipped on would otherwise fail this opt-out check spuriously)
out="$(printf '{"prompt":"have I written about %s"}' "$SEED" | env -u PROSE_RAG_INJECT uv run --project "$DIR" python "$DIR/bin/prose-rag" hook --db "$DB" --floor 0.65 2>/dev/null)"
if [[ -z "$out" ]]; then ok "silent without PROSE_RAG_INJECT/--force"; else no "fired while opt-out: $out"; fi

echo "[9] recall gate skips an operational prompt with NO model load (plain python3, no fastembed)"
set +e; out="$(printf '{"prompt":"fix the failing test and commit it"}' | python3 "$DIR/bin/prose-rag" hook --db "$DB" --force 2>/dev/null)"; rc=$?; set -e
if [[ $rc -eq 0 && -z "$out" ]]; then ok "gated out before any embed import (rc=0, silent)"; else no "rc=$rc out=$out (gate did not short-circuit the import)"; fi

echo "[10] recall gate PASSES a recall-phrased prompt and injects the match"
out="$(printf '{"prompt":"have I written about %s"}' "$SEED" | pr hook --db "$DB" --floor 0.65 --force 2>/dev/null)"
if grep -q 'A.md' <<<"$out"; then ok "recall prompt passed gate + injected A.md"; else no "recall prompt did not inject: $out"; fi

echo "[11] long single-heading section is WINDOWED into multiple chunks, not truncated"
# One heading + ~40 table rows (~4000 chars) with a marker in the LAST row. The old
# chunker truncated at CHUNK_MAX (1500) and lost the tail (the VERDICTS.md bug).
{
  printf '# Big ledger\n\n| date | subject | verdict |\n|---|---|---|\n'
  for i in $(seq 1 39); do printf '| 2026-01-%02d | subject number %d with some padding text to lengthen the row | GO |\n' "$((i % 28 + 1))" "$i"; done
  printf '| 2026-02-01 | zzquokka final row marker | NO-GO |\n'
} > "$TMP/corpus/C.md"
DB2="$TMP/idx2.db"
out="$(pr index --corpus "$TMP/corpus/C.md" --db "$DB2" 2>&1)"
n="$(grep -oE 'indexed [0-9]+ chunks' <<<"$out" | grep -oE '[0-9]+' || echo 0)"
tailhit="$(pr query "zzquokka final row marker" --db "$DB2" --floor 0.30 2>/dev/null || true)"
if [[ "$n" -ge 3 ]] && grep -q 'C.md' <<<"$tailhit"; then ok "windowed into $n chunks, tail row retrievable"; else no "windowing broken: n=$n tailhit=$tailhit"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
