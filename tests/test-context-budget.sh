#!/usr/bin/env bash
# test-context-budget.sh -- sequence tests for the context-budget UserPromptSubmit
# hook (SPEC-255). Each step writes a synthetic transcript whose last main-chain
# assistant turn carries a chosen context size, runs the hook, and asserts whether
# it spoke (a systemMessage on stdout) or stayed silent.
#
# Ported from the operator's dotfiles reference suite (tieubao/dotfiles
# tests/context-budget.sh); same 13 cases, kit hermetic-HOME style.
#
# Hermetic: HOME points at a fresh temp dir, so real state (~/.cache, ~/.claude)
# is never touched.
set -u

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$KIT_DIR/hooks/context-budget.sh"
[ -r "$HOOK" ] || { echo "ERROR: hook not found at $HOOK" >&2; exit 1; }

_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dwarves-kit-context-budget-tests.XXXXXX")"
trap 'rm -rf "$_tmp"' EXIT
export HOME="$_tmp"
unset KIT_CTX_WARN KIT_CTX_STEP
mkdir -p "$HOME/.claude/projects/p"

PASS=0
FAIL=0

# transcript <file> <main_ctx> [sidechain_ctx]: a user line, a main assistant turn
# split across cache fields, and optionally a later sidechain turn.
transcript() {
    local f="$1" ctx="$2" side="${3:-}"
    {
        echo '{"type":"user","message":{"content":"hi"}}'
        jq -cn --argjson c "$ctx" '{type:"assistant", isSidechain:false,
            message:{usage:{input_tokens:3, cache_creation_input_tokens:1000, cache_read_input_tokens:($c - 1003), output_tokens:50}}}'
        [ -n "$side" ] && jq -cn --argjson c "$side" '{type:"assistant", isSidechain:true,
            message:{usage:{input_tokens:0, cache_creation_input_tokens:0, cache_read_input_tokens:$c}}}'
    } > "$f"
}

# step <label> <expect: speak|silent> <session> <transcript>
step() {
    local label="$1" expect="$2" session="$3" tr="$4" out actual rc
    out=$(jq -cn --arg s "$session" --arg t "$tr" '{session_id:$s, transcript_path:$t, prompt:"continue"}' \
        | bash "$HOOK" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        actual="exit=$rc"
    elif printf '%s' "$out" | jq -e '.systemMessage and .hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        actual=speak
    elif [ -z "$out" ]; then
        actual=silent
    else
        actual="garbage"
    fi
    if [ "$actual" = "$expect" ]; then
        PASS=$((PASS + 1)); printf '  PASS %-50s %s\n' "$label" "$actual"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected=%s actual=%s\n' "$label" "$expect" "$actual"
        [ -n "$out" ] && printf '       out: %s\n' "$out"
    fi
}

T="$HOME/.claude/projects/p/s1.jsonl"

echo "== Case 1: bands =="
transcript "$T" 150000; step "1.1 150k under budget" silent s1 "$T"
transcript "$T" 250000; step "1.2 250k crosses 200k" speak s1 "$T"
transcript "$T" 290000; step "1.3 290k same band, no nag" silent s1 "$T"
transcript "$T" 310000; step "1.4 310k next band" speak s1 "$T"
transcript "$T" 320000; step "1.5 320k same band" silent s1 "$T"

echo "== Case 2: compact resets the band =="
transcript "$T" 90000;  step "2.1 drop to 90k" silent s1 "$T"
transcript "$T" 230000; step "2.2 re-cross 200k warns again" speak s1 "$T"

echo "== Case 3: sidechain usage is ignored =="
T3="$HOME/.claude/projects/p/s3.jsonl"
transcript "$T3" 50000 900000; step "3.1 main 50k, sidechain 900k" silent s3 "$T3"

echo "== Case 4: sessions keep separate state =="
T4="$HOME/.claude/projects/p/s4.jsonl"
transcript "$T4" 250000; step "4.1 other session at 250k still warns" speak s4 "$T4"

echo "== Case 5: fail open =="
step "5.1 missing transcript" silent s5 "$HOME/nope.jsonl"
printf 'not json\n' > "$HOME/bad.jsonl"; step "5.2 unparseable transcript" silent s5 "$HOME/bad.jsonl"
echo '{"type":"user"}' > "$HOME/nouse.jsonl"; step "5.3 no assistant turn yet" silent s5 "$HOME/nouse.jsonl"

echo "== Case 6: thresholds come from env =="
T6="$HOME/.claude/projects/p/s6.jsonl"
transcript "$T6" 120000
KIT_CTX_WARN=100000 step "6.1 120k with KIT_CTX_WARN=100000" speak s6 "$T6"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
