#!/usr/bin/env bash
# test-batch-debt-warn.sh -- sequence tests for the batch-debt-warn PreToolUse hook.
# Each step feeds the hook a Bash tool payload and asserts whether it spoke
# (additionalContext on stdout) or stayed silent.
#
# Hermetic: HOME and the ledger root both point at fresh temp dirs, so the real
# ~/.local/state/dwarves-kit run logs are never read or written.
set -u

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$KIT_DIR/hooks/batch-debt-warn.sh"
[ -r "$HOOK" ] || { echo "ERROR: hook not found at $HOOK" >&2; exit 1; }

_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dwarves-kit-batch-debt-tests.XXXXXX")"
trap 'rm -rf "$_tmp"' EXIT
export HOME="$_tmp"
export CLAUDE_PLUGIN_ROOT="$KIT_DIR"
export KIT_LEDGER_DIR="$_tmp/ledger"
mkdir -p "$KIT_LEDGER_DIR/runs"

PASS=0
FAIL=0

# step <label> <expect: warn|silent> <session> [command]
step() {
    local label="$1" expect="$2" session="$3" cmd="${4:-gh pr merge 12 --squash}" out actual rc
    out=$(jq -cn --arg s "$session" --arg c "$cmd" \
        '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        actual="exit=$rc"
    elif printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        actual=warn
    elif [ -z "$out" ]; then
        actual=silent
    else
        actual=garbage
    fi
    if [ "$actual" = "$expect" ]; then
        PASS=$((PASS + 1)); printf '  PASS %-50s %s\n' "$label" "$actual"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected=%s actual=%s\n' "$label" "$expect" "$actual"
        [ -n "$out" ] && printf '       out: %s\n' "$out"
    fi
}

# seed_start <session>: a lane START dated after that session's first merge.
seed_start() {
    local since ts
    since=$(head -n 1 "$KIT_LEDGER_DIR/merge-watch/$1.log" | awk -F' \\| ' '{print $1}')
    ts=$(TZ=UTC date -u -r "$(( $(date +%s) + 60 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
         || date -u -d '+1 minute' +%Y-%m-%dT%H:%M:%SZ)
    [ "$ts" '>' "$since" ] || { echo "  SETUP FAIL: seeded START $ts not after $since" >&2; exit 1; }
    echo "$ts | START | lane=full classified=full type=feature repo=demo" \
        >> "$KIT_LEDGER_DIR/runs/feat-seeded.log"
}

echo "== Case 1: two merges, no START in the window -> warn on the second =="
step "1.1 first merge is always silent"        silent s-nostart
step "1.2 second merge with no START warns"    warn   s-nostart
step "1.3 warn fires once per session"         silent s-nostart

echo "== Case 2: a lane START inside the window keeps it silent =="
step "2.1 first merge"                         silent s-start
seed_start s-start
step "2.2 second merge after a START"          silent s-start

echo "== Case 3: non-merge commands never engage =="
step "3.1 one merge only"                      silent s-single
step "3.2 git push is not a merge"             silent s-single "git push -u origin feat/x"
step "3.3 merge inside prose does not engage"  silent s-single "git commit -m 'gh pr merge notes'"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
