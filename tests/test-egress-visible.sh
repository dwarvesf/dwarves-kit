#!/usr/bin/env bash
# test-egress-visible.sh -- a failed LLM call stays fail-open but leaves one line in the
# egress-failures ledger, and /kit:start can summarize it. Also pins the per-session slop marker.
#
# Every `claude -p` caller (harvest, backlog-stage, skill-review, session-audit, reflect propose)
# is driven here with a STUBBED failing model command. Hermetic: the ledger root, HOME, and the
# staging files all live under one temp dir.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/kit-egress.XXXXXX")" || exit 1
trap 'mv -f "$T" "$T.discard" 2>/dev/null' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export KIT_LEDGER_DIR="$T/ledger"
EGRESS="$KIT_DIR/lib/telemetry/egress-fail.sh"
LOG="$KIT_LEDGER_DIR/egress-failures.log"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }
lines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
has_line() { [ -f "$LOG" ] && grep -Eq "^[0-9T:Z-]+ \| $1 \| $2" "$LOG"; }

# stub model commands: reads the prompt, then misbehaves
printf '#!/bin/sh\ncat >/dev/null\nexit 3\n' > "$T/fail.sh"
printf '#!/bin/sh\ncat >/dev/null\nexit 0\n' > "$T/empty.sh"
printf '#!/bin/sh\ncat >/dev/null\nprintf "[]"\n' > "$T/good.sh"
chmod +x "$T"/*.sh

# a transcript with forward intent so backlog-stage's prefilter lets it through
cat > "$T/t.jsonl" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"We decided to keep the ledger append-only. We should add a retry to the uploader later."}]}}
EOF
printf '{"transcript_path":"%s/t.jsonl","session_id":"s1"}' "$T" > "$T/payload.json"

echo "== helper: record + summary =="
[ -z "$(bash "$EGRESS" summary)" ]; check "summary is silent when the ledger is empty" $?
bash "$EGRESS" record harvest "extractor exit 3"
bash "$EGRESS" record harvest "empty | output
with newline"
bash "$EGRESS" record skill-review "empty claude output"
[ "$(lines)" = 3 ]; check "each record appends exactly one line (pipes and newlines stripped)" $?
has_line harvest "extractor exit 3"; check "line shape is 'ts | source | reason'" $?
printf '2020-01-01T00:00:00Z | session-audit | too old\n' >> "$LOG"
S="$(bash "$EGRESS" summary)"
case "$S" in *"harvest failed 2 times"*) r=0 ;; *) r=1 ;; esac; check "summary counts per source: $S" $r
case "$S" in *"skill-review failed 1 time "*) r=0 ;; *) r=1 ;; esac; check "summary uses the singular for one failure" $r
case "$S" in *session-audit*) r=1 ;; *) r=0 ;; esac; check "summary ignores entries older than the window" $r
[ "$(printf '%s\n' "$S" | wc -l | tr -d ' ')" = 1 ]; check "summary is ONE line" $?
: > "$LOG"

echo "== harvest: failing and empty extractor are ledgered, healthy one is not =="
run_harvest() { # run_harvest <extractor-script>
  rm -f "$T/hv/last-ledger"
  HARVEST_SYNC=1 HARVEST_STATE_DIR="$T/hv" HARVEST_MIN_INTERVAL=0 REPO_ROOT="$T/repo" \
    HARVEST_LEDGER="$T/learned.md" HARVEST_EXTRACTOR="$1" \
    bash "$KIT_DIR/hooks/harvest.sh" < "$T/payload.json" >/dev/null 2>&1
}
mkdir -p "$T/repo"
run_harvest "$T/fail.sh"; rc=$?
check "harvest exits 0 on a failing extractor (fail-open)" "$rc"
has_line harvest "extractor exit 3"; check "harvest ledgers 'extractor exit 3'" $?
run_harvest "$T/empty.sh"
has_line harvest "empty output"; check "harvest ledgers 'empty output'" $?
n="$(lines)"; run_harvest "$T/good.sh"
[ "$(lines)" = "$n" ]; check "a healthy extractor (valid '[]') adds no line" $?
[ ! -e "$T/learned.md" ]; check "harvest still stages nothing on failure" $?

echo "== backlog-stage: failing and empty extractor are ledgered =="
run_bs() {
  rm -rf "$T/bs"
  BACKLOG_STAGE_AUTO=1 BACKLOG_STAGE_SYNC=1 BACKLOG_STAGE_MIN_INTERVAL=0 BACKLOG_STAGE_STATE_DIR="$T/bs" \
    REPO_ROOT="$T/repo" BACKLOG_STAGE_STAGING="$T/staging.md" BACKLOG_STAGE_BACKLOG="$T/BACKLOG.md" \
    BACKLOG_STAGE_EXTRACTOR="$1" bash "$KIT_DIR/hooks/backlog-stage.sh" < "$T/payload.json" >/dev/null 2>&1
}
run_bs "$T/fail.sh"; rc=$?
check "backlog-stage exits 0 on a failing extractor (fail-open)" "$rc"
has_line backlog-stage "extractor exit 3"; check "backlog-stage ledgers 'extractor exit 3'" $?
run_bs "$T/empty.sh"
has_line backlog-stage "empty output"; check "backlog-stage ledgers 'empty output'" $?
n="$(lines)"; run_bs "$T/good.sh"
[ "$(lines)" = "$n" ]; check "a healthy backlog-stage extractor adds no line" $?

echo "== skill-review: an empty reviewer output is ledgered =="
export SKILL_CURATOR_STATE_DIR="$T/sc" SKILL_CURATOR_PROPOSALS_DIR="$T/proposals" SKILL_CURATOR_SKILLS_DIR="$T/skills"
mkdir -p "$SKILL_CURATOR_SKILLS_DIR"
jq -n --arg tp "$KIT_DIR/lib/skill-curator/tests/fixtures/sample-transcript.jsonl" '{session_id:"sess-x",transcript_path:$tp}' > "$T/sc-payload.json"
SKILL_CURATOR_REVIEWER_CMD="exit 3" bash "$KIT_DIR/lib/skill-curator/lib/reviewer-run.sh" "$T/sc-payload.json" >/dev/null 2>&1; rc=$?
check "reviewer exits 0 on a failing reviewer (fail-open)" "$rc"
has_line skill-review "empty claude output"; check "skill-review ledgers the empty output" $?

echo "== session-audit: a failing runtime is ledgered =="
SESSION_AUDIT_CMD="$T/fail.sh" "$KIT_DIR/lib/session/audit/bin/session-audit" run --out "$T/intel" --root "$T/none" >/dev/null 2>&1; rc=$?
check "session-audit exits 0 on a failing runtime (fail-open)" "$rc"
has_line session-audit "command exit 3"; check "session-audit ledgers 'command exit 3'" $?
SESSION_AUDIT_CMD="$T/empty.sh" "$KIT_DIR/lib/session/audit/bin/session-audit" run --out "$T/intel" --root "$T/none" >/dev/null 2>&1
has_line session-audit "empty or unparseable output"; check "session-audit ledgers an empty runtime output" $?

echo "== reflect propose: a failing interpreter is ledgered =="
cat > "$T/agg.json" <<'EOF'
{"window":{"days":30,"megas":null,"rids":["r1"],"n_rids":1},
 "signals":[{"id":"S1","lens":"gate-yield","figure":"x=1","rids":["r1"],"detail":{}}]}
EOF
LEARN_PROPOSE_INTERPRETER="$T/fail.sh" LEARN_PROPOSE_VERIFIER="$T/fail.sh" REFLECT_PROPOSE_RID=test-rid \
  BACKLOG_STAGE_STAGING="$T/p-staging.md" BACKLOG_STAGE_BACKLOG="$T/p-BACKLOG.md" \
  LEARN_PROPOSE_COCKPIT="$T/boards.txt" LEARN_PROPOSE_MEGAGOALS="$T/megagoals" \
  python3 "$KIT_DIR/lib/reflect/propose.py" --aggregate-file "$T/agg.json" >/dev/null 2>&1; rc=$?
check "reflect propose exits 0 on a failing interpreter (fail-open)" "$rc"
has_line reflect-propose "command exit 3"; check "reflect propose ledgers 'command exit 3'" $?

echo "== /kit:start wiring =="
grep -q 'lib/telemetry/egress-fail.sh summary' "$KIT_DIR/commands/start.md"; check "commands/start.md calls the egress summary" $?
S="$(bash "$EGRESS" summary)"
case "$S" in *"harvest failed"*"backlog-stage failed"*"skill-review failed"*"session-audit failed"*"reflect-propose failed"*) r=0 ;; *) r=1 ;; esac
check "summary names all five sources after the runs above: $S" $r

echo "== slop-cleaner: the session marker is keyed by session id =="
SLOP_DIR="$T/slopgit"; mkdir -p "$SLOP_DIR"; git -C "$SLOP_DIR" init -q 2>/dev/null
SA="egress-test-a-$$"; SB="egress-test-b-$$"
MA="/tmp/.dwarves-kit-session-start-$SA"; MB="/tmp/.dwarves-kit-session-start-$SB"
slop() { ( cd "$SLOP_DIR" && printf '{"stop_hook_active":false,"session_id":"%s"}' "$1" | env -u DWARVES_KIT_SESSION_MARKER bash "$KIT_DIR/hooks/slop-cleaner.sh" >/dev/null 2>&1 ); }
slop "$SA"; [ -f "$MA" ]; check "session A gets its own marker" $?
[ ! -f "$MB" ]; check "session B has no marker before its first Stop" $?
slop "$SB"; [ -f "$MB" ]; check "session B gets a separate marker" $?
[ -f "$MA" ]; check "session B's start left session A's marker alone" $?
STALE="/tmp/.dwarves-kit-session-start-stale-$$"; touch -t 202001010000 "$STALE"
slop "$SB"; [ ! -e "$STALE" ]; check "a marker older than a day is swept" $?
[ -f "$MB" ]; check "the live session's marker survives the sweep" $?
rm -f "$MA" "$MB" 2>/dev/null

echo
echo "egress-visible: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
