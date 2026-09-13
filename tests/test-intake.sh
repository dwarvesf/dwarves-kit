#!/usr/bin/env bash
# test-intake.sh -- `bin/intake gate` / `lib/intake/intake.sh`: the scripted dedup gate that
# replaces the five hand-written prose copies the intake skills carried.
#
# Proves:
#   AC1 a decided subject hits: the fixture board row and the fixture verdict row are both
#       cited, exit 0
#   AC2 a fresh URL misses every store, hits is empty, exit 1
#   AC3 a seen URL hits the URL ledger through the configured command
#   AC4 a store with no key, a command not on PATH, and a registry path that does not exist
#       are each SKIPPED with a reason, never fatal
#   AC5 a boards row whose file is gone is ignored while its sibling row still hits
#   AC6 a board hit reports row_kind eval for a measured evaluation and skim for a skim
#   AC7 a project .kit.toml cannot supply any `[intake]` key (the root-only fence)
#   AC8 no argument exits 64, an unknown verb exits 64, --help exits 0
#
# Hermetic: HOME, REPO_ROOT, PRECEDENT_REGISTRY and DWARVES_KIT_LOG_DIR point into the temp
# tree, so the `owned` source (precedent's inventory surface) scans nothing real; the URL
# ledger, the note store and the pull-request search are PATH stubs, so no case reaches a
# network or the operator's own stores.
#
# Run: bash tests/test-intake.sh
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTAKE_BIN="$KIT_DIR/bin/intake"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

T="$(mktemp -d "${TMPDIR:-/tmp}/dk-intake-test.XXXXXX")"
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT

SEEN_URL="https://example.test/seen-link"
FRESH_URL="https://example.test/fresh-link-zzq"

# --- fixtures ---------------------------------------------------------------------------
mkdir -p "$T/stub" "$T/repo" "$T/log"

cat > "$T/board.md" <<'MD'
# Fixture board

| ID | Item | Notes & source | Status |
|---|---|---|---|
| FX-001 | quibblewax parser rewrite | [eval] quibblewax vs the owned parser, measured run | queued |
| FX-002 | zonkplume reader | skim only, no numbers taken | queued |
MD

cat > "$T/verdicts.md" <<'MD'
# VERDICTS fixture

| 2026-01-01 | quibblewax as the parser | NO-GO | content model mismatch | reopen-if: upstream adds a plugin api |
MD

cat > "$T/boards.txt" <<MD
# name  path
fixture  $T/board.md
ghostrepo  $T/does-not-exist/BACKLOG.md
MD

cat > "$T/stub/dgst" <<STUB
#!/usr/bin/env bash
# fixture URL ledger: one seen link, everything else new.
if [ "\${1:-}" = "check" ] && [ "\${2:-}" = "$SEEN_URL" ]; then
  echo '{"seen":true,"verdict":"skip","conclusion":"low density","date":"2026-01-02"}'
  exit 0
fi
echo '{"seen":false}'
exit 1
STUB

cat > "$T/stub/prose-rag" <<'STUB'
#!/usr/bin/env bash
echo '[]'
STUB

cat > "$T/stub/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$T/stub/dgst" "$T/stub/prose-rag" "$T/stub/gh"

_write_operator() {  # _write_operator <dir> <url_ledger cmd> [extra lines]
  mkdir -p "$1"
  {
    echo '[intake]'
    echo "url_ledger = \"$2\""
    echo 'notes = "prose-rag"'
    echo "verdicts = \"$T/verdicts.md\""
    echo "boards = \"$T/boards.txt\""
  } > "$1/kit.toml"
}
_write_operator "$T/op" "dgst"
mkdir -p "$T/op-empty"; printf '[intake]\n' > "$T/op-empty/kit.toml"

# run <operator-dir> <args...> -- the gate, fenced. Prints stdout; RC holds the exit code.
run() {
  local opdir="$1"; shift
  OUT="$(PATH="$T/stub:$PATH" HOME="$T" REPO_ROOT="$T/repo" \
        DWARVES_KIT_LOG_DIR="$T/log" PRECEDENT_REGISTRY="$T/no-registry.txt" \
        KIT_CONFIG_OPERATOR="$opdir" KIT_PROJECT_ROOT="${PROJ:-$T/repo}" \
        bash "$INTAKE_BIN" "$@" 2>"$T/err")"
  RC=$?
  printf '%s' "$OUT"
}

echo "=== AC1: a decided subject hits the board and the verdict ledger ==="
run "$T/op" gate "quibblewax parser" >/dev/null
assert "decided subject exits 0" "$RC"
assert "board row cited" "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "board")] | length > 0' >/dev/null; echo $?)"
assert "verdict row cited" "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "verdict")] | length > 0' >/dev/null; echo $?)"
assert "the board hit names the registered board" \
  "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "board") | .where] | index("fixture") != null' >/dev/null; echo $?)"

echo "=== AC2: a fresh URL misses every store ==="
run "$T/op" gate "$FRESH_URL" >/dev/null
assert "fresh URL exits 1" "$([ "$RC" -eq 1 ]; echo $?)"
assert "fresh URL produced no hits" "$(printf '%s' "$OUT" | jq -e '.hits | length == 0' >/dev/null; echo $?)"

echo "=== AC3: a seen URL hits the URL ledger ==="
run "$T/op" gate "$SEEN_URL" >/dev/null
assert "seen URL exits 0" "$RC"
assert "the hit kind is url" "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "url")] | length == 1' >/dev/null; echo $?)"
assert "the hit label carries the prior verdict" "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "url") | .label] | .[0] | test("verdict skip")' >/dev/null; echo $?)"

echo "=== AC4: a missing source is skipped, never fatal ==="
run "$T/op-empty" gate "$FRESH_URL" >/dev/null
assert "every key unset still exits 1 (a miss), not an error" "$([ "$RC" -eq 1 ]; echo $?)"
for k in url board verdict note pr; do
  assert "$k reported as skipped with a reason" \
    "$(printf '%s' "$OUT" | jq -e --arg k "$k" '[.skipped[] | select(.kind == $k) | select(.why != "")] | length == 1' >/dev/null; echo $?)"
done
assert "each of the five skipped sources printed one stderr line" \
  "$([ "$(grep -c 'intake gate: skipped' "$T/err")" -eq 5 ]; echo $?)"
# a command named but absent from PATH is the same non-fatal skip
_write_operator "$T/op-nocmd" "dgst-does-not-exist"
run "$T/op-nocmd" gate "$SEEN_URL" >/dev/null
assert "a url_ledger command not on PATH is skipped, not fatal" \
  "$(printf '%s' "$OUT" | jq -e '[.skipped[] | select(.kind == "url") | .why] | .[0] | test("not on PATH")' >/dev/null; echo $?)"

echo "=== AC5: a boards row whose file is gone is ignored, the sibling still hits ==="
run "$T/op" gate "quibblewax parser" >/dev/null
assert "the missing board row did not break the scan" "$RC"
assert "no hit claims the ghost board" \
  "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.where == "ghostrepo")] | length == 0' >/dev/null; echo $?)"

echo "=== AC6: row_kind separates a measured eval from a skim ==="
run "$T/op" gate "quibblewax parser" >/dev/null
assert "the eval row reports row_kind eval" \
  "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "board") | .row_kind] | index("eval") != null' >/dev/null; echo $?)"
run "$T/op" gate "zonkplume reader" >/dev/null
assert "the skim row reports row_kind skim" \
  "$(printf '%s' "$OUT" | jq -e '[.hits[] | select(.kind == "board") | .row_kind] | index("skim") != null' >/dev/null; echo $?)"

echo "=== AC7: a project .kit.toml cannot supply an [intake] key ==="
mkdir -p "$T/proj"
{ echo '[intake]'; echo "verdicts = \"$T/verdicts.md\""; echo "boards = \"$T/boards.txt\""; } > "$T/proj/.kit.toml"
PROJ="$T/proj" run "$T/op-empty" gate "quibblewax parser" >/dev/null
assert "the project override is ignored (still a miss)" "$([ "$RC" -eq 1 ]; echo $?)"
assert "board still reported as unset, not read from the project toml" \
  "$(printf '%s' "$OUT" | jq -e '[.skipped[] | select(.kind == "board") | .why] | .[0] | test("not set")' >/dev/null; echo $?)"
unset PROJ

echo "=== AC8: argument contract ==="
run "$T/op" gate >/dev/null 2>&1
assert "no argument exits 64" "$([ "$RC" -eq 64 ]; echo $?)"
run "$T/op" nosuchverb >/dev/null 2>&1
assert "an unknown verb exits 64" "$([ "$RC" -eq 64 ]; echo $?)"
run "$T/op" --help >/dev/null
assert "--help exits 0" "$RC"
assert "--help documents the gate verb" "$(printf '%s' "$OUT" | grep -q 'intake.sh gate'; echo $?)"

echo ""
echo "test-intake: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
