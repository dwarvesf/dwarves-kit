#!/usr/bin/env bash
# test-context-budget.sh -- sequence tests for the context-budget UserPromptSubmit
# hook (SPEC-255, percentage rewrite). Each step writes a synthetic transcript whose
# last main-chain assistant turn carries a chosen context size (and optionally a
# model id), runs the hook, and asserts whether it spoke (a systemMessage on stdout)
# or stayed silent.
#
# Default window is 200000 tokens; KIT_CTX_WARN_PCT=65 (130000 tokens) and
# KIT_CTX_STRONG_PCT=70 (140000 tokens) unless a case overrides them.
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
unset KIT_CTX_WARN_PCT KIT_CTX_STRONG_PCT KIT_CTX_WINDOW
mkdir -p "$HOME/.claude/projects/p"

PASS=0
FAIL=0

# transcript <file> <main_ctx> [model] [sidechain_ctx]: a user line, a main assistant
# turn split across cache fields, and optionally a later sidechain turn.
transcript() {
    local f="$1" ctx="$2" model="${3:-claude-sonnet-5}" side="${4:-}"
    {
        echo '{"type":"user","message":{"content":"hi"}}'
        jq -cn --argjson c "$ctx" --arg m "$model" '{type:"assistant", isSidechain:false,
            message:{model:$m, usage:{input_tokens:3, cache_creation_input_tokens:1000, cache_read_input_tokens:($c - 1003), output_tokens:50}}}'
        [ -n "$side" ] && jq -cn --argjson c "$side" '{type:"assistant", isSidechain:true,
            message:{usage:{input_tokens:0, cache_creation_input_tokens:0, cache_read_input_tokens:$c}}}'
    } > "$f"
}

# transcript_with_identity <file> <main_ctx> <bare_model> <identity_model_id>: same
# shape as transcript(), plus an earlier attachment line carrying the real modelId
# (the identity marker Claude Code actually writes; .message.model stays bare).
transcript_with_identity() {
    local f="$1" ctx="$2" model="$3" identity="$4"
    {
        echo '{"type":"user","message":{"content":"hi"}}'
        jq -cn --arg id "$identity" '{type:"attachment", isSidechain:false,
            attachment:{type:"model", identity:{modelId:$id}}}'
        jq -cn --argjson c "$ctx" --arg m "$model" '{type:"assistant", isSidechain:false,
            message:{model:$m, usage:{input_tokens:3, cache_creation_input_tokens:1000, cache_read_input_tokens:($c - 1003), output_tokens:50}}}'
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

echo "== Case 1: fixture percentages (default 200k window) =="
transcript "$T" 100000; step "1.1 50% (100k) silent"            silent s1 "$T"
transcript "$T" 132000; step "1.2 66% (132k) speaks once"        speak  s1 "$T"
transcript "$T" 132000; step "1.3 66% again, same threshold"     silent s1 "$T"
transcript "$T" 142000; step "1.4 71% (142k) speaks (escalation)" speak  s1 "$T"
transcript "$T" 142000; step "1.5 71% again, same threshold"     silent s1 "$T"

echo "== Case 2: /clear or /compact resets state =="
transcript "$T" 90000;  step "2.1 drop to 45% clears state" silent s1 "$T"
transcript "$T" 132000; step "2.2 re-cross 65% warns again" speak  s1 "$T"

echo "== Case 3: sidechain usage is ignored =="
T3="$HOME/.claude/projects/p/s3.jsonl"
transcript "$T3" 50000 claude-sonnet-5 900000; step "3.1 main 25%, sidechain 450% ignored" silent s3 "$T3"

echo "== Case 4: sessions keep separate state =="
T4="$HOME/.claude/projects/p/s4.jsonl"
transcript "$T4" 132000; step "4.1 other session at 66% still warns" speak s4 "$T4"

echo "== Case 5: fail open =="
step "5.1 missing transcript" silent s5 "$HOME/nope.jsonl"
printf 'not json\n' > "$HOME/bad.jsonl"; step "5.2 unparseable transcript" silent s5 "$HOME/bad.jsonl"
echo '{"type":"user"}' > "$HOME/nouse.jsonl"; step "5.3 no assistant turn yet" silent s5 "$HOME/nouse.jsonl"

echo "== Case 6: thresholds come from env =="
T6="$HOME/.claude/projects/p/s6.jsonl"
transcript "$T6" 60000
KIT_CTX_WARN_PCT=30 step "6.1 60k (30%) with KIT_CTX_WARN_PCT=30" speak s6 "$T6"

echo "== Case 7: window comes from the model id, or KIT_CTX_WINDOW overrides =="
T7="$HOME/.claude/projects/p/s7.jsonl"
transcript "$T7" 132000 "claude-opus-5-5"
step "7.1 non-1m model keeps 200k window, 66% speaks" speak s7 "$T7"
T7b="$HOME/.claude/projects/p/s7b.jsonl"
transcript "$T7b" 132000 "us.anthropic.claude-x-1m-v1:0"
step "7.2 1m model window: 132k is only 13%, silent" silent s7b "$T7b"
T7c="$HOME/.claude/projects/p/s7c.jsonl"
transcript "$T7c" 660000 "us.anthropic.claude-x-1m-v1:0"
step "7.3 1m model window: 660k is 66%, speaks" speak s7c "$T7c"
T7d="$HOME/.claude/projects/p/s7d.jsonl"
transcript "$T7d" 65000 "claude-sonnet-5"
KIT_CTX_WINDOW=100000 step "7.4 KIT_CTX_WINDOW=100000 override: 65k is 65%, speaks" speak s7d "$T7d"

echo "== Case 8: threshold 0 (warn) is advisory, threshold 1 (strong) is a directive =="
tone() {
    local label="$1" want="$2" session="$3" tr="$4" ctx
    ctx=$(jq -cn --arg s "$session" --arg t "$tr" '{session_id:$s, transcript_path:$t, prompt:"continue"}' \
        | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
    if printf '%s' "$ctx" | grep -q "$want"; then
        PASS=$((PASS + 1)); printf '  PASS %-50s has %s\n' "$label" "$want"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s missing %s\n' "$label" "$want"; printf '       ctx: %s\n' "$ctx"
    fi
}
T8="$HOME/.claude/projects/p/s8.jsonl"
transcript "$T8" 132000
tone "8.1 66%, warn threshold, advisory" "CONTEXT BUDGET" s8 "$T8"
transcript "$T8" 142000
tone "8.2 71%, strong threshold, directive" "CONTEXT CEILING" s8 "$T8"

echo "== Case 9: 1m window detection reads the identity attachment, not just .message.model =="
T9a="$HOME/.claude/projects/p/s9a.jsonl"
transcript_with_identity "$T9a" 130000 "claude-opus-5-5" "claude-opus-5-5[1m]"
step "9.1 bare model + [1m] identity at 130k: real 1M window, 13%, silent" silent s9a "$T9a"
T9b="$HOME/.claude/projects/p/s9b.jsonl"
transcript "$T9b" 130000 "claude-opus-5-5"
step "9.2 bare model, no identity, 130k: 200k window, 65%, speaks" speak s9b "$T9b"
T9c="$HOME/.claude/projects/p/s9c.jsonl"
transcript "$T9c" 250000 "claude-opus-5-5"
step "9.3 bare model, no identity, 250k: exceeds 200k, guard forces 1M window, silent" silent s9c "$T9c"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
