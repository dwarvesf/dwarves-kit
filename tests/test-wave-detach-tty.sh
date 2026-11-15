#!/usr/bin/env bash
# test-wave-detach-tty.sh
# Pins the wave path's "no controlling terminal" spawn (lib/queue/detach-run).
#
# Bug: a wave sub-goal is a background process group on the operator's terminal. Its `claude -p`
# runs the user's zshrc (via Claude Code's shell snapshot), which runs `stty` on the controlling
# terminal; a background group doing that gets SIGTTOU and stops (state T) for good. The fix runs the
# session in its own session via detach-run, with the wave group's abort kill still reaching it.
#
# 1. detach-run alone: exit status passthrough, KIT_DETACH_CMD not leaked, and a group kill of the
#    spawn (the `_wave_abort` shape: `set -m`, `kill -- -$!`) leaves no orphan.
# 2. A real `_wave_run` under a REAL pty (python3 pty gives the shell a controlling terminal, the
#    condition the bug needs) with a mock claude that runs `stty -ixon </dev/tty`:
#      fixed code             -> the wave finishes, the mock had no controlling terminal
#      NC_SKIP_WAVE_DETACH=1  -> NEGATIVE CONTROL: the mock stops (state T) and the deadline fires
# 3. A real `_wave_run` aborted with SIGTERM leaves no orphaned mock or grandchild.
#
# Run: bash tests/test-wave-detach-tty.sh   (exit 0 = pass, 1 = fail)
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
DETACH="$KIT/lib/queue/detach-run"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

command -v perl >/dev/null 2>&1 || { echo "SKIP perl not installed (detach-run needs it; the wave falls back to the old spawn)"; exit 0; }

alive() { kill -0 "$1" 2>/dev/null; }
wait_for_file() {  # path secs
  local i=0 max=$(( $2 * 10 ))
  while [ ! -s "$1" ] && [ "$i" -lt "$max" ]; do sleep 0.1; i=$((i + 1)); done
  [ -s "$1" ]
}

# ============ 1. detach-run alone ============
KIT_DETACH_CMD=bash "$DETACH" -c 'exit 7'; rc=$?
[ "$rc" = 7 ] && pass "detach-run passes the child's exit status through (7)" || fail "detach-run exit status: got $rc, want 7"

out=$(KIT_DETACH_CMD=bash "$DETACH" -c 'printf "%s" "${KIT_DETACH_CMD:-unset}"')
[ "$out" = unset ] && pass "detach-run does not leak KIT_DETACH_CMD to the command" || fail "KIT_DETACH_CMD leaked: '$out'"

cat > "$TMP/tree" <<'EOF'
#!/usr/bin/env bash
sleep 300 &
echo "$$ $!" > "$TREE_PIDS"
wait
EOF
chmod +x "$TMP/tree"
export TREE_PIDS="$TMP/tree.pids"
set -m
KIT_DETACH_CMD="$TMP/tree" "$DETACH" &
jpid=$!
set +m
if wait_for_file "$TREE_PIDS" 10; then
  read -r child grand < "$TREE_PIDS"
  kill -TERM -- -"$jpid" 2>/dev/null
  wait "$jpid" 2>/dev/null; jrc=$?
  sleep 0.3
  if ! alive "$child" && ! alive "$grand" && [ "$jrc" = 143 ]; then
    pass "group kill of the detach-run job leaves no orphan (child, grandchild gone; rc 143)"
  else
    fail "group kill: child alive=$(alive "$child" && echo y || echo n) grandchild alive=$(alive "$grand" && echo y || echo n) rc=$jrc"
    kill -KILL "$child" "$grand" 2>/dev/null
  fi
else
  fail "detach-run tree never started"
  kill -KILL -- -"$jpid" 2>/dev/null
fi

# ============ shared wave fixture ============
mk_git_mega() {  # repo-root
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name test
  git -C "$1" commit -q --allow-empty -m init
}

mk_wave() {  # name -> prints the megadir
  local repo="$TMP/$1-repo" mg="$TMP/$1-repo/mega"
  mk_git_mega "$repo"; mkdir -p "$mg/goals"
  printf '# Mega-goal: detach\n## Sub-goals\n- [ ] SG-01 alpha , auto , PR #__\n' > "$mg/ROADMAP.md"
  echo "POINTER: resume from ROADMAP" > "$mg/POINTER_PROMPT.md"
  printf '# SG-01: sub-goal\n**Branch:** feat/wave-detach-%s\n\n## Touches\n- lib/detach-%s/**\n' "$1" "$1" > "$mg/goals/01-SG-01.md"
  printf '%s' "$mg"
}

# Mock claude for the pty cases: records its controlling terminal, then does what the user's zshrc
# does (stty on the controlling terminal), then flips its box.
cat > "$TMP/claude-stty" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
echo $$ > "$MOCK_PID_OUT"
ps -o tty= -p $$ | tr -d ' ' > "$MOCK_TTY_OUT"
stty -ixon </dev/tty >/dev/null 2>&1
bash "$ORCH" flip "$MEGADIR" SG-01 >/dev/null 2>&1
MOCK
chmod +x "$TMP/claude-stty"

# ============ 2. real wave under a real pty ============
command -v python3 >/dev/null 2>&1 || { echo "SKIP python3 missing: no pty cases"; [ "$fails" = 0 ] && exit 0 || exit 1; }

cat > "$TMP/inner-pty" <<'INNER'
#!/usr/bin/env bash
# Runs INSIDE the pty: this shell has a controlling terminal and is its foreground group.
source "$ORCH"
export CLAUDE_CMD="$TMP/claude-stty" CLAUDE_FLAGS="" WAVE_CAP=1 DWARVES_KIT_LOG_DIR="$TMP/logs-$CASE"
(
  # Start the clock once the mock is running (worktree setup time varies), then give it DEADLINE secs.
  for _ in $(seq 1 900); do [ -s "$MOCK_PID_OUT" ] && break; sleep 0.1; done
  sleep "$DEADLINE"
  echo deadline > "$RES.deadline"
  ps -axo stat=,pgid=,comm= | awk '$1 ~ /^T/ {print}' > "$RES.stopped"
  pg=$(ps -o pgid= -p "$(cat "$MOCK_PID_OUT")" 2>/dev/null | tr -d ' ')
  [ -n "$pg" ] && { kill -CONT -- -"$pg" 2>/dev/null; kill -KILL -- -"$pg" 2>/dev/null; }
) &
reaper=$!
_wave_run "$MEGADIR" "$MEGADIR/ROADMAP.md" > "$RES.out" 2>&1
echo "$?" > "$RES"
kill "$reaper" 2>/dev/null
INNER

run_pty_case() {  # case deadline [extra env assignments...]
  local case="$1" deadline="$2"; shift 2
  local mg; mg=$(mk_wave "$case")
  env ORCH="$ORCH" TMP="$TMP" CASE="$case" DEADLINE="$deadline" MEGADIR="$mg" \
      RES="$TMP/res-$case" MOCK_TTY_OUT="$TMP/tty-$case" MOCK_PID_OUT="$TMP/pid-$case" "$@" \
    python3 -I -c 'import os,pty,sys; pty.spawn(["bash", sys.argv[1]])' "$TMP/inner-pty" </dev/null >"$TMP/pty-$case.out" 2>&1
  RES_MEGA="$mg"
}

run_pty_case fixed 30
tty_fixed=$(cat "$TMP/tty-fixed" 2>/dev/null)
rc_fixed=$(cat "$TMP/res-fixed" 2>/dev/null)
if [ ! -e "$TMP/res-fixed.deadline" ] && [ "$rc_fixed" = 0 ] && grep -q '\[x\] SG-01' "$RES_MEGA/ROADMAP.md" \
   && { [ "$tty_fixed" = "??" ] || [ "$tty_fixed" = "?" ]; }; then
  pass "fixed: wave session finishes under a real pty, runs with no controlling terminal (tty='$tty_fixed'), box flipped"
else
  fail "fixed: rc='$rc_fixed' deadline=$([ -e "$TMP/res-fixed.deadline" ] && echo hit || echo no) tty='$tty_fixed' roadmap: $(grep SG-01 "$RES_MEGA/ROADMAP.md")"
  cat "$TMP/res-fixed.out" 2>/dev/null | tail -5
fi

run_pty_case nc 4 NC_SKIP_WAVE_DETACH=1
tty_nc=$(cat "$TMP/tty-nc" 2>/dev/null)
if [ -e "$TMP/res-nc.deadline" ] && [ -s "$TMP/res-nc.stopped" ] && ! grep -q '\[x\] SG-01' "$RES_MEGA/ROADMAP.md" \
   && [ "$tty_nc" != "??" ] && [ "$tty_nc" != "?" ]; then
  pass "NEGATIVE CONTROL (pre-fix spawn): the session sits on the terminal (tty='$tty_nc') and its stty stops it (state T): $(head -1 "$TMP/res-nc.stopped" | tr -s ' ')"
else
  fail "NEGATIVE CONTROL: expected a stopped session. deadline=$([ -e "$TMP/res-nc.deadline" ] && echo hit || echo no) stopped='$(cat "$TMP/res-nc.stopped" 2>/dev/null)' tty='$tty_nc' roadmap: $(grep SG-01 "$RES_MEGA/ROADMAP.md")"
fi

# ============ 3. wave abort leaves no orphan ============
cat > "$TMP/claude-hang" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
sleep 300 &
echo "$$ $!" > "$HANG_PIDS"
wait
MOCK
chmod +x "$TMP/claude-hang"

cat > "$TMP/inner-abort" <<'INNER'
#!/usr/bin/env bash
source "$ORCH"
export CLAUDE_CMD="$TMP/claude-hang" CLAUDE_FLAGS="" WAVE_CAP=1 DWARVES_KIT_LOG_DIR="$TMP/logs-abort"
_wave_run "$MEGADIR" "$MEGADIR/ROADMAP.md" >/dev/null 2>&1
INNER

mg=$(mk_wave abort)
HANG_PIDS="$TMP/hang.pids" ORCH="$ORCH" TMP="$TMP" MEGADIR="$mg" bash "$TMP/inner-abort" &
ipid=$!
if wait_for_file "$TMP/hang.pids" 15; then
  # The wrapper (detach-run) is the wave job; the real mock + its sleep run in the detached session.
  read -r mock grand < "$TMP/hang.pids"
  kill -TERM "$ipid"
  wait "$ipid" 2>/dev/null
  sleep 0.5
  if ! alive "$mock" && ! alive "$grand"; then
    pass "wave abort (SIGTERM to the orchestrator) leaves no orphaned session or grandchild"
  else
    fail "wave abort orphaned: mock alive=$(alive "$mock" && echo y || echo n) grandchild alive=$(alive "$grand" && echo y || echo n)"
    kill -KILL "$mock" "$grand" 2>/dev/null
  fi
else
  fail "abort case: the mock never started"
  kill -KILL "$ipid" 2>/dev/null
fi

echo "---"
[ "$fails" = 0 ] && { echo "all passed"; exit 0; } || { echo "$fails failed"; exit 1; }
