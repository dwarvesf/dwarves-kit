#!/usr/bin/env bash
# test-context-budget.sh -- sequence tests for the context-budget UserPromptSubmit
# hook (SPEC-255). Each step writes a synthetic transcript whose last main-chain
# assistant turn carries a chosen context size (and optionally a model id), runs the
# hook, and asserts whether it spoke (a systemMessage on stdout) or stayed silent.
#
# Default mode is absolute tokens: KIT_CTX_WARN_TOKENS=200000 and
# KIT_CTX_STRONG_TOKENS=250000, whatever the window. The legacy cases further down
# set KIT_CTX_WARN_PCT=65 / KIT_CTX_STRONG_PCT=70 explicitly, which switches the hook
# back to percent-of-window thresholds (default window 200000).
#
# Hermetic: HOME points at a fresh temp dir, so real state (~/.cache, ~/.claude)
# is never touched.
set -u

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$KIT_DIR/hooks/context-budget.sh"
[ -r "$HOOK" ] || { echo "ERROR: hook not found at $HOOK" >&2; exit 1; }

_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dwarves-kit-context-budget-tests.XXXXXX")" || exit 1
trap 'rm -rf "$_tmp"' EXIT
export HOME="$_tmp"
unset KIT_CTX_WARN_PCT KIT_CTX_STRONG_PCT KIT_CTX_WINDOW KIT_CTX_WARN_TOKENS KIT_CTX_STRONG_TOKENS ANTHROPIC_MODEL
# The state dir comes from the kit's data-path resolver: pin every input so a real host's XDG dirs
# or operator kit.toml are never read or written.
unset XDG_STATE_HOME XDG_CACHE_HOME XDG_CONFIG_HOME KIT_DATA_ROOT
export KIT_CONFIG_OPERATOR="$HOME/.config/dwarves-kit"
BUDGET_DIR="$(bash "$KIT_DIR/lib/config/data-path.sh" path cache context-budget)"
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

# nopct <label> <session> <transcript>: the hook speaks and neither message carries a '%'.
nopct() {
    local label="$1" session="$2" tr="$3" out
    out=$(jq -cn --arg s "$session" --arg t "$tr" '{session_id:$s, transcript_path:$t, prompt:"continue"}' \
        | bash "$HOOK" 2>/dev/null)
    if [ -n "$out" ] && ! printf '%s' "$out" | grep -q '%' && printf '%s' "$out" | grep -q 'k tokens'; then
        PASS=$((PASS + 1)); printf '  PASS %-50s tokens, no %%\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s want tokens and no %%\n' "$label"; printf '       out: %s\n' "$out"
    fi
}

echo "== Case A: absolute token thresholds by default (bare opus id, no window file) =="
TA="$HOME/.claude/projects/p/a1.jsonl"
transcript "$TA" 199999 claude-opus-5-5; step "A.1 199999 silent"                   silent a1 "$TA"
transcript "$TA" 200000 claude-opus-5-5; step "A.2 200000 warns once"               speak  a1 "$TA"
transcript "$TA" 210000 claude-opus-5-5; step "A.3 210k again, same threshold"      silent a1 "$TA"
transcript "$TA" 249999 claude-opus-5-5; step "A.4 249999 still under strong"       silent a1 "$TA"
transcript "$TA" 250000 claude-opus-5-5; step "A.5 250000 strong once"              speak  a1 "$TA"
transcript "$TA" 300000 claude-opus-5-5; step "A.6 300k again, same threshold"      silent a1 "$TA"
transcript "$TA" 150000 claude-opus-5-5; step "A.7 drop under 200k clears state"    silent a1 "$TA"
transcript "$TA" 200000 claude-opus-5-5; step "A.8 re-cross 200k warns again"       speak  a1 "$TA"

echo "== Case B: the old false ceilings no longer fire =="
TB="$HOME/.claude/projects/p/b1.jsonl"
transcript "$TB" 148000 claude-opus-5-5; step "B.1 148k (old 74% ceiling) silent"   silent b1 "$TB"
transcript "$TB" 154000 claude-opus-5-5; step "B.2 154k (old 77% ceiling) silent"   silent b1 "$TB"
TB3="$HOME/.claude/projects/p/b3.jsonl"
transcript "$TB3" 148000 claude-opus-5-5
KIT_CTX_WINDOW=200000 step "B.3 KIT_CTX_WINDOW alone keeps absolute mode, 148k silent" silent b3 "$TB3"
TB4="$HOME/.claude/projects/p/b4.jsonl"
transcript "$TB4" 200000 claude-opus-5-5
mkdir -p "$BUDGET_DIR"; echo 1000000 > "$BUDGET_DIR/b4.window"
step "B.4 1M window file ignored in absolute mode, 200k warns" speak b4 "$TB4"

echo "== Case C: messages print tokens, not a percentage =="
TC="$HOME/.claude/projects/p/c1.jsonl"
transcript "$TC" 205000 claude-opus-5-5; nopct "C.1 warn message" c1 "$TC"
transcript "$TC" 260000 claude-opus-5-5; nopct "C.2 strong message" c1 "$TC"
TC3="$HOME/.claude/projects/p/c3.jsonl"
transcript "$TC3" 205000 claude-opus-5-5; tone "C.3 warn names the 200k budget" "200k budget" c3 "$TC3"
transcript "$TC3" 260000 claude-opus-5-5; tone "C.4 strong names the 250k ceiling" "250k ceiling" c3 "$TC3"

echo "== Case D: token thresholds come from env, bad values fail open =="
TD="$HOME/.claude/projects/p/d1.jsonl"
transcript "$TD" 120000 claude-opus-5-5
KIT_CTX_WARN_TOKENS=100000 KIT_CTX_STRONG_TOKENS=150000 step "D.1 120k with warn=100k speaks" speak d1 "$TD"
TD2="$HOME/.claude/projects/p/d2.jsonl"
transcript "$TD2" 300000 claude-opus-5-5
KIT_CTX_WARN_TOKENS=250000 KIT_CTX_STRONG_TOKENS=200000 step "D.2 warn >= strong fails open" silent d2 "$TD2"
KIT_CTX_WARN_TOKENS=20k step "D.3 non-numeric warn fails open" silent d2 "$TD2"
KIT_CTX_WARN_TOKENS=0 step "D.4 zero warn fails open" silent d2 "$TD2"
KIT_CTX_WARN_TOKENS=200000 KIT_CTX_STRONG_TOKENS=200000 step "D.5 warn = strong fails open" silent d2 "$TD2"
TD6="$HOME/.claude/projects/p/d6.jsonl"
transcript "$TD6" 160000 claude-opus-5-5
KIT_CTX_WARN_TOKENS=100000 KIT_CTX_STRONG_TOKENS=150000 tone "D.6 STRONG_TOKENS=150000 at 160k escalates" "150k ceiling" d6 "$TD6"
TD7="$HOME/.claude/projects/p/d7.jsonl"
transcript "$TD7" 120000 claude-opus-5-5
KIT_CTX_WARN_TOKENS=090000 KIT_CTX_STRONG_TOKENS=0150000 tone "D.7 leading zeros read as base 10 (90k)" "90k budget" d7 "$TD7"

echo "== Case E: negative control, explicit percentage vars restore the old behavior =="
TE="$HOME/.claude/projects/p/e1.jsonl"
transcript "$TE" 148000 claude-opus-5-5
KIT_CTX_STRONG_PCT=70 KIT_CTX_WINDOW=200000 tone "E.1 148k is 74% of 200k: old CEILING returns" "CONTEXT CEILING" e1 "$TE"
TE2="$HOME/.claude/projects/p/e2.jsonl"
transcript "$TE2" 140000 claude-opus-5-5
KIT_CTX_WARN_PCT=65 KIT_CTX_WINDOW=200000 step "E.2 WARN_PCT alone switches to pct mode: 140k speaks" speak e2 "$TE2"
TE3="$HOME/.claude/projects/p/e3.jsonl"
transcript "$TE3" 65000 claude-opus-5-5
KIT_CTX_WARN_PCT=65 KIT_CTX_WINDOW=100001 step "E.3 pct rounds up: 65000 < 65% of 100001, silent" silent e3 "$TE3"
transcript "$TE3" 65001 claude-opus-5-5
KIT_CTX_WARN_PCT=65 KIT_CTX_WINDOW=100001 step "E.4 pct rounds up: 65001 >= 65% of 100001, speaks" speak e3 "$TE3"

# The legacy percentage cases below all run with the percentage vars set explicitly.
export KIT_CTX_WARN_PCT=65 KIT_CTX_STRONG_PCT=70

T="$HOME/.claude/projects/p/s1.jsonl"

echo "== Case 1 (legacy pct): fixture percentages (default 200k window) =="
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

T7e="$HOME/.claude/projects/p/s7e.jsonl"
transcript "$T7e" 140000 "claude-opus-5-5"
printf '{"model":"opus[1m]"}' > "$HOME/.claude/settings.json"
step "7.5 settings model opus[1m], bare transcript id: 140k is 14%, silent" silent s7e "$T7e"
rm -f "$HOME/.claude/settings.json"
T7f="$HOME/.claude/projects/p/s7f.jsonl"
transcript "$T7f" 140000 "claude-opus-5-5"
ANTHROPIC_MODEL="claude-opus-5-5[1m]" step "7.6 ANTHROPIC_MODEL carries [1m]: 140k is 14%, silent" silent s7f "$T7f"
T7g="$HOME/.claude/projects/p/s7g.jsonl"
transcript "$T7g" 250000 "claude-opus-5-5"
step "7.7 usage past 200k proves a bigger window: 250k is 25% of 1M, silent" silent s7g "$T7g"
# The live bug: opus-5-5 on a 1M window logs a bare id, 167k read as 83%.
T7h="$HOME/.claude/projects/p/s7h.jsonl"
transcript "$T7h" 167000 "claude-opus-5-5"
mkdir -p "$BUDGET_DIR"
echo 1000000 > "$BUDGET_DIR/s7h.window"
step "7.8 statusline window file 1M, bare id: 167k is 16%, silent" silent s7h "$T7h"
T7i="$HOME/.claude/projects/p/s7i.jsonl"
transcript "$T7i" 167000 "claude-opus-5-5"
echo junk > "$BUDGET_DIR/s7i.window"
step "7.9 junk window file ignored: falls back to 200k, 83% speaks" speak s7i "$T7i"

echo "== Case 8: threshold 0 (warn) is advisory, threshold 1 (strong) is a directive =="
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
# 9.3 (bare model, no identity, 250k exceeds 200k) dropped: same guard, same
# assertion as 7.7 -- #761's ">200k proves a bigger window" case.

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
