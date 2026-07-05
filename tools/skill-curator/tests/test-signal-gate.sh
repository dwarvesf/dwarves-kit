#!/usr/bin/env bash
# Signal-marker pre-gate (opt-in via signal_gate): a summary with zero cheap signal markers is
# skipped BEFORE the model call, preserving quota. Gate defaults OFF (behaviour unchanged); a
# summary WITH markers still runs the model (recall guard, tested per marker CATEGORY so a regex
# regression on one half of the pattern can't hide). Mock the model via CC_SI_REVIEWER_CMD; a
# `touch $INVOKED` proves whether the reviewer ran. Run: bash tests/test-signal-gate.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$DIR/lib/reviewer-run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

export CC_SI_STATE_DIR="$TMP/state"
export CC_SI_PROPOSALS_DIR="$TMP/proposals"
export CC_SI_SKILLS_DIR="$TMP/skills"; mkdir -p "$CC_SI_SKILLS_DIR"
LEDGER="$CC_SI_STATE_DIR/ledger.jsonl"
INVOKED="$TMP/INVOKED"

mk_env(){ jq -nc --arg r "$1" --argjson c "${2:-0.001}" \
  '{type:"result",subtype:"success",total_cost_usd:$c,result:$r,usage:{input_tokens:1000,output_tokens:200}}'; }
ENV_JSON="$TMP/env.json"; mk_env '{"draft":null,"reason":"no signal"}' 0.001 > "$ENV_JSON"
MOCK="touch $INVOKED; cat $ENV_JSON"        # reviewer mock: records that it ran, returns a null draft
reset(){ rm -rf "$CC_SI_PROPOSALS_DIR" "$CC_SI_STATE_DIR" "$INVOKED" 2>/dev/null; }
ledger_has(){ [ -f "$LEDGER" ] && jq -e "$1" "$LEDGER" >/dev/null 2>&1; }

# A user+assistant turn text becomes the summary via transcript_compact.
mk_txn(){ # $1 user text, $2 assistant text, $3 tag -> a .jsonl transcript path
  local f="$TMP/txn-$3.jsonl"
  { jq -nc --arg t "$1" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]}}'
    jq -nc --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
  } > "$f"; printf '%s' "$f"
}
# keeps <tag> <text>: gate ON, a summary carrying <text> must NOT be skipped (reviewer runs).
keeps(){
  reset
  pay "$(mk_txn "$2" "acknowledged" "$1")" > "$TMP/p.json"
  CC_SI_SIGNAL_GATE=true CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$TMP/p.json"
  [[ -e "$INVOKED" ]] && ok "recall [$1]: kept a '$1' session (model ran)" || no "recall [$1]: '$2' was WRONGLY gated"
}
NO_MARK="$(mk_txn "deploy the worker to production" "deployed the worker to production" nomark)"
pay(){ jq -nc --arg tp "$1" '{session_id:"sig-test",transcript_path:$tp}'; }

echo "[1] gate DEFAULT-OFF: a marker-free summary STILL runs the reviewer (behaviour unchanged)"
reset
pay "$NO_MARK" > "$TMP/p.json"
CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$TMP/p.json"
if [[ -e "$INVOKED" ]]; then ok "gate off -> reviewer ran on marker-free session"; else no "gate off but reviewer skipped"; fi

echo "[2] gate ON + marker-free summary: reviewer SKIPPED, ledger note=skip-no-signal, exit 0"
reset
pay "$NO_MARK" > "$TMP/p.json"
CC_SI_SIGNAL_GATE=true CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$TMP/p.json"; rc=$?
if [[ ! -e "$INVOKED" ]] && [[ $rc -eq 0 ]] && ledger_has 'select(.staged==false and .note=="skip-no-signal" and .total_cost_usd==0)'; then
  ok "gate on -> marker-free session skipped before model, ledgered skip-no-signal"; else no "gate did not skip marker-free session (rc=$rc, invoked=$([ -e "$INVOKED" ] && echo yes || echo no))"; fi

echo "[3] recall guard PER MARKER CATEGORY: each category of the built-in regex must keep a session"
# One representative token per logically-distinct half of the pattern, isolated so a regex
# regression on any single category is caught (not masked by co-occurring markers).
keeps correction  "no, that is the wrong approach"
keeps frustration "stop doing that, it is too verbose"
keeps technique   "turns out the root cause was a stale cache"
keeps fix         "the fix was a rebuild; here is the workaround"
keeps debug       "spent an hour on debug before I figured out the issue"
keeps skill-patch "the loaded skill was outdated and missing a step"

echo "[4] gate ON + marker-free: nothing staged under proposals/ (negative control)"
reset
pay "$NO_MARK" > "$TMP/p.json"
CC_SI_SIGNAL_GATE=true CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$TMP/p.json"
if [[ -z "$(find "$CC_SI_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]]; then ok "gated session stages nothing"; else no "gated session staged a draft"; fi

echo "[5] custom signal_markers regex is honoured (override seam)"
reset
pay "$NO_MARK" > "$TMP/p.json"   # 'deploy...' matches a custom 'deploy' marker -> should RUN
CC_SI_SIGNAL_GATE=true CC_SI_SIGNAL_MARKERS="deploy" CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$TMP/p.json"
if [[ -e "$INVOKED" ]]; then ok "custom marker 'deploy' matched -> reviewer ran"; else no "custom signal_markers override ignored"; fi

echo "[6] gate runs BEFORE the lock: a marker-free run skips even while another holds the lock"
# Discriminator: if the gate were placed AFTER si_acquire_lock, a held lock would divert to the
# single-flight path (no skip-no-signal row). A skip-no-signal row proves the gate short-circuited
# before the lock was ever consulted.
reset
mkdir -p "$CC_SI_STATE_DIR/state/reviewer.lock.d"
sleep 30 & HOLDER=$!; echo "$HOLDER" > "$CC_SI_STATE_DIR/state/reviewer.lock.d/pid"
pay "$NO_MARK" > "$TMP/p.json"
CC_SI_SIGNAL_GATE=true CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$TMP/p.json"; rc=$?
if [[ ! -e "$INVOKED" ]] && [[ $rc -eq 0 ]] && ledger_has 'select(.note=="skip-no-signal")'; then
  ok "gate short-circuits before the lock (skip-no-signal despite a held lock)"; else no "gate did not run before the lock (rc=$rc)"; fi
kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true

echo "[7] empty transcript short-circuits BEFORE the gate (no skip-no-signal, no model call)"
# has_signal_markers("") is also false, so if the empty-check were removed the gate would ledger a
# skip-no-signal for an empty session. Asserting NO such row proves the empty-check still wins.
reset
PE="$TMP/payload-empty.json"; jq -n '{session_id:"s",transcript_path:"/nonexistent.jsonl"}' > "$PE"
CC_SI_SIGNAL_GATE=true CC_SI_REVIEWER_CMD="$MOCK" bash "$RUN" "$PE"
if [[ ! -e "$INVOKED" ]] && ! ledger_has 'select(.note=="skip-no-signal")'; then
  ok "empty transcript returns before the gate (no skip-no-signal row)"; else no "gate fired on an empty transcript"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-signal-gate: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-signal-gate: all $pass passed"
