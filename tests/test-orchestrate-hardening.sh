#!/usr/bin/env bash
# test-orchestrate-hardening.sh -- orchfin-06 tiny sweep: three independent orchestrate.sh
# papercuts (ID-095/096/098), batched because each is too small for its own PR.
#
# 1. ID-095: `.orchestrate/*.stream.jsonl`/`*.session.log` retention. Verified reality: these
#    files are NOT unbounded growth (one per sub-goal-id, truncated per run), the real risk is a
#    captured transcript SITTING ON DISK past an age cap, possibly carrying secret-shaped text.
#    Proves BOTH mitigations: (a) `_prune_streams` removes files older than $STREAM_RETENTION_DAYS
#    and leaves fresh ones alone (the NEGATIVE CONTROL this sub-goal's Proof requires), and (b)
#    `_redact_secrets_file` masks a secret-shaped line in a REAL captured stream before it is
#    handed back to the caller.
# 2. ID-096: `_route`'s pre-flight `Model:` allowlist. An off-allowlist tier is rejected BEFORE any
#    session dispatches (mock `claude` never invoked), instead of dying mid-`claude -p` deep inside
#    a spawned session.
# 3. ID-098: the wave reap loop's happy-path `tmux kill-window` cleanup. A cleanly-landed
#    (shipped) sub-goal's pane window is killed, not left to accumulate across a multi-wave run.
#
# Run: bash tests/test-orchestrate-hardening.sh   (exit 0 = pass, 1 = fail)

set -uo pipefail
export TIER4_CLOSE=0
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
fails=0; total=0
pass() { total=$((total + 1)); echo "PASS $*"; }
fail() { total=$((total + 1)); echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Source it (not exec) so we can call internal helpers directly, same pattern as
# tests/test-model-routing.sh / tests/test-multiplexer.sh. The `[ "${BASH_SOURCE[0]}" = "$0" ]`
# main-guard at the bottom of orchestrate.sh keeps `main "$@"` from firing on source.
# shellcheck source=../lib/queue/orchestrate.sh
source "$ORCH"

# ============================ SECTION 1: ID-095a -- age/rotation cap (NEGATIVE CONTROL) ============================
D1="$TMP/retention"
mkdir -p "$D1/.orchestrate"
OLD_STREAM="$D1/.orchestrate/SG-OLD.stream.jsonl"
OLD_LOG="$D1/.orchestrate/SG-OLD.session.log"
FRESH_STREAM="$D1/.orchestrate/SG-FRESH.stream.jsonl"
echo '{"type":"assistant","text":"old transcript"}' > "$OLD_STREAM"
echo 'old plain session log' > "$OLD_LOG"
echo '{"type":"assistant","text":"fresh transcript"}' > "$FRESH_STREAM"
# Backdate the two OLD files to a fixed date in the past (year 2000) -- portable `touch -t` form
# used elsewhere in this repo's suite (tests/test-hooks.sh, tests/test-spec-reserve.sh), works
# identically under BSD (macOS) and GNU touch. FRESH_STREAM keeps its just-created mtime (now).
touch -t 200001010000 "$OLD_STREAM" "$OLD_LOG"

STREAM_RETENTION_DAYS=1 _prune_streams "$D1"

if [ ! -f "$OLD_STREAM" ] && [ ! -f "$OLD_LOG" ]; then
  pass "ID-095 [NEGATIVE CONTROL]: files older than the retention cap are pruned (both .stream.jsonl and .session.log)"
else
  fail "ID-095: an over-age file survived the sweep (OLD_STREAM exists=$([ -f "$OLD_STREAM" ] && echo yes || echo no), OLD_LOG exists=$([ -f "$OLD_LOG" ] && echo yes || echo no))"
fi
if [ -f "$FRESH_STREAM" ]; then
  pass "ID-095: a fresh (within-retention) file is left alone by the sweep"
else
  fail "ID-095: the sweep incorrectly removed a fresh, within-retention file"
fi

# ============================ SECTION 2: ID-095b -- secret redaction in a real captured stream ============================
D2="$TMP/redact-mega"
mkdir -p "$D2/goals"
cat > "$D2/ROADMAP.md" <<'EOF'
# Mega-goal: redaction fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$D2/POINTER_PROMPT.md"
echo "GOALFILE-MARKER-01 contract for SG-01" > "$D2/goals/01-first.md"

# Mock claude: prints a SYNTHETIC, non-secret token in the secret-shaped `sk-...` pattern (never a
# real credential on the command line -- the secret-guard hook would (rightly) block that; this is
# a fixture value a test file writes into a heredoc, per the sub-goal contract's secret-handling
# note) plus ordinary prose, then flips the box.
cat > "$TMP/claude-redact" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
printf 'ordinary line before\ntoken: sk-TESTFAKE0000000000000000\nordinary line after\n'
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$REDACT_RM" > "$REDACT_RM.tmp" && mv "$REDACT_RM.tmp" "$REDACT_RM"
EOF
chmod +x "$TMP/claude-redact"

REDACT_RM="$D2/ROADMAP.md" CAPTURE_TOKENS=1 CLAUDE_FLAGS="" TIER4_CLOSE=0 \
  CLAUDE_CMD="$TMP/claude-redact" bash "$ORCH" run "$D2" >/dev/null 2>&1

SLOG="$D2/.orchestrate/SG-01.stream.jsonl"
if [ -s "$SLOG" ]; then
  if grep -q 'sk-TESTFAKE' "$SLOG"; then
    fail "ID-095: the secret-shaped token is still present, UNREDACTED, in the stored stream ($SLOG)"; cat "$SLOG"
  elif grep -q '\[REDACTED\]' "$SLOG"; then
    pass "ID-095 [NEGATIVE CONTROL]: a secret-shaped line is redacted in the stored stream (raw token absent, [REDACTED] present)"
  else
    fail "ID-095: neither the raw token nor a [REDACTED] marker is present -- redaction did not run as expected"; cat "$SLOG"
  fi
else
  fail "ID-095: no stream file captured at $SLOG (fixture/harness problem, not a redaction result)"
fi

# ============================ SECTION 3: ID-096 -- Model: allowlist pre-flight rejection ============================
D3="$TMP/badmodel-mega"
mkdir -p "$D3/goals"
cat > "$D3/ROADMAP.md" <<'EOF'
# Mega-goal: bad-model fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$D3/POINTER_PROMPT.md"
cat > "$D3/goals/01-first.md" <<'EOF'
# SG-01
Model: sonet

GOALFILE-MARKER-01 contract for SG-01
EOF

BAD_MODEL_LOG="$TMP/badmodel-calls.log"; : > "$BAD_MODEL_LOG"
cat > "$TMP/claude-badmodel" <<EOF
#!/usr/bin/env bash
echo "INVOKED: \$*" >> "$BAD_MODEL_LOG"
EOF
chmod +x "$TMP/claude-badmodel"

berr="$TMP/badmodel.stderr"
CLAUDE_CMD="$TMP/claude-badmodel" TIER4_CLOSE=0 bash "$ORCH" run "$D3" >/dev/null 2>"$berr"

if [ ! -s "$BAD_MODEL_LOG" ]; then
  pass "ID-096 [NEGATIVE CONTROL]: an off-allowlist Model: tier never reaches dispatch (mock claude was NOT invoked)"
else
  fail "ID-096: dispatch happened anyway despite the invalid Model: tier"; cat "$BAD_MODEL_LOG"
fi
if grep -qi 'invalid Model:' "$berr"; then
  pass "ID-096: a clear pre-flight rejection message names the bad tier"
else
  fail "ID-096: no clear rejection message on stderr"; cat "$berr"
fi
b1=$(_sg_line "$D3/ROADMAP.md" SG-01)
case "$b1" in
  '- [ ] SG-01'*) pass "ID-096: SG-01's box stays unchecked (no false-complete on a rejected tier)" ;;
  *) fail "ID-096: SG-01's box was unexpectedly flipped ($b1)" ;;
esac

# ID-096 MULTI-WORD guard (TIER-4 dissent fix): the substring-membership bug this fix originally
# shipped ACCEPTED `Model: opus sonnet` because `" opus sonnet "` is a substring of the joined
# allowlist `" opus sonnet haiku "`. The exact-token enumeration must REJECT it pre-flight, same as
# any other off-allowlist value , mock claude never invoked, box unflipped, clear stderr message.
D3b="$TMP/badmodel-multiword-mega"
mkdir -p "$D3b/goals"
cat > "$D3b/ROADMAP.md" <<'EOF'
# Mega-goal: multi-word bad-model fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$D3b/POINTER_PROMPT.md"
cat > "$D3b/goals/01-first.md" <<'EOF'
# SG-01
Model: opus sonnet

GOALFILE-MARKER-01 contract for SG-01
EOF

MW_LOG="$TMP/badmodel-mw-calls.log"; : > "$MW_LOG"
cat > "$TMP/claude-badmodel-mw" <<EOF
#!/usr/bin/env bash
echo "INVOKED: \$*" >> "$MW_LOG"
EOF
chmod +x "$TMP/claude-badmodel-mw"

mwerr="$TMP/badmodel-mw.stderr"
CLAUDE_CMD="$TMP/claude-badmodel-mw" TIER4_CLOSE=0 bash "$ORCH" run "$D3b" >/dev/null 2>"$mwerr"

if [ ! -s "$MW_LOG" ]; then
  pass "ID-096 [NEGATIVE CONTROL, multi-word]: 'Model: opus sonnet' is REJECTED pre-flight (substring-membership bug fixed; mock claude NOT invoked)"
else
  fail "ID-096: multi-word 'opus sonnet' slipped through pre-flight and dispatched (substring bug)"; cat "$MW_LOG"
fi
if grep -qi 'invalid Model:' "$mwerr"; then
  pass "ID-096 [multi-word]: clear pre-flight rejection message for the multi-word value"
else
  fail "ID-096 [multi-word]: no clear rejection message on stderr"; cat "$mwerr"
fi
b1mw=$(_sg_line "$D3b/ROADMAP.md" SG-01)
case "$b1mw" in
  '- [ ] SG-01'*) pass "ID-096 [multi-word]: SG-01's box stays unchecked (no false-complete)" ;;
  *) fail "ID-096 [multi-word]: SG-01's box was unexpectedly flipped ($b1mw)" ;;
esac

# ============================ SECTION 4: ID-098 -- happy-path tmux kill-window cleanup ============================
mk_git_mega() {  # repo
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
}

# Minimal tmux mock (same shape as tests/test-multiplexer.sh's): logs every invocation, actually
# execs the new-window command line so a real `_pane-exec` re-entry + real claude mock run.
cat > "$TMP/tmux-mock" <<'MOCK'
#!/usr/bin/env bash
set -u
STATE="${TMUX_MOCK_STATE:?TMUX_MOCK_STATE not set}"
mkdir -p "$STATE"
printf '%s\n' "$*" >> "$STATE/calls.log"
sub="$1"; shift
case "$sub" in
  has-session)
    [ "$1" = -t ] && shift
    [ -f "$STATE/session.$1" ]; exit $? ;;
  new-session)
    name=""
    while [ "$#" -gt 0 ]; do case "$1" in -s) name="$2"; shift 2;; -n) shift 2;; *) shift;; esac; done
    : > "$STATE/session.$name" ;;
  new-window)
    session="" dir=""; cmd_argv=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -d) shift ;;
        -t) session="$2"; shift 2 ;;
        -n) shift 2 ;;
        -c) dir="$2"; shift 2 ;;
        --) shift; cmd_argv=("$@"); break ;;
        *) shift ;;
      esac
    done
    ( cd "$dir" 2>/dev/null || exit 1; "${cmd_argv[@]}" ) >/dev/null 2>&1 &
    ;;
  capture-pane) : ;;
  send-keys) : ;;
  kill-window)
    [ "$1" = -t ] && shift
    : ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$TMP/tmux-mock"

W="$TMP/id098-repo"; mk_git_mega "$W"
WM="$W/mega"; mkdir -p "$WM/goals"
cat > "$WM/ROADMAP.md" <<'EOF'
# Mega-goal: id-098 fixture
## Sub-goals
- [ ] SG-01 only , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WM/POINTER_PROMPT.md"
cat > "$WM/goals/01-SG-01.md" <<'EOF'
# SG-01: sub-goal
**Branch:** feat/sg-01

## Touches
- lib/id-098/**
EOF

cat > "$TMP/claude-id098" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
"$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
MOCK
chmod +x "$TMP/claude-id098"

STATE_098="$TMP/tmux-state-098"; mkdir -p "$STATE_098"
wrc=0
( export MULTIPLEXER=1 TMUX_CMD="$TMP/tmux-mock" TMUX_MOCK_STATE="$STATE_098" TMUX_SESSION=orch-id098 \
    WAVE_CAP=2 CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-id098" ORCH="$ORCH" MEGADIR="$WM"
  _wave_run "$WM" "$WM/ROADMAP.md" ) > "$TMP/id098.out" 2>&1 || wrc=$?

b1=$(_sg_line "$WM/ROADMAP.md" SG-01)
if [ "$wrc" = 0 ] && [ -z "$(printf '%s' "$b1" | grep -F '[ ]')" ]; then
  pass "ID-098 setup: wave landed SG-01 (box flipped, rc 0)"
else
  fail "ID-098 setup: wave did not land cleanly (rc=$wrc box='$b1')"; cat "$TMP/id098.out"
fi

if grep -q 'new-window .*-n SG-01' "$STATE_098/calls.log" 2>/dev/null; then
  pass "ID-098 setup: tmux new-window spawned SG-01's pane"
else
  fail "ID-098 setup: no new-window call for SG-01"; cat "$STATE_098/calls.log" 2>/dev/null
fi

if grep -q "kill-window -t orch-id098:SG-01" "$STATE_098/calls.log" 2>/dev/null; then
  pass "ID-098 [Done=]: a cleanly-landed (shipped) sub-goal's window is killed on the happy path (no orphaned pane)"
else
  fail "ID-098: no kill-window call for SG-01's completed pane -- window would be left orphaned"; cat "$STATE_098/calls.log" 2>/dev/null
fi

echo ""
echo "=== $((total - fails))/$total passed, $fails failed ==="
[ "$fails" -eq 0 ]
