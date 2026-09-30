#!/usr/bin/env bash
# test-orchestrate-orca.sh
# Pins the opt-in Orca backend of lib/queue/orchestrate.sh against the stub in
# tests/fixtures/orca-stub/. Every case is hermetic: a temp git repo with a local bare origin, a
# temp state dir for the stub, a temp DWARVES_KIT_LOG_DIR. The live Orca runtime is never touched.
# Each case prints `PASS <name>` or `FAIL <name>: ...`; the suite ends with a Results line.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
STUB="$KIT/tests/fixtures/orca-stub/orca"
passed=0; failed=0; cfail=0; cname=""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DWARVES_KIT_LOG_DIR="$TMP/kitlogs" CLAUDE_FLAGS="" TIER4_CLOSE=0 WAVE_CAP=2 ORCA_POLL_SECS=0

case_begin() { cname="$1"; cfail=0; }
expect() {  # actual expected description
  [ "$1" = "$2" ] && return 0
  cfail=$((cfail + 1)); echo "  [$cname] $3: expected '$2' got '$1'"
}
expect_match() {  # text regex description
  printf '%s' "$1" | grep -Eq -- "$2" && return 0
  cfail=$((cfail + 1)); echo "  [$cname] $3: no match for /$2/ in: $(printf '%s' "$1" | head -c 300)"
}
expect_no_match() {
  printf '%s' "$1" | grep -Eq -- "$2" || return 0
  cfail=$((cfail + 1)); echo "  [$cname] $3: unexpected match for /$2/"
}
case_end() {
  if [ "$cfail" = 0 ]; then echo "PASS $cname"; passed=$((passed + 1)); else echo "FAIL $cname"; failed=$((failed + 1)); fi
}

# Poison binaries: a sentinel proves they were called.
mkdir -p "$TMP/poison"
for b in orca gh; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$POISON_SENTINEL"\nexit 0\n' "$b" > "$TMP/poison/$b"
  chmod +x "$TMP/poison/$b"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/failing-orca"; chmod +x "$TMP/failing-orca"
# BOARD_WORK_CMD fake: prints $BW_JSON when set, else an empty schema-1 view; BW_FAIL=1 exits 1.
cat > "$TMP/bw" <<'EOF'
#!/usr/bin/env bash
[ "${BW_FAIL:-0}" = 1 ] && exit 1
if [ -n "${BW_JSON:-}" ]; then printf '%s\n' "$BW_JSON"; else echo '{"schema":1,"orca":"ok","items":[]}'; fi
EOF
chmod +x "$TMP/bw"

# ---- fixture ---------------------------------------------------------------------------------
# SG-01 auto; SG-02 auto, depends SG-01; SG-03 gate, depends SG-02. A local bare origin; the mega
# dir sits inside the working clone.
mkcase() {  # sets W REPO MEGA STATE
  W="$(mktemp -d "$TMP/c.XXXXXX")"; REPO="$W/repo"; MEGA="$REPO/mega"; STATE="$W/state"
  git init -q --template= --bare -b master "$W/origin.git"
  git init -q --template= -b master "$REPO"
  git -C "$REPO" config user.email t@t.t; git -C "$REPO" config user.name t
  mkdir -p "$MEGA/goals"
  cat > "$MEGA/ROADMAP.md" <<'EOF'
# Mega-goal: orca fixture
## Sub-goals
- [ ] SG-01 first , auto , PR #__
- [ ] SG-02 second , auto , depends SG-01 , PR #__
- [ ] SG-03 third , gate , depends SG-02 , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$MEGA/POINTER_PROMPT.md"
  printf '**Branch:** feat/orca-sg-01\nDone = one\n' > "$MEGA/goals/01-first.md"
  printf '**Branch:** feat/orca-sg-02\nDone = two\n' > "$MEGA/goals/02-second.md"
  printf '**Branch:** feat/orca-sg-03\nDone = three\n' > "$MEGA/goals/03-third.md"
  git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm init
  git -C "$REPO" remote add origin "$W/origin.git"; git -C "$REPO" push -q origin master
}
oenv() {  # run a command with the Orca env
  ORCA_CMD="$STUB" ORCA_STUB_STATE="$STATE" BOARD_WORK_CMD="$TMP/bw" GH_CMD="$TMP/poison/gh" \
  CLAUDE_CMD="$TMP/poison/claude" POISON_SENTINEL="$W/sentinel" "$@"
}
orun()  { oenv bash "$ORCH" run "$MEGA" --backend orca "$@"; }
tick()  { ORCA_MAX_TICKS=1 orun >"$W/tick.out" 2>&1; }
ostat() { oenv bash "$ORCH" status "$MEGA" 2>/dev/null; }
sset()  { ORCA_STUB_STATE="$STATE" "$STUB" _set "$@"; }
st()    { ostat | awk -F'\t' -v s="$1" '$1==s{print $2" "$3}'; }
jqs()   { jq -r "$@" "$STATE/state.json"; }
calls() { cat "$STATE/calls.log" 2>/dev/null; }
tid()   { jqs --arg t "$1" '.tasks[]|select(.title==$t)|.id'; }   # "mega SG-01" -> task id
did()   { jqs --arg t "$(tid "$1")" '[.dispatches[]|select(.taskId==$t)][0].dispatchId // empty'; }
push_branch() { git -C "$REPO" push -q origin "master:refs/heads/$1"; }
flip()  { bash "$ORCH" flip "$MEGA" "$1" >/dev/null 2>&1; }
events() { cat "$MEGA/.orchestrate/events.log" 2>/dev/null; }
# Finish auto sub-goal N the way a good worker does: push the branch, flip the box, Orca completes the Task.
finish_auto() {  # NN
  push_branch "feat/orca-sg-$1"; flip "SG-$1"; sset task-status "$(tid "mega SG-$1")" completed
}

# ---- stub-contract ---------------------------------------------------------------------------
tc_stub_contract() {
  case_begin stub-contract
  mkcase
  export ORCA_STUB_STATE="$STATE"
  v=$("$STUB" --version); expect "$v" "1.4.209" "version"
  r=$("$STUB" orchestration run-create --objective mega:x --json); rid=$(printf '%s' "$r" | jq -r .id)
  expect_match "$rid" '^run_' "run-create id"
  t=$("$STUB" orchestration task-create --spec s --task-title T --run "$rid" --retry-request k1 --json)
  tid1=$(printf '%s' "$t" | jq -r .id)
  t2=$("$STUB" orchestration task-create --spec s --task-title T --run "$rid" --retry-request k1 --json)
  expect "$(printf '%s' "$t2" | jq -r .id)" "$tid1" "retry-request replays the first result"
  "$STUB" orchestration task-list --run "$rid" --json | jq -e '.tasks|length==1' >/dev/null; expect "$?" 0 "task-list json"
  "$STUB" orchestration worker-start --task "$tid1" --agent claude --run "$rid" --json | jq -e .dispatchId >/dev/null; expect "$?" 0 "worker-start json"
  "$STUB" orchestration worker-list --run "$rid" --json | jq -e '.workers[0].projection.liveness=="live"' >/dev/null; expect "$?" 0 "worker-list json"
  "$STUB" orchestration gate-create --task "$tid1" --question q --json | jq -e .id >/dev/null; expect "$?" 0 "gate-create json"
  "$STUB" orchestration gate-list --run "$rid" --json | jq -e '.gates|length==1' >/dev/null; expect "$?" 0 "gate-list json"
  "$STUB" orchestration inbox --run "$rid" --json | jq -e '.messages|type=="array"' >/dev/null; expect "$?" 0 "inbox json"
  "$STUB" orchestration check --run "$rid" --json | jq -e 'has("delivery")' >/dev/null; expect "$?" 0 "check json"
  "$STUB" orchestration task-update --id "$tid1" --status blocked --json | jq -e .ok >/dev/null; expect "$?" 0 "task-update json"
  "$STUB" orchestration worker-stop --dispatch d --json >/dev/null; expect "$?" 0 "worker-stop"
  "$STUB" worktree ps --json | jq -e '.result.worktrees|type=="array"' >/dev/null; expect "$?" 0 "worktree ps json"
  "$STUB" orchestration reset --all >/dev/null 2>&1; expect "$?" 99 "orchestration reset exits 99"
  expect_match "$(calls)" 'orchestration reset --all' "the refused verb is logged"
  unset ORCA_STUB_STATE
  case_end
}

# ---- AC1 default path unchanged --------------------------------------------------------------
tc_AC1() {
  case_begin AC1
  mkcase
  printf '# Mega-goal: default fixture\n## Sub-goals\n- [ ] SG-01 only , auto , PR #__\n' > "$MEGA/ROADMAP.md"
  cat > "$TMP/claude-flip" <<'EOF'
  #!/usr/bin/env bash
  cat >/dev/null
  bash "$ORCH_UNDER_TEST" flip "$MEGA_UNDER_TEST" SG-01
EOF
  chmod +x "$TMP/claude-flip"
  export POISON_SENTINEL="$W/sentinel"
  run_default() {  # extra args...
    ( PATH="$TMP/poison:$PATH" ORCA_CMD="$TMP/poison/orca" CLAUDE_CMD="$TMP/claude-flip" ORCH_UNDER_TEST="$ORCH" MEGA_UNDER_TEST="$MEGA" \
      bash "$ORCH" run "$MEGA" "$@" ) >"$W/def.out" 2>&1
  }
  run_default; expect "$?" 0 "no flag exits 0"
  expect "$(ls "$W/sentinel" 2>/dev/null)" "" "no flag: poison never called"
  printf '# Mega-goal: default fixture\n## Sub-goals\n- [ ] SG-01 only , auto , PR #__\n' > "$MEGA/ROADMAP.md"
  run_default --backend claude; expect "$?" 0 "--backend claude exits 0"
  expect "$(ls "$W/sentinel" 2>/dev/null)" "" "--backend claude: poison never called"
  printf '# Mega-goal: default fixture\n## Sub-goals\n- [ ] SG-01 only , auto , PR #__\n' > "$MEGA/ROADMAP.md"
  fns=$(PATH="$TMP/poison:$PATH" ORCA_CMD="$TMP/poison/orca" CLAUDE_CMD="$TMP/claude-flip" ORCH_UNDER_TEST="$ORCH" MEGA_UNDER_TEST="$MEGA" \
    bash -c '. "$1"; cmd_run "$2" >/dev/null 2>&1; declare -F | awk "{print \$3}" | grep -E "^orca_(plan|tick|gate|derive|reset)$"' _ "$ORCH" "$MEGA")
  expect "$fns" "" "no backend function is defined on the default path"
  unset POISON_SENTINEL
  case_end
}

# ---- AC2 plan --------------------------------------------------------------------------------
tc_AC2() {
  case_begin AC2
  mkcase
  ORCA_MAX_TICKS=0 orun >"$W/o.out" 2>&1; expect "$?" 0 "plan-only run exits 0"
  c=$(calls)
  expect "$(printf '%s\n' "$c" | grep -c '^orchestration run-create')" 1 "one run-create"
  expect "$(printf '%s\n' "$c" | grep -c '^orchestration task-create')" 4 "four task-create"
  order=$(printf '%s\n' "$c" | grep '^orchestration task-create' | grep -oE -- '--task-title mega SG-0[0-9](:accept)?' | sed 's/--task-title //' | tr '\n' ',')
  expect "$order" "mega SG-01,mega SG-02,mega SG-03,mega SG-03:accept," "ROADMAP order, accept Task last"
  t1=$(tid "mega SG-01"); t2=$(tid "mega SG-02"); t3=$(tid "mega SG-03")
  expect "$(jqs --arg t "mega SG-02" '.tasks[]|select(.title==$t)|.deps|join(",")')" "$t1" "SG-02 depends on SG-01"
  expect "$(jqs --arg t "mega SG-03" '.tasks[]|select(.title==$t)|.deps|join(",")')" "$t2" "SG-03 depends on SG-02"
  expect "$(jqs --arg t "mega SG-03:accept" '.tasks[]|select(.title==$t)|.deps|join(",")')" "$t3" "accept depends on SG-03"
  expect "$(printf '%s\n' "$c" | grep '^orchestration task-create' | grep -c -- '--retry-request run_[0-9]*-SG-')" 4 "every task-create carries a retry request"
  expect "$(jqs '.keys|length')" 4 "four retry keys stored"
  ORCA_MAX_TICKS=0 orun >"$W/o.out" 2>&1
  expect "$(calls | grep -c '^orchestration task-create')" 4 "a second run creates no Task"
  expect "$(calls | grep -c '^orchestration run-create')" 1 "a second run creates no Run"
  case_end
}

# ---- AC3 dispatch ----------------------------------------------------------------------------
tc_AC3() {
  case_begin AC3
  mkcase
  ORCA_MAX_TICKS=0 orun >/dev/null 2>&1
  t1=$(tid "mega SG-01"); t2=$(tid "mega SG-02")
  sset task-status "$t2" ready       # Orca says ready, but SG-01's box is open
  tick
  expect_match "$(calls)" "worker-start --task $t1 " "SG-01 (Orca ready, no deps) starts"
  expect_no_match "$(calls)" "worker-start --task $t2 " "SG-02 with an open dep box is not started"
  # a Task that already has a stopped Dispatch is never started again
  mkcase
  ORCA_MAX_TICKS=0 orun >/dev/null 2>&1
  t1=$(tid "mega SG-01"); t2=$(tid "mega SG-02")
  finish_auto 01
  ORCA_STUB_STATE="$STATE" "$STUB" orchestration worker-start --task "$t2" --agent claude --run "$(cat "$MEGA/.orchestrate/orca/run")" --retry-of x --json >/dev/null
  d2=$(did "mega SG-02"); sset dispatch-status "$d2" stopped; sset liveness "$d2" exited; sset task-status "$t2" ready
  tick
  expect "$(calls | grep -c "worker-start --task $t2 ")" 1 "only the manual start; the backend adds none (prior-Dispatch guard)"
  case_end
}

# ---- AC4 negative control: a worker stopped mid-task -------------------------------------------
ac4_row() {  # builds the scenario, prints SG-02's `status` state and reason
  mkcase
  ORCA_MAX_TICKS=0 orun >/dev/null 2>&1
  finish_auto 01
  tick                                         # consumes SG-01, starts SG-02
  local before; before=$(st SG-02)
  d2=$(did "mega SG-02")
  sset liveness "$d2" exited     # the worker exits; the Task stays `dispatched`
  printf '%s\n%s\n' "$before" "$(st SG-02)"
}
tc_AC4() {
  case_begin AC4
  out=$(ac4_row)
  expect "$(printf '%s\n' "$out" | sed -n 1p)" "RUNNING -" "before the stop SG-02 is RUNNING"
  expect "$(printf '%s\n' "$out" | sed -n 2p)" "PARKED exited" "first status after the stop"
  case_end
}

# ---- AC5 unknown stays unknown -----------------------------------------------------------------
tc_AC5() {
  case_begin AC5
  mkcase
  tick; d1=$(did "mega SG-01")
  expect "$(st SG-01)" "RUNNING -" "control: a live worker is RUNNING"
  sset liveness "$d1" unverifiable
  expect_match "$(st SG-01)" '^INDETERMINATE' "liveness unverifiable"
  expect_no_match "$(st SG-01)" 'RUNNING|PARKED|DONE' "unverifiable never reads as RUNNING, PARKED or DONE"
  sset liveness "$d1" live
  grep -v 'SG-02' "$MEGA/.orchestrate/orca/map.tsv" > "$W/map.tmp"; cat "$W/map.tmp" > "$MEGA/.orchestrate/orca/map.tsv"
  expect "$(st SG-02)" "INDETERMINATE no-map-row" "no map row"
  out=$(ORCA_CMD="$TMP/failing-orca" ORCA_STUB_STATE="$STATE" BOARD_WORK_CMD="$TMP/bw" bash "$ORCH" status "$MEGA" 2>/dev/null | awk -F'\t' '$1=="SG-01"{print $2}')
  expect "$out" "INDETERMINATE" "ORCA_CMD exiting nonzero"
  case_end
}

# ---- AC6 DONE-UNSEEN then DONE ------------------------------------------------------------------
tc_AC6() {
  case_begin AC6
  mkcase
  tick; t1=$(tid "mega SG-01"); d1=$(did "mega SG-01")
  sset task-status "$t1" completed
  expect "$(st SG-01)" "DONE-UNSEEN -" "completed, box open, no shipped event"
  push_branch feat/orca-sg-01; flip SG-01
  tick
  expect "$(st SG-01)" "DONE -" "after the flip and one tick"
  expect_match "$(events)" $'\tSG-01\tshipped\t' "events.log has shipped for SG-01"
  expect_match "$(calls)" "worker-release --dispatch $d1" "worker-release for that dispatch"
  case_end
}

# ---- AC7 HELD and accept ------------------------------------------------------------------------
to_gate_pending() {  # drives the fixture until SG-03 finished and its gate is open
  mkcase
  ORCA_MAX_TICKS=0 orun >/dev/null 2>&1
  tick; finish_auto 01; tick; finish_auto 02; tick
  push_branch feat/orca-sg-03; sset task-status "$(tid "mega SG-03")" completed
  tick
}
tc_AC7() {
  case_begin AC7
  to_gate_pending
  t3a=$(tid "mega SG-03:accept")
  expect "$(calls | grep -c "gate-create --task $t3a ")" 1 "one gate-create on the accept Task"
  expect_match "$(st SG-03)" '^HELD gate gate_' "SG-03 is HELD"
  tick; tick
  expect "$(calls | grep -c "gate-create --task $t3a ")" 1 "gate-create issued once across ticks"
  expect_match "$(grep -c '^- \[ \] SG-03' "$MEGA/ROADMAP.md")" '^1$' "SG-03 box stays open while held"
  gid=$(jqs '.gates[0].id')
  sset gate-resolve "$gid" accept
  tick
  expect_match "$(grep '^- \[.\] SG-03' "$MEGA/ROADMAP.md")" '^- \[x\]' "the tick flipped the box"
  expect_match "$(events)" $'\tSG-03\tshipped\tgate '"$gid"' accept' "shipped event names the gate"
  expect "$(jqs --arg t "$t3a" '.tasks[]|select(.id==$t)|.status')" completed "accept Task completed"
  expect "$(st SG-03)" "DONE -" "SG-03 DONE after accept"
  expect "$(ls "$W/sentinel" 2>/dev/null)" "" "no gh call"
  # rework
  to_gate_pending
  gid=$(jqs '.gates[0].id'); sset gate-resolve "$gid" rework
  expect "$(st SG-03)" "BLOCKED rework" "rework reads BLOCKED rework"
  tick
  expect_match "$(grep '^- \[.\] SG-03' "$MEGA/ROADMAP.md")" '^- \[ \]' "rework leaves the box open"
  case_end
}

# ---- AC8 no self-claim ---------------------------------------------------------------------------
tc_AC8() {
  case_begin AC8
  mkcase
  tick; t1=$(tid "mega SG-01"); t2=$(tid "mega SG-02")
  sset task-status "$t1" completed      # box never flipped
  tick
  expect "$(st SG-01)" "BLOCKED no self-claim" "completed with an open box"
  expect_no_match "$(calls)" "worker-start --task $t2 " "the dependent is not started"
  case_end
}

# ---- AC9 rollback -------------------------------------------------------------------------------
tc_AC9() {
  case_begin AC9
  mkcase
  tick; t1=$(tid "mega SG-01"); t2=$(tid "mega SG-02"); run=$(cat "$MEGA/.orchestrate/orca/run"); d1=$(did "mega SG-01")
  sset task-status "$t2" ready
  ORCA_STUB_STATE="$STATE" "$STUB" orchestration worker-start --task "$t2" --agent claude --run "$run" --json >/dev/null
  d2=$(did "mega SG-02"); sset dispatch-status "$d2" stopped; sset liveness "$d2" exited
  sset task-status "$t1" completed
  # a Dispatch of another Run must never be touched
  jq '.dispatches += [{dispatchId:"disp_foreign",taskId:"task_foreign",runId:"run_other",dispatchStatus:"active",terminalState:"active",projection:{liveness:"live"},observation:{agentWait:null}}]' "$STATE/state.json" > "$STATE/s.tmp" && cat "$STATE/s.tmp" > "$STATE/state.json"
  expected_blocked=$(jqs '.tasks[]|select(.status!="completed")|.id' | sort | tr '\n' ',')
  : > "$STATE/calls.log"
  oenv bash "$ORCH" orca-reset "$MEGA" >"$W/reset.out" 2>&1; expect "$?" 0 "orca-reset exits 0"
  c=$(calls)
  expect "$(printf '%s\n' "$c" | grep -c 'worker-stop')" 1 "one worker-stop (the live Dispatch)"
  expect_match "$c" "worker-stop --dispatch $d1" "the live Dispatch is stopped"
  expect_no_match "$c" "worker-stop --dispatch $d2" "an exited Dispatch is not stopped"
  expect "$(printf '%s\n' "$c" | grep -c 'worker-release')" 2 "both of this Run's Dispatches are released"
  expect_no_match "$c" 'foreign' "the other Run's Dispatch is untouched"
  expect_no_match "$c" 'orchestration reset' "never the global reset"
  got_blocked=$(printf '%s\n' "$c" | grep -oE 'task-update --id [a-z_0-9]+ --status blocked' | awk '{print $3}' | sort | tr '\n' ',')
  expect "$got_blocked" "$expected_blocked" "every Task not completed is set to blocked"
  expect_no_match "$c" "task-update --id $t1 " "the completed Task is left alone"
  expect "$(ls "$MEGA/.orchestrate/orca/map.tsv" 2>/dev/null)" "" "map.tsv moved aside"
  expect "$(ls "$MEGA/.orchestrate/orca/" | grep -c '^map.tsv.reset-')" 1 "the moved map is kept"
  case_end
}

# ---- AC10 pre-flight -----------------------------------------------------------------------------
tc_AC10() {
  case_begin AC10
  mkcase
  oenv bash "$ORCH" run "$MEGA" --backend foo >/dev/null 2>&1; expect "$?" 64 "--backend foo"
  MEGA_BACKEND=foo oenv bash "$ORCH" run "$MEGA" >/dev/null 2>&1; expect "$?" 64 "MEGA_BACKEND=foo"
  printf 'Harness: codex\n' >> "$MEGA/goals/02-second.md"
  orun >"$W/o.out" 2>&1; expect "$?" 64 "Harness: codex under the Orca backend"
  expect "$(ls "$STATE/calls.log" 2>/dev/null)" "" "zero Orca calls"
  out=$(MEGA_BACKEND=orca oenv bash "$ORCH" run "$MEGA" --backend claude --dry-run 2>&1)
  expect_no_match "$out" 'backend orca' "the flag wins over MEGA_BACKEND"
  printf '**Branch:** feat/orca-sg-02\nDone = two\n' > "$MEGA/goals/02-second.md"
  printf '%s\n' '- [ ] SG-04 fourth , auto , depends SG-01 SG-02 , PR #__' >> "$MEGA/ROADMAP.md"
  orun >"$W/o.out" 2>&1; expect "$?" 64 "two SG dependencies are rejected"
  expect_match "$(cat "$W/o.out")" 'one' "the rejection names the limit"
  case_end
}

# ---- AC13 inbox ack after acting ------------------------------------------------------------------
tc_AC13() {
  case_begin AC13
  mkcase
  tick; t1=$(tid "mega SG-01"); run=$(cat "$MEGA/.orchestrate/orca/run")
  qid=$(sset message question "$t1")
  expect "$(st SG-01)" "PARKED question" "an unanswered question parks the sub-goal"
  sset message worker_done "$t1" >/dev/null
  finish_auto 01
  tick
  expect "$(calls | grep -c -- '--ack')" 0 "no ack while the question is unanswered"
  sset reply "$qid"
  tick
  expect "$(calls | grep -c -- '--ack')" 1 "exactly one ack after the reply"
  expect_match "$(calls)" 'check --run [a-z_0-9]+ --ack dlv_' "the ack names the delivery"
  tick
  expect "$(calls | grep -c -- '--ack')" 1 "no second ack"
  case_end
}

# ---- AC15 run lock ---------------------------------------------------------------------------------
tc_AC15() {
  case_begin AC15
  mkcase
  sleep 300 & live=$!
  mkdir -p "$MEGA/.orchestrate/orca/run.lock"; echo "$live" > "$MEGA/.orchestrate/orca/run.lock/pid"
  ORCA_MAX_TICKS=0 orun >"$W/o.out" 2>&1; rc=$?
  expect "$rc" 75 "a live holder blocks a second runner"
  expect_match "$(cat "$W/o.out")" "pid $live" "the message names the holder pid"
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
  ORCA_MAX_TICKS=0 orun >"$W/o.out" 2>&1; expect "$?" 0 "a dead holder is reclaimed"
  expect "$(ls "$MEGA/.orchestrate/orca/run.lock" 2>/dev/null)" "" "the lock is released on exit"
  case_end
}

# ---- AC16 ticking and errors -------------------------------------------------------------------------
tc_AC16() {
  case_begin AC16
  to_gate_pending
  gid=$(jqs '.gates[0].id')
  ORCA_MAX_TICKS=3 orun >"$W/o.out" 2>&1; expect "$?" 0 "a pending gate keeps the runner ticking"
  expect_match "$(cat "$W/o.out")" 'tick bound reached \(3\)' "three ticks ran while the gate was pending"
  sset gate-resolve "$gid" accept
  ORCA_MAX_TICKS=1 orun >"$W/o.out" 2>&1
  expect_match "$(grep '^- \[.\] SG-03' "$MEGA/ROADMAP.md")" '^- \[x\]' "the next tick processes the accept"
  # gate timeout
  to_gate_pending
  gid=$(jqs '.gates[0].id')
  ORCA_GATE_TIMEOUT_SECS=1 ORCA_POLL_SECS=1 orun >"$W/o.out" 2>&1; expect "$?" 0 "gate timeout exits 0"
  expect_match "$(cat "$W/o.out")" "held: SG-03 awaiting gate $gid" "the held line names the SG and gate"
  expect_match "$(grep '^- \[.\] SG-03' "$MEGA/ROADMAP.md")" '^- \[ \]' "SG-03 stays open"
  # status footer
  sleep 300 & live=$!
  mkdir -p "$MEGA/.orchestrate/orca/run.lock"; echo "$live" > "$MEGA/.orchestrate/orca/run.lock/pid"
  out=$(ostat)
  expect_match "$out" "runner pid $live alive" "status prints the runner pid"
  expect_match "$out" 'last tick [0-9]+s ago' "status prints the last-tick age"
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
  # unreachable
  mkcase
  ORCA_STUB_FAIL_VERB=task-list orun >"$W/o.out" 2>&1; expect "$?" 1 "five failed ticks halt with exit 1"
  expect_match "$(cat "$W/o.out")" 'orca-unreachable: task-list' "the halt names the verb"
  expect "$(grep -c 'tick read failed' "$W/o.out")" 5 "exactly five failed ticks"
  # version
  mkcase
  sset version 1.4.100
  ORCA_MAX_TICKS=0 orun >"$W/o.out" 2>&1; expect "$?" 64 "an old Orca fails pre-flight"
  expect_match "$(cat "$W/o.out")" 'orca-too-old: 1.4.100' "the message names the version"
  case_end
}

# ---- rule order --------------------------------------------------------------------------------------
tc_rule_order() {
  case_begin rule-order
  mkcase
  tick; t1=$(tid "mega SG-01"); run=$(cat "$MEGA/.orchestrate/orca/run"); d1=$(did "mega SG-01")
  sset task-status "$t1" completed
  tick
  expect "$(st SG-01)" "BLOCKED no self-claim" "consumed and rejected reads BLOCKED"
  ORCA_STUB_STATE="$STATE" "$STUB" orchestration worker-start --task "$t1" --agent claude --run "$run" --retry-of "$d1" --json >/dev/null
  sset task-status "$t1" completed
  expect "$(st SG-01)" "DONE-UNSEEN -" "a retry Dispatch starts clean"
  case_end
}

# ---- view fallback -----------------------------------------------------------------------------------
tc_view_fallback() {
  case_begin view-fallback
  mkcase
  tick
  good='{"schema":1,"orca":"ok","items":[{"item":"mega/SG-01","origin":"mega","flags":["PARKED"],"agent":{"state":"idle","idle_s":1500},"rung":"built","reasons":[]}]}'
  BW_JSON="$good" ostat > "$W/v1.out"
  expect "$(awk -F'\t' '$1=="SG-01"{print $2" "$3" "$6}' "$W/v1.out")" "PARKED idle 1500s built" "control: schema 1 with a PARKED flag"
  export BW_JSON="${good/\"schema\":1/\"schema\":2}"
  expect "$(awk -F'\t' '$1=="SG-01"{print $2" "$6}' <(ostat))" "RUNNING ?" "schema 2: rung ? and no idle PARKED"
  export BW_JSON="${good/\"orca\":\"ok\"/\"orca\":\"error\"}"
  expect "$(awk -F'\t' '$1=="SG-01"{print $2}' <(ostat))" "RUNNING" "top-level orca not ok: no idle signal"
  export BW_JSON="$good" BW_FAIL=1
  expect "$(awk -F'\t' '$1=="SG-01"{print $2" "$6}' <(ostat))" "RUNNING ?" "board work exits 1: rung ?"
  unset BW_JSON BW_FAIL
  expect "$(st SG-02)" "WAITING deps SG-01" "other states unchanged"
  case_end
}

# ---- mutation check: the AC4 control can fail ----------------------------------------------------------
tc_mutation_check() {
  case_begin mutation-check
  sed 's/\[ "\$live" = exited \]/false/' "$KIT/lib/queue/orca-backend.sh" > "$TMP/orca-backend.mutant.sh"
  expect "$(grep -c 'false; then _S_STATE=PARKED' "$TMP/orca-backend.mutant.sh")" 1 "the mutant drops the exited branch"
  row=$(ORCA_BACKEND_LIB="$TMP/orca-backend.mutant.sh" ac4_row | sed -n 2p)
  [ "$row" != "PARKED exited" ] || { cfail=$((cfail + 1)); echo "  [$cname] AC4 stayed green on the mutant"; }
  expect_match "$row" '^INDETERMINATE' "the mutant falls to INDETERMINATE (never a false RUNNING)"
  case_end
}

tc_start_failure() {
  case_begin start-failure
  mkcase
  ORCA_STUB_FAIL_VERB=worker-start ORCA_MAX_TICKS=1 orun >"$W/o.out" 2>&1
  expect "$(st SG-01)" "INDETERMINATE start-outcome-unknown" "a failed worker-start is unknown, not rejected"
  tick; tick
  expect "$(calls | grep -c 'worker-start')" 1 "the backend never relaunches a start of unknown outcome"
  case_end
}

# ONLY="AC4 AC8" runs just those cases; unset runs every case.
CASES="stub-contract AC1 AC2 AC3 AC4 AC5 AC6 AC7 AC8 AC9 AC10 AC13 AC15 AC16 rule-order start-failure view-fallback mutation-check"
for c in $CASES; do
  if [ -z "${ONLY:-}" ] || printf ' %s ' "$ONLY" | grep -q " $c "; then "tc_${c//-/_}"; fi
done

echo "Results: $passed passed, $failed failed"
[ "$failed" = 0 ]
