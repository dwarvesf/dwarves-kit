#!/usr/bin/env bash
# TASK-008: SessionStart surfacing. surface_line shows staged-memory + skill-draft + 7-day spend;
# the hook emits valid additionalContext JSON; disabled -> nothing. Run: bash tests/test-surface.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

export SKILL_CURATOR_STATE_DIR="$TMP/state" SKILL_CURATOR_PROPOSALS_DIR="$TMP/proposals"
export SKILL_CURATOR_MEMORY_LEDGER="$TMP/learned-ledger.md"
mkdir -p "$SKILL_CURATOR_STATE_DIR" "$SKILL_CURATOR_PROPOSALS_DIR/draft-one"
: > "$SKILL_CURATOR_PROPOSALS_DIR/draft-one/SKILL.md"
# memory ledger: 2 queued rows + 1 flushed (not counted) + header/sep
{ printf '| date | item | kind | home | status |\n|---|---|---|---|---|\n'
  printf '| 2026-06-18 | a | concept | til | queued |\n'
  printf '| 2026-06-18 | b | insight | research | queued |\n'
  printf '| 2026-06-10 | c | decision | til | flushed |\n'; } > "$SKILL_CURATOR_MEMORY_LEDGER"
# cost ledger: one in-window row
jq -nc --arg ts "$(date +%Y-%m-%d)" '{ts:$ts,kind:"skill-review",staged:true,total_cost_usd:0.0034}' > "$SKILL_CURATOR_STATE_DIR/ledger.jsonl"

# shellcheck source=lib/surface.sh
. "$DIR/lib/surface.sh"

echo "[1] surface_counts = '2 1 <spend>' (memory queued / drafts / 7d spend)"
counts="$(surface_counts)"; set -- $counts
if [[ "$1" -eq 2 && "$2" -eq 1 ]]; then ok "counts: mem=$1 drafts=$2 spend=$3"; else no "counts wrong: '$counts'"; fi

echo "[2] surface_line mentions the three counts"
line="$(surface_line)"
if grep -q '2 staged memory' <<<"$line" && grep -q '1 skill drafts' <<<"$line" && grep -q '0.0034' <<<"$line"; then
  ok "line: $line"; else no "line wrong: $line"; fi

echo "[3] SessionStart hook emits valid additionalContext JSON"
out="$(bash "$DIR/hooks/sessionstart-surface.sh" < /dev/null)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)"
if [[ -n "$ctx" ]] && grep -q 'staged memory' <<<"$ctx"; then ok "valid JSON additionalContext"; else no "bad hook output: $out"; fi

echo "[4] disabled (SKILL_CURATOR_ENABLED=false) -> hook emits nothing (negative control)"
out_off="$(SKILL_CURATOR_ENABLED=false bash "$DIR/hooks/sessionstart-surface.sh" < /dev/null)"
if [[ -z "$out_off" ]]; then ok "disabled -> no surfacing"; else no "surfaced while disabled: $out_off"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-surface: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-surface: all $pass passed"
