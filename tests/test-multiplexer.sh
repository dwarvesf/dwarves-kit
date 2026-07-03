#!/usr/bin/env bash
# test-multiplexer.sh (SPEC-119, ADR-0032 s4): pins the opt-in multiplexer wiring in `_wave_run`.
# MULTIPLEXER=1 spawns each wave session into a tmux window (`tmux new-window`) instead of a plain
# background job, so `tmux capture-pane` returns its live output and `tmux send-keys` can reach it.
# MULTIPLEXER=0 (default, unset) must be BYTE-UNCHANGED: `_wave_run` never invokes `$TMUX_CMD` --
# the load-bearing negative control this whole sub-goal's Proof rests on.
#
# No real tmux server is used (headless-safe, no CI dependency): `$TMP/tmux-mock` fakes just enough
# of has-session/new-session/new-window/capture-pane/send-keys/kill-window to prove the wiring --
# `new-window` actually execs the given command line (a real `_pane-exec` re-entry into
# orchestrate.sh, a REAL subprocess, not a test-only stub) and redirects its output to a per-window
# log file that `capture-pane` reads back, so the whole spawn/capture chain is exercised for real.
set -uo pipefail
export TIER4_CLOSE=0
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/orchestrate.sh
source "$KIT/lib/orchestrate.sh"
ORCH="$KIT/lib/orchestrate.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_git_mega() {  # repo
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
}

make_goal() {  # megadir id [glob]
  local mg="$1" id="$2" glob="${3:-}"
  mkdir -p "$mg/goals"
  {
    printf '# %s: sub-goal\n' "$id"
    printf '**Branch:** feat/%s\n' "$(printf '%s' "$id" | tr 'A-Z' 'a-z')"
    if [ -n "$glob" ]; then printf '\n## Touches\n- %s\n' "$glob"; fi
  } > "$mg/goals/${id#SG-}-${id}.md"
}

# Fake tmux (no real server): implements has-session/new-session/new-window/capture-pane/
# send-keys/kill-window over plain files under $TMUX_MOCK_STATE. `new-window` actually EXECS the
# given command line in the background (mirroring how a real tmux server detaches a pane from the
# invoking `tmux` CLI call) and redirects its output to a per-window log `capture-pane` reads back.
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
    [ -f "$STATE/session.$1" ]
    exit $?
    ;;
  new-session)
    name=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -s) name="$2"; shift 2 ;;
        -n) shift 2 ;;
        *) shift ;;
      esac
    done
    : > "$STATE/session.$name"
    ;;
  new-window)
    session="" id="" dir=""; cmd_argv=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -d) shift ;;
        -t) session="$2"; shift 2 ;;
        -n) id="$2"; shift 2 ;;
        -c) dir="$2"; shift 2 ;;
        --) shift; cmd_argv=("$@"); break ;;             # fixed form: everything after -- is argv
        *) cmd_argv=("$1"); shift ;;                     # legacy single-string form (kept for the
                                                         # injection positive-control below)
      esac
    done
    : > "$STATE/session.$session"
    panelog="$STATE/pane.$session.$id.log"
    : > "$panelog"
    if [ "${#cmd_argv[@]}" -gt 1 ]; then
      # Real tmux with a multi-arg command execs the argv DIRECTLY -- no `$SHELL -c`, no second
      # parse. Modelled by running the array as-is (the fix's whole guarantee).
      ( cd "$dir" 2>/dev/null || exit 1; "${cmd_argv[@]}" ) > "$panelog" 2>&1 &
    else
      # Real tmux with a single command STRING hands it to `$SHELL -c` -- a second shell parse,
      # i.e. an eval. This is the pre-fix sink the injection positive-control exercises.
      ( cd "$dir" 2>/dev/null || exit 1; eval "${cmd_argv[0]:-}" ) > "$panelog" 2>&1 &
    fi
    ;;
  capture-pane)
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -p) shift ;;
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    cat "$STATE/pane.${target%%:*}.${target##*:}.log" 2>/dev/null
    ;;
  send-keys)
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        *) break ;;
      esac
    done
    printf '%s\n' "$*" >> "$STATE/keys.${target%%:*}.${target##*:}.log"
    ;;
  kill-window)
    [ "$1" = -t ] && shift
    : "$1"
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$TMP/tmux-mock"

# A poisoned tmux: any invocation is itself the test failure (records a sentinel + exits nonzero).
# Used under the default MULTIPLEXER=0 to prove the off-path never touches tmux at all.
cat > "$TMP/tmux-poison" <<'MOCK'
#!/usr/bin/env bash
echo "POISON: tmux invoked with: $*" >> "${TMUX_POISON_LOG:?}"
exit 99
MOCK
chmod +x "$TMP/tmux-poison"

# Claude mock: flips its sub-goal's box (via the locked flip CLI, matching the real wave-session
# contract) and prints a recognizable line, so capture-pane's returned content is checkable.
cat > "$TMP/claude-mux" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
echo "MUX-HELLO from $id"
bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
exit 0
MOCK
chmod +x "$TMP/claude-mux"

# ============================ (A) MULTIPLEXER=1: spawn + capture-pane visibility ============================
A="$TMP/mux-on-repo"
mk_git_mega "$A"
AM="$A/mega"; mkdir -p "$AM"
cat > "$AM/ROADMAP.md" <<'EOF'
# Mega-goal: mux-on
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$AM/POINTER_PROMPT.md"
make_goal "$AM" SG-01 "lib/wave-a/**"
make_goal "$AM" SG-02 "lib/wave-b/**"

STATE_A="$TMP/tmux-state-a"; mkdir -p "$STATE_A"
arc=0
( export MULTIPLEXER=1 TMUX_CMD="$TMP/tmux-mock" TMUX_MOCK_STATE="$STATE_A" TMUX_SESSION=orch-test-a \
    WAVE_CAP=2 CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-mux" ORCH="$ORCH" MEGADIR="$AM"
  _wave_run "$AM" "$AM/ROADMAP.md" ) > "$TMP/a.out" 2>&1 || arc=$?

[ "$arc" = 0 ] && pass "mux-on: _wave_run rc 0" || { fail "mux-on: _wave_run rc=$arc"; cat "$TMP/a.out"; }
b1=$(_sg_line "$AM/ROADMAP.md" SG-01); b2=$(_sg_line "$AM/ROADMAP.md" SG-02)
case "$b1" in '- [x] SG-01'*) pass "mux-on: SG-01 box flipped" ;; *) fail "mux-on: SG-01 not flipped ($b1)" ;; esac
case "$b2" in '- [x] SG-02'*) pass "mux-on: SG-02 box flipped" ;; *) fail "mux-on: SG-02 not flipped ($b2)" ;; esac

# spawn: a tmux new-window call happened per sub-goal, naming the window after its id.
if grep -q 'new-window .*-n SG-01' "$STATE_A/calls.log" 2>/dev/null; then
  pass "mux-on: tmux new-window spawned a pane for SG-01"
else
  fail "mux-on: no new-window call for SG-01"; cat "$STATE_A/calls.log" 2>/dev/null
fi
if grep -q 'new-window .*-n SG-02' "$STATE_A/calls.log" 2>/dev/null; then
  pass "mux-on: tmux new-window spawned a pane for SG-02"
else
  fail "mux-on: no new-window call for SG-02"
fi

# receive: capture-pane against each pane returns that session's REAL live output.
cap1=$(TMUX_MOCK_STATE="$STATE_A" "$TMP/tmux-mock" capture-pane -p -t "orch-test-a:SG-01")
cap2=$(TMUX_MOCK_STATE="$STATE_A" "$TMP/tmux-mock" capture-pane -p -t "orch-test-a:SG-02")
case "$cap1" in *"MUX-HELLO from SG-01"*) pass "mux-on: capture-pane SG-01 returns its live output" ;; *) fail "mux-on: capture-pane SG-01 empty/wrong: '$cap1'" ;; esac
case "$cap2" in *"MUX-HELLO from SG-02"*) pass "mux-on: capture-pane SG-02 returns its live output" ;; *) fail "mux-on: capture-pane SG-02 empty/wrong: '$cap2'" ;; esac

# control: _pane_send_keys reaches the right pane (send-keys wiring, the "intervene" half).
( export TMUX_CMD="$TMP/tmux-mock" TMUX_MOCK_STATE="$STATE_A" TMUX_SESSION=orch-test-a
  _pane_send_keys "$AM" SG-01 "hello-operator" ) >/dev/null 2>&1
if grep -q 'hello-operator' "$STATE_A/keys.orch-test-a.SG-01.log" 2>/dev/null; then
  pass "mux-on: send-keys reached SG-01's pane"
else
  fail "mux-on: send-keys did not land in SG-01's pane log"
fi

# ============================ (B) MULTIPLEXER=0 (default): off-path byte-unchanged NC ============================
# Same shape as (A) (two disjoint sub-goals, WAVE_CAP=2) but MULTIPLEXER is left UNSET (the
# operator default) and TMUX_CMD points at a POISONED tmux: any invocation is itself a failure. If
# _wave_run's default path ever touched tmux, this NC would catch it; the existing (unedited)
# tests/test-orchestrate-wavefront.sh passing is the complementary byte-unchanged regression proof.
B="$TMP/mux-off-repo"
mk_git_mega "$B"
BM="$B/mega"; mkdir -p "$BM"
cat > "$BM/ROADMAP.md" <<'EOF'
# Mega-goal: mux-off
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$BM/POINTER_PROMPT.md"
make_goal "$BM" SG-01 "lib/wave-a/**"
make_goal "$BM" SG-02 "lib/wave-b/**"

POISON_LOG="$TMP/poison.log"; : > "$POISON_LOG"
brc=0
( # MULTIPLEXER deliberately left at its already-sourced default (0/off) -- an "unset" here would
  # be an unbound-variable error under this test's own `set -u`, and is not what an operator's
  # default (never having set it) looks like anyway: the var is defaulted once at source time.
  export TMUX_CMD="$TMP/tmux-poison" TMUX_POISON_LOG="$POISON_LOG" \
    WAVE_CAP=2 CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-mux" ORCH="$ORCH" MEGADIR="$BM"
  _wave_run "$BM" "$BM/ROADMAP.md" ) > "$TMP/b.out" 2>&1 || brc=$?

[ "$brc" = 0 ] && pass "mux-off NC: _wave_run rc 0 (headless path unaffected by the poisoned tmux)" \
  || { fail "mux-off NC: _wave_run rc=$brc"; cat "$TMP/b.out"; }
ob1=$(_sg_line "$BM/ROADMAP.md" SG-01); ob2=$(_sg_line "$BM/ROADMAP.md" SG-02)
case "$ob1" in '- [x] SG-01'*) pass "mux-off NC: SG-01 box flipped via the plain background path" ;; *) fail "mux-off NC: SG-01 not flipped ($ob1)" ;; esac
case "$ob2" in '- [x] SG-02'*) pass "mux-off NC: SG-02 box flipped via the plain background path" ;; *) fail "mux-off NC: SG-02 not flipped ($ob2)" ;; esac
if [ -s "$POISON_LOG" ]; then
  fail "mux-off NC: tmux WAS invoked while MULTIPLEXER was unset -- coupling leak"; cat "$POISON_LOG"
else
  pass "mux-off NC [NEGATIVE CONTROL]: \$TMUX_CMD never invoked (no tmux window, no send-keys) with MULTIPLEXER unset"
fi

# ============================ (C) MULTIPLEXER=1 explicit off (0) is the same NC ============================
POISON_LOG2="$TMP/poison2.log"; : > "$POISON_LOG2"
C="$TMP/mux-off2-repo"
mk_git_mega "$C"
CM="$C/mega"; mkdir -p "$CM"
cat > "$CM/ROADMAP.md" <<'EOF'
# Mega-goal: mux-off-explicit
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$CM/POINTER_PROMPT.md"
make_goal "$CM" SG-01 "lib/wave-a/**"
crc=0
( export MULTIPLEXER=0 TMUX_CMD="$TMP/tmux-poison" TMUX_POISON_LOG="$POISON_LOG2" \
    WAVE_CAP=2 CLAUDE_FLAGS="" CLAUDE_CMD="$TMP/claude-mux" ORCH="$ORCH" MEGADIR="$CM"
  _wave_run "$CM" "$CM/ROADMAP.md" ) > "$TMP/c.out" 2>&1 || crc=$?
[ "$crc" = 0 ] && [ ! -s "$POISON_LOG2" ] \
  && pass "mux-off explicit (MULTIPLEXER=0) [NEGATIVE CONTROL]: tmux never invoked" \
  || { fail "mux-off explicit: rc=$crc, poison log: $(cat "$POISON_LOG2" 2>/dev/null)"; }

# ============================ (D) command-injection NC (SPEC-119 security fix) ============================
# `route_flags` is built from the goal file's UNSANITIZED `Model:` header. The pre-fix `_pane_spawn`
# joined the pane command into ONE string that real tmux re-parses via `$SHELL -c` (an eval), so a
# hostile `Model:` value broke out and ran on the host under MULTIPLEXER=1. The fix passes the
# command as separate argv tokens after `--` (exec-direct, no re-parse). Two halves:
#  D1 positive control -- proves the payload + the mock's eval path CAN inject (NC is non-vacuous);
#  D2 the fix -- the real `_pane_spawn` (multi-arg) leaves the same payload inert.
PWNED_POS="$TMP/pwned-positive"; PWNED_FIX="$TMP/pwned-fixed"
rm -f "$PWNED_POS" "$PWNED_FIX" 2>/dev/null || true
# A Model:-derived route_flags whose metachars CLOSE the escaped-quote wrapper the pre-fix code put
# around each field (`\"$route_flags\"`), break out, run a command, then reopen the quote.
INJ='--model opus"; touch '"$PWNED_POS"'; echo "'

# D1: feed the OLD joined-string form (each field wrapped in escaped quotes, exactly as the pre-fix
# `_pane_spawn` built it) straight to the mock's new-window -> the mock's eval path re-parses it.
DSTATE="$TMP/inj-state"; mkdir -p "$DSTATE"
INJ_CMDLINE="\"/bin/true\" _pane-exec \"x\" \"SG-01\" \"pf\" \"$INJ\" \"df\""
TMUX_MOCK_STATE="$DSTATE" "$TMP/tmux-mock" new-window -d -t sess -n SG-01 -c "$TMP" \
  "$INJ_CMDLINE" >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8; do [ -e "$PWNED_POS" ] && break; sleep 0.25; done
if [ -e "$PWNED_POS" ]; then
  pass "inj D1 positive control: the joined-string form DOES inject (payload + mock eval are live)"
else
  fail "inj D1 positive control: payload did not fire via the joined string -- NC would be vacuous"
fi

# D2: the real, fixed `_pane_spawn` with the SAME payload as route_flags -> exec-direct, no re-parse.
D2STATE="$TMP/inj-fix-state"; mkdir -p "$D2STATE"
( export TMUX_CMD="$TMP/tmux-mock" TMUX_MOCK_STATE="$D2STATE" TMUX_SESSION=orch-inj \
    ORCH_DIR="$TMP" ORCH="$ORCH"
  # a stub orchestrate.sh so the pane's exec target exists and is itself inert
  printf '#!/usr/bin/env bash\n:\n' > "$TMP/orchestrate.sh"; chmod +x "$TMP/orchestrate.sh"
  _pane_spawn "$TMP/mega-x" SG-01 "$TMP" "$TMP/pf" "$INJ" "$TMP/df" ) >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8; do [ -e "$PWNED_FIX" ] && break; sleep 0.25; done
if [ -e "$PWNED_FIX" ]; then
  fail "inj D2 [NEGATIVE CONTROL]: FIXED _pane_spawn STILL injected -- host command ran"
else
  pass "inj D2 [NEGATIVE CONTROL]: fixed _pane_spawn passes route_flags as argv; the metachar Model: value is inert (no host command)"
fi

echo "----"
if [ "$fails" = 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$fails FAILING"
  exit 1
fi
