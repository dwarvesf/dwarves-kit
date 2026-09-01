#!/usr/bin/env bash
# CLI smoke for the RUST engine (the Python twin lives at ../../tests/smoke.sh).
# Exercises the real binary end to end: index/query/hook/arg-parse, incremental
# rerun, deletion pruning, the foreign-db clobber guard, and windowed-tail retrieval.
# Prereq: the model is in the hf cache (any prior `prose-rag index` run fetched it).
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/target/release/prose-rag"
[ -x "$BIN" ] || cargo build --release --manifest-path "$DIR/Cargo.toml"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
DB="$T/index.bin"
C="$T/corpus"
mkdir -p "$C"

pass=0
ok() { pass=$((pass + 1)); echo "ok $pass - $1"; }
fail() { echo "FAIL - $1" >&2; exit 1; }

cat > "$C/quokka.md" <<'EOF'
# Quokka husbandry field notes

The quokka enclosure needs brackish wallaby fodder and a shaded thermoregulation
platform, with weekly marsupial dental checks recorded in the husbandry ledger.
EOF
cat > "$C/other.md" <<'EOF'
# Grocery list

Milk, eggs, bread, coffee beans, and a replacement mop head for the kitchen.
EOF

# 1. index builds
out="$("$BIN" index --corpus "$C" --db "$DB" 2>&1)"
echo "$out" | grep -q "indexed" || fail "index did not report success: $out"
ok "index builds a fresh corpus"

# 2. incremental no-op rerun
out="$("$BIN" index --corpus "$C" --db "$DB" 2>&1)"
echo "$out" | grep -q "up to date" || fail "rerun re-embedded: $out"
ok "unchanged rerun is a no-op"

# 3. seeded query ranks the distinctive doc top-1
out="$("$BIN" query "quokka marsupial husbandry" --db "$DB" --floor 0 --k 2)"
echo "$out" | head -1 | grep -q "quokka.md" || fail "seeded doc not top-1: $out"
ok "seeded query top-1"

# 4. floor filters everything at 0.99
out="$("$BIN" query "quokka marsupial husbandry" --db "$DB" --floor 0.99)"
echo "$out" | grep -q "no matches above floor" || fail "floor 0.99 leaked: $out"
ok "floor filter"

# 5. --json emits a JSON array
"$BIN" query "quokka" --db "$DB" --floor 0 --json | head -1 | grep -q '^\[' \
  || fail "--json not JSON"
ok "--json output"

# 6-8. hook safety: junk payload / empty prompt / opt-in off -> silent exit 0
# (env -u: the session may export PROSE_RAG_INJECT=1 globally; these assert the OFF state)
for payload in 'notjson' '{}' '{"prompt":"have I written about quokkas?"}'; do
  out="$(echo "$payload" | env -u PROSE_RAG_INJECT "$BIN" hook --db "$DB")" \
    || fail "hook errored on: $payload"
  [ -z "$out" ] || fail "hook not silent on: $payload -> $out"
done
ok "hook silent on junk payload"
ok "hook silent on empty/keyless payload"
ok "hook silent without PROSE_RAG_INJECT (opt-in off)"

# 9. hook injects with --force --no-gate on-topic
out="$(echo '{"prompt":"quokka husbandry dental checks"}' | "$BIN" hook --db "$DB" --force --no-gate --floor 0)"
echo "$out" | grep -q "Relevant prior notes" || fail "forced hook did not inject: $out"
ok "forced hook injects"

# 10. deleting a file prunes it on the next index
rm -f "$C/other.md"
out="$("$BIN" index --corpus "$C" --db "$DB" 2>&1)"
echo "$out" | grep -q "1 removed" || fail "prune not reported: $out"
"$BIN" query "grocery mop head" --db "$DB" --floor 0 --k 5 | grep -q "other.md" \
  && fail "pruned doc still retrievable"
ok "deleted file pruned from index"

# 11. foreign/corrupt db file refuses loudly instead of clobbering
printf 'SQLite format 3\0garbage' > "$T/foreign.db"
if "$BIN" index --corpus "$C" --db "$T/foreign.db" 2>"$T/err.txt"; then
  fail "index overwrote a foreign db file"
fi
grep -q "refusing" "$T/err.txt" || fail "clobber guard message missing"
ok "foreign db clobber guard"

# 12. unknown flag exits 2
"$BIN" query "x" --bogus 2>/dev/null && fail "unknown flag accepted"
[ $? -eq 2 ] || fail "unknown flag wrong exit code"
ok "unknown flag rejected (exit 2)"

# 13. windowed long section: tail content is retrievable (the #768 parity check, e2e)
{
  echo "# Long ledger"
  echo
  for i in $(seq 1 40); do
    echo "| row $i | routine ledger padding entry with ordinary words | filler |"
  done
  echo "| row 41 | the xylophone amortization anomaly appears only in the tail | end |"
} > "$C/long.md"
"$BIN" index --corpus "$C" --db "$DB" >/dev/null 2>&1
out="$("$BIN" query "xylophone amortization anomaly" --db "$DB" --floor 0 --k 2)"
echo "$out" | grep -q "long.md" || fail "windowed tail not retrievable: $out"
ok "windowed tail content retrievable end-to-end"

# 14. unconfigured corpus (no --corpus, no PROSE_RAG_CORPUS) skips clean: exit 0, db untouched
cp "$DB" "$T/before.bin"
out="$(env -u PROSE_RAG_CORPUS "$BIN" index --db "$DB" 2>&1)" || fail "unconfigured index exited nonzero: $out"
echo "$out" | grep -q "no corpus configured" || fail "unconfigured skip message missing: $out"
cmp -s "$DB" "$T/before.bin" || fail "unconfigured index touched the db"
ok "unconfigured corpus skips clean (exit 0, db untouched)"

# 15. configured corpus with no markdown files is a real error (exit 1)
mkdir -p "$T/empty"
if env PROSE_RAG_CORPUS="$T/empty" "$BIN" index --db "$DB" 2>/dev/null; then
  fail "empty configured corpus exited 0"
fi
ok "configured-but-empty corpus errors (exit 1)"

echo "smoke: all $pass passed"
