#!/usr/bin/env bash
# orca-backend.sh -- the opt-in Orca backend for orchestrate.sh (trial). SOURCED by orchestrate.sh
# only under `run --backend orca` and for the `status` / `orca-reset` verbs; the default path never
# loads this file and never calls $ORCA_CMD. Not executable on its own.
#
# It maps each sub-goal to an Orca Task, starts supervised workers, and derives every sub-goal's
# state at READ time from Orca plus the ROADMAP box. Nothing derived is stored. The ROADMAP box
# stays the only proof of done: an Orca `completed` never advances a sub-goal (no self-claim).
# The runner stays non-LLM. Five parts: plan, tick, gate, derive, reset.
#
# Uses from orchestrate.sh: _subgoals _sg_line _sg_deps_blocked _goalfile _sg_branch _emit_event
# _route _harness_of _build_prompt cmd_flip _lock_stale _lock_reclaim _unlock _tier4_close.

ORCA_CMD="${ORCA_CMD:-orca}"
BOARD_WORK_CMD="${BOARD_WORK_CMD:-$LIB_ROOT/../bin/board work}"
ORCA_POLL_SECS="${ORCA_POLL_SECS:-30}"
ORCA_IDLE_MIN="${ORCA_IDLE_MIN:-20}"
ORCA_GATE_TIMEOUT_SECS="${ORCA_GATE_TIMEOUT_SECS:-86400}"
ORCA_ERROR_LIMIT="${ORCA_ERROR_LIMIT:-5}"
ORCA_AGENT="${ORCA_AGENT:-claude}"
ORCA_MIN_VERSION="1.4.209"
_TICK_ACTED=0 _TICK_ROWS="" _O_OK=0 _O_BW="" _O_TL="" _O_WL="" _O_GL="" _O_IB="" _O_CK=""
# ORCA_MAX_TICKS (unset = unbounded) is a test seam: run at most N ticks, 0 = plan only.

_orca_dir() { printf '%s/.orchestrate/orca\n' "$1"; }
_orca() { "$ORCA_CMD" orchestration "$@" </dev/null; }
_orca_repo() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$1"; }
_orca_slug() { basename "${1%/}"; }
_orca_run_id() { cat "$(_orca_dir "$1")/run" 2>/dev/null; }
_orca_pushed() { git -C "$1" ls-remote --exit-code origin "refs/heads/$2" >/dev/null 2>&1; }
_orca_sha() { git -C "$1" ls-remote origin "refs/heads/$2" 2>/dev/null | cut -c1-12; }
_orca_map_task() {  # dir sg kind
  awk -F'\t' -v s="$2" -v k="$3" '$2==s && $3==k {print $1; exit}' "$(_orca_dir "$1")/map.tsv" 2>/dev/null
}

# Read one Orca verb into a variable. Failure (nonzero exit or non-JSON) records "<verb> exit <rc>".
_ORCA_FAIL=""
_orca_get() {  # varname verb args...
  local __v="$1" __verb="$2" __out __rc
  shift 2
  __out=$(_orca "$__verb" "$@" 2>/dev/null); __rc=$?
  if [ "$__rc" != 0 ] || ! printf '%s' "$__out" | jq -e . >/dev/null 2>&1; then
    _ORCA_FAIL="$__verb exit $__rc"; printf -v "$__v" '%s' ""; return 1
  fi
  printf -v "$__v" '%s' "$__out"
}

# The SPEC-366 view, one call. Any failure or a schema other than 1 leaves it empty: rung prints `?`
# and no idle signal is used.
_orca_board_work() {  # dir
  local dir="$1" out
  _O_BW=""
  # shellcheck disable=SC2086 # BOARD_WORK_CMD is operator config, word-split on purpose.
  out=$(ORCA_BIN="$ORCA_CMD" $BOARD_WORK_CMD --json --megagoals-root "$(cd "$(dirname "$dir")" && pwd -P)" \
        --code-root "$(_orca_repo "$dir")" --idle-min "$ORCA_IDLE_MIN" 2>/dev/null) || return 0
  printf '%s' "$out" | jq -e '.schema == 1' >/dev/null 2>&1 || return 0
  _O_BW="$out"
}

# Populate _O_TL _O_WL _O_GL _O_IB (+ _O_BW), and _O_CK when with_check=1. Returns 1 on the first
# failed Orca read. Only a tick consumes mail with `check`; `status` never does.
_orca_read() {  # dir with_check
  local dir="$1" with_check="${2:-0}" run
  run=$(_orca_run_id "$dir"); _ORCA_FAIL=""; _O_OK=0; _O_BW=""
  _orca_get _O_TL task-list --run "$run" --json && _orca_get _O_WL worker-list --run "$run" --json \
    && _orca_get _O_GL gate-list --run "$run" --json && _orca_get _O_IB inbox --run "$run" --json || return 1
  _O_CK=""
  [ "$with_check" = 1 ] && { _orca_get _O_CK check --run "$run" --json || return 1; }
  _orca_board_work "$dir"
  _O_OK=1
}

# ---- events ---------------------------------------------------------------------------------
# A state-change event note starts `dispatch=<id> task=<id>: <reason>` so a retry (a new Dispatch on
# the same Task) starts clean. status is shipped, blocked or held.
_orca_ev() {  # dir sg status dispatch task reason
  _emit_event "$1" "$2" "$3" "dispatch=$4 task=$5: $6"
}
# Note text of the newest event of one of the statuses (a|b|c) for this sg and dispatch, or empty.
_orca_ev_note() {  # dir sg dispatch statuses
  local ef; ef=$(_events_file "$1"); [ -f "$ef" ] || return 0
  awk -F'\t' -v s="$2" -v d="dispatch=$3 " -v st="$4" \
    'BEGIN{n=split(st,a,"|")} $2==s && index($4,d)==1 { for(i=1;i<=n;i++) if($3==a[i]) {note=$4; f=1} } END{ if(f) print note }' "$ef"
}

# ---- plan -----------------------------------------------------------------------------------
# Idempotent: creates the Run once and a Task for every unchecked sub-goal that has no map row yet
# (runs every tick, so a sub-goal added mid-run is picked up). A gate sub-goal gets an extra accept
# Task that is never dispatched; its dependents depend on the accept Task.
_orca_task_id() { printf '%s' "$1" | jq -r '.id // .task.id // .taskId // empty'; }
orca_plan() {  # dir
  local dir="$1" od roadmap="$1/ROADMAP.md" run out slug progress=1 pass
  od=$(_orca_dir "$dir"); mkdir -p "$od"; slug=$(_orca_slug "$dir")
  run=$(_orca_run_id "$dir")
  if [ -z "$run" ]; then
    out=$(_orca run-create --objective "mega:$slug" --json 2>/dev/null) || { echo "[orca] run-create failed" >&2; return 1; }
    run=$(printf '%s' "$out" | jq -r '.id // .run.id // .runId // empty')
    [ -n "$run" ] || { echo "[orca] run-create returned no id" >&2; return 1; }
    printf '%s\n' "$run" > "$od/run"; _TICK_ACTED=$((_TICK_ACTED + 1))
  fi
  : >> "$od/map.tsv"
  # Passes let a dependent be created after a dependency that the ROADMAP lists later.
  for pass in 1 2 3 4 5 6 7 8; do
    [ "$progress" = 1 ] || break
    progress=0
    local sg policy checked line deps d dtask depjson sep tid gf ptr
    while IFS=$'\t' read -r sg policy checked; do
      [ "$checked" = 0 ] || continue
      [ -n "$(_orca_map_task "$dir" "$sg" work)" ] && continue
      line=$(_sg_line "$roadmap" "$sg")
      deps=$(printf '%s' "$line" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' || true)
      depjson=""; sep=""; local missing=0
      for d in $deps; do
        [ "$(_subgoals "$roadmap" | awk -F'\t' -v i="$d" '$1==i{print $3}')" = 1 ] && continue
        dtask=$(_orca_map_task "$dir" "$d" accept); [ -n "$dtask" ] || dtask=$(_orca_map_task "$dir" "$d" work)
        [ -n "$dtask" ] || { missing=1; break; }
        depjson="$depjson$sep\"$dtask\""; sep=","
      done
      [ "$missing" = 0 ] || continue
      gf=$(_goalfile "$dir" "$sg")
      ptr="Target: ${gf:-no goal file}
Change: the \`Done =\` line in ${gf:-no goal file}
Constraints: the \`## Touches\` section in ${gf:-no goal file}
Ownership: the \`## Touches\` section in ${gf:-no goal file}
Observable acceptance: push branch $(_sg_branch "$gf" "$sg") to origin, then run: bash $ORCH_DIR/orchestrate.sh flip $(cd "$dir" && pwd -P) $sg (a gate sub-goal pushes and does NOT flip)
Read and follow $(cd "$dir" && pwd -P)/.orchestrate/orca/$sg.prompt.md"
      out=$(_orca task-create --spec "$ptr" --task-title "$slug $sg" ${depjson:+--deps "[$depjson]"} \
            --retry-request "$run-$sg" --run "$run" --json 2>/dev/null) || { echo "[orca] task-create $sg failed" >&2; continue; }
      tid=$(_orca_task_id "$out"); [ -n "$tid" ] || { echo "[orca] task-create $sg returned no id" >&2; continue; }
      printf '%s\t%s\twork\n' "$tid" "$sg" >> "$od/map.tsv"; progress=1; _TICK_ACTED=$((_TICK_ACTED + 1))
      case "$policy" in
        gate|'gate!')
          out=$(_orca task-create --spec "Decision gate for $sg. Never dispatched." --task-title "$slug $sg:accept" \
                --deps "[\"$tid\"]" --retry-request "$run-$sg-accept" --run "$run" --json 2>/dev/null) || { echo "[orca] task-create $sg:accept failed" >&2; continue; }
          tid=$(_orca_task_id "$out")
          [ -n "$tid" ] && printf '%s\t%s\taccept\n' "$tid" "$sg" >> "$od/map.tsv" ;;
      esac
    done < <(_subgoals "$roadmap")
  done
  return 0
}

# ---- derive ---------------------------------------------------------------------------------
# One row per sub-goal: sg state reason task dispatch rung. First matching rule wins. A rule that
# needs a field that is absent or reads `unverifiable` yields INDETERMINATE and stops there.
_orca_jq() { printf '%s' "$1" | jq -r "${@:2}"; }   # json jqargs...

_orca_sg_state() {  # dir sg policy checked   -> _S_STATE _S_REASON _S_TASK _S_DISP _S_RUNG
  local dir="$1" sg="$2" policy="$3" checked="$4" roadmap="$1/ROADMAP.md"
  local gf branch repo slug task atask ts row live dstat wait gate gres gid q bnote line
  _S_STATE=""; _S_REASON=""; _S_DISP="-"; _S_RUNG="?"
  slug=$(_orca_slug "$dir"); repo=$(_orca_repo "$dir")
  gf=$(_goalfile "$dir" "$sg"); branch=$(_sg_branch "$gf" "$sg")
  task=$(_orca_map_task "$dir" "$sg" work); _S_TASK="${task:--}"
  [ -n "${_O_BW:-}" ] && _S_RUNG=$(_orca_jq "$_O_BW" --arg i "$slug/$sg" '[.items[]|select(.origin=="mega" and .item==$i)][0].rung // "?"')
  # 1 DONE: box checked and the branch is on origin. Box checked but no branch: unknown.
  if [ "$checked" = 1 ]; then
    if _orca_pushed "$repo" "$branch"; then _S_STATE=DONE; else _S_STATE=INDETERMINATE; _S_REASON="branch-not-on-origin"; fi
    return 0
  fi
  # 2 INDETERMINATE: no map row, an Orca read failed, or a needed row is missing.
  [ -n "$task" ] || { _S_STATE=INDETERMINATE; _S_REASON="no-map-row"; return 0; }
  [ "${_O_OK:-0}" = 1 ] || { _S_STATE=INDETERMINATE; _S_REASON="orca-read-failed: ${_ORCA_FAIL:-unknown}"; return 0; }
  ts=$(_orca_jq "$_O_TL" --arg t "$task" '[.tasks[]|select(.id==$t)][0].status // empty')
  [ -n "$ts" ] || { _S_STATE=INDETERMINATE; _S_REASON="no-task-row"; return 0; }
  row=$(_orca_jq "$_O_WL" --arg t "$task" '[.workers[]|select(.taskId==$t)][0] // empty | [.dispatchId, (.projection.liveness // ""), (.dispatchStatus // ""), (if .observation.agentWait then "1" else "" end)] | join("|")')
  IFS='|' read -r _S_DISP live dstat wait <<<"$row"; : "${_S_DISP:=-}"
  atask=$(_orca_map_task "$dir" "$sg" accept)
  # 3 HELD: a gate sub-goal whose accept Task has a pending gate.
  case "$policy" in gate|'gate!')
    if [ -n "$atask" ]; then
      gate=$(_orca_jq "$_O_GL" --arg t "$atask" '[.gates[]|select(.taskId==$t)]|last // empty|[.id,.status,(.resolution // "")]|join("|")')
      IFS='|' read -r gid gres q <<<"$gate"
      [ "$gres" = pending ] && { _S_STATE=HELD; _S_REASON="gate $gid"; return 0; }
      # 4 (gate half) the gate resolved rework
      [ "$gres" = resolved ] && [ "$q" = rework ] && { _S_STATE=BLOCKED; _S_REASON="rework"; return 0; }
    fi ;;
  esac
  # 4 BLOCKED: a blocked event for the latest Dispatch, or the Task itself is blocked.
  bnote=$(_orca_ev_note "$dir" "$sg" "$_S_DISP" blocked)
  if [ -n "$bnote" ]; then
    # A worker-start whose outcome is unknown is not a rejection: the Dispatch may exist. Never relaunched.
    case "$bnote" in
      *"worker-start exit"*) _S_STATE=INDETERMINATE; _S_REASON="start-outcome-unknown" ;;
      *) _S_STATE=BLOCKED; _S_REASON="${bnote#*: }" ;;
    esac
    return 0
  fi
  # 5 DONE-UNSEEN: worker finished, the runner has not consumed it yet.
  if [ "$ts" = completed ]; then
    [ -n "$(_orca_ev_note "$dir" "$sg" "$_S_DISP" 'shipped|blocked')" ] || { _S_STATE=DONE-UNSEEN; return 0; }
    _S_STATE=INDETERMINATE; _S_REASON="completed-and-consumed-but-box-open"; return 0
  fi
  [ "$ts" = blocked ] && { _S_STATE=BLOCKED; _S_REASON="task-blocked"; return 0; }
  # 6 FAILED
  [ "$ts" = failed ] && { _S_STATE=FAILED; _S_REASON="worker_done failed"; return 0; }
  # 7 PARKED, 8 RUNNING
  if [ "$ts" = dispatched ]; then
    [ "$_S_DISP" != "-" ] || { _S_STATE=INDETERMINATE; _S_REASON="no-dispatch-row"; return 0; }
    q=$(_orca_jq "$_O_IB" --arg t "$task" '. as $all | [.messages[]|select(.taskId==$t and (.type=="question" or .type=="escalation")) | select(.id as $i | ([$all.messages[]|select(.replyTo==$i)]|length)==0)] | .[0].type // empty')
    if [ "$live" = exited ]; then _S_STATE=PARKED; _S_REASON=exited   # rule7:exited
    elif [ "$dstat" = stopped ]; then _S_STATE=PARKED; _S_REASON=stopped
    elif [ -n "$wait" ]; then _S_STATE=PARKED; _S_REASON="agent-wait"
    elif [ -n "$q" ]; then _S_STATE=PARKED; _S_REASON="$q"
    elif [ "${_O_BW:-}" ] && [ "$(_orca_jq "$_O_BW" '.orca')" = ok ] \
         && [ "$(_orca_jq "$_O_BW" --arg i "$slug/$sg" '[.items[]|select(.origin=="mega" and .item==$i)][0].flags // [] | index("PARKED") != null')" = true ]; then
      _S_STATE=PARKED; _S_REASON="idle $(_orca_jq "$_O_BW" --arg i "$slug/$sg" '[.items[]|select(.origin=="mega" and .item==$i)][0].agent.idle_s // "?"')s"
    elif [ "$live" = live ]; then _S_STATE=RUNNING
    else _S_STATE=INDETERMINATE; _S_REASON="liveness-${live:-absent}"
    fi
    return 0
  fi
  # 9 READY, 10 WAITING
  line=$(_sg_line "$roadmap" "$sg")
  case "$ts" in
    ready)   q=$(_sg_deps_blocked "$roadmap" "$line")
             if [ -z "$q" ]; then _S_STATE=READY; else _S_STATE=WAITING; _S_REASON="deps $q"; fi ;;
    pending) q=$(_sg_deps_blocked "$roadmap" "$line"); _S_STATE=WAITING; _S_REASON="${q:+deps $q}"; : "${_S_REASON:=orca-pending}" ;;
    *)       _S_STATE=INDETERMINATE; _S_REASON="unknown-task-status:$ts" ;;
  esac
}

orca_derive() {  # dir -> TSV rows on stdout
  local dir="$1" roadmap="$1/ROADMAP.md" sg policy checked tid kind
  while IFS=$'\t' read -r sg policy checked; do
    _orca_sg_state "$dir" "$sg" "$policy" "$checked"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sg" "$_S_STATE" "${_S_REASON:--}" "$_S_TASK" "$_S_DISP" "$_S_RUNG"
  done < <(_subgoals "$roadmap")
  # A Task mapped from a sub-goal that left the ROADMAP is shown, never touched.
  while IFS=$'\t' read -r tid sg kind; do
    [ "$kind" = work ] || continue
    [ -n "$(_sg_line "$roadmap" "$sg")" ] || printf '%s\tINDETERMINATE\tnot in ROADMAP\t%s\t-\t?\n' "$sg" "$tid"
  done < "$(_orca_dir "$dir")/map.tsv"
}

# ---- tick -----------------------------------------------------------------------------------
_orca_task_status() { _orca_jq "$_O_TL" --arg t "$1" '[.tasks[]|select(.id==$t)][0].status // empty'; }
_orca_latest_disp() { _orca_jq "$_O_WL" --arg t "$1" '[.workers[]|select(.taskId==$t)][0].dispatchId // empty'; }

# An auto sub-goal whose Task Orca reports completed: ground it on the ROADMAP box and the branch.
_orca_consume() {  # dir sg checked
  local dir="$1" sg="$2" checked="$3" task disp repo branch
  task=$(_orca_map_task "$dir" "$sg" work); [ -n "$task" ] || return 0
  [ "$(_orca_task_status "$task")" = completed ] || return 0
  disp=$(_orca_latest_disp "$task"); : "${disp:=-}"
  [ -z "$(_orca_ev_note "$dir" "$sg" "$disp" 'shipped|blocked|held')" ] || return 0
  repo=$(_orca_repo "$dir"); branch=$(_sg_branch "$(_goalfile "$dir" "$sg")" "$sg")
  _TICK_ACTED=$((_TICK_ACTED + 1))
  if [ "$checked" != 1 ]; then
    _orca_ev "$dir" "$sg" blocked "$disp" "$task" "no self-claim"
    echo "[orchestrate] [guardrail] $sg finished in Orca but did not check its ROADMAP box; chain held (no self-claim)." >&2
  elif ! _orca_pushed "$repo" "$branch"; then
    _orca_ev "$dir" "$sg" blocked "$disp" "$task" "branch $branch not on origin"
  else
    _orca_ev "$dir" "$sg" shipped "$disp" "$task" "box checked"
    [ "$disp" = "-" ] || _orca worker-release --dispatch "$disp" --json >/dev/null 2>&1 || true
    _say "[orchestrate] $sg complete (box checked, branch on origin); worker released."
  fi
}

# Start workers for READY sub-goals under the wave cap. Uses the disjointness gate `_wave_gate`
# itself uses; `_wave_gate` is not called because it never admits a gate sub-goal and it demands
# `## Touches` from the first member, and both would stop a serial Orca run.
_orca_dispatch() {  # dir rows
  local dir="$1" rows="$2" roadmap="$1/ROADMAP.md" run repo od gate cap occupied=0 admitted=0
  local sg state reason task disp _r policy gf other deps dep base branch pfile rmodel reffort route_out route_rc out rc line
  local occ_files=() f ok
  run=$(_orca_run_id "$dir"); repo=$(_orca_repo "$dir"); od=$(_orca_dir "$dir")
  gate="$LIB_ROOT/gate/dispatch-gate.sh"; cap="$WAVE_CAP"
  # A gate! sub-goal that is running, held or waiting to be consumed stops every new start.
  while IFS=$'\t' read -r sg state reason task disp _r; do
    policy=$(_subgoals "$roadmap" | awk -F'\t' -v i="$sg" '$1==i{print $2}')
    case "$state" in RUNNING|PARKED) occupied=$((occupied + 1)); occ_files+=("$(_goalfile "$dir" "$sg")") ;; esac
    case "$state:$policy" in RUNNING:'gate!'|PARKED:'gate!'|HELD:'gate!'|DONE-UNSEEN:'gate!') return 0 ;; esac
  done <<<"$rows"
  while IFS=$'\t' read -r sg state reason task disp _r; do
    [ "$state" = READY ] || continue
    policy=$(_subgoals "$roadmap" | awk -F'\t' -v i="$sg" '$1==i{print $2}')
    # prior-Dispatch guard: any Dispatch at all, or a failed start, is an operator matter.
    [ -z "$(_orca_latest_disp "$task")" ] || continue
    [ -z "$(_orca_ev_note "$dir" "$sg" "-" 'blocked')" ] || continue
    [ $((occupied + admitted)) -lt "$cap" ] || break
    gf=$(_goalfile "$dir" "$sg")
    if [ $((occupied + admitted)) -gt 0 ]; then
      [ "$policy" != 'gate!' ] || continue
      [ -n "$gf" ] && [ -n "$(bash "$gate" touches "$gf" 2>/dev/null)" ] || continue
      ok=1
      for other in ${occ_files[@]+"${occ_files[@]}"}; do bash "$gate" disjoint "$gf" "$other" >/dev/null 2>&1 || { ok=0; break; }; done
      [ "$ok" = 1 ] || continue
    fi
    line=$(_sg_line "$roadmap" "$sg")
    deps=$(printf '%s' "$line" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' || true)
    base=""
    for dep in $deps; do base=$(_sg_branch "$(_goalfile "$dir" "$dep")" "$dep"); done
    branch=$(_sg_branch "$gf" "$sg")
    route_out=$(_route "$gf"); route_rc=$?
    IFS=$'\t' read -r rmodel reffort <<<"$route_out"
    if [ "$route_rc" != 0 ]; then _orca_ev "$dir" "$sg" blocked "-" "$task" "routing rejected"; continue; fi
    [ -n "$rmodel" ] && rmodel=$(printf '%s' "$rmodel" | tr '[:upper:]' '[:lower:]')
    if [ -n "$reffort" ] && [ -z "$rmodel" ]; then
      echo "[orchestrate] [orca] WARN: $sg has Effort: without Model:; Orca needs --model for --effort, dropping the effort." >&2; reffort=""
    fi
    pfile="$od/$sg.prompt.md"
    { _build_prompt "$dir" "$sg" ""
      printf '\nORCA WORKER CONTRACT: work on branch %s (Orca made your worktree). When done, push the branch to origin.\n' "$branch"
      case "$policy" in
        gate|'gate!') printf 'This is a gate sub-goal: push the branch and do NOT flip the ROADMAP box. A human decision gate follows.\n' ;;
        *) printf 'Then run: bash %s/orchestrate.sh flip %s %s\n' "$ORCH_DIR" "$(cd "$dir" && pwd -P)" "$sg" ;;
      esac
    } > "$pfile"
    out=$(_orca worker-start --task "$task" --agent "$ORCA_AGENT" --worktree new-top-level --name "$branch" \
          --repo "path:$repo" ${base:+--base-branch "$base"} ${rmodel:+--model "$rmodel"} ${reffort:+--effort "$reffort"} \
          --run "$run" --retry-request "$run-$sg-start" --json 2>&1); rc=$?
    _TICK_ACTED=$((_TICK_ACTED + 1))
    if [ "$rc" != 0 ]; then
      # Outcome unknown: never relaunch. The operator inspects the request and retries by hand.
      _orca_ev "$dir" "$sg" blocked "-" "$task" "worker-start exit $rc"
      echo "[orchestrate] [orca] $sg worker-start exit $rc; not relaunching. $(printf '%s' "$out" | head -1)" >&2
      continue
    fi
    _emit_event "$dir" "$sg" executing "task=$task orca worker-start branch=$branch"
    _say "[orchestrate] $sg started as an Orca worker (task $task, branch $branch)."
    admitted=$((admitted + 1)); occ_files+=("$gf")
    [ "$policy" = 'gate!' ] && break
  done <<<"$rows"
}

# One tick: read, plan, consume, gates and mail, dispatch, stamp. _TICK_ROWS holds the derived
# rows from the reads at the start of the tick. Returns 1 when an Orca read failed.
orca_tick() {  # dir
  local dir="$1" od roadmap="$1/ROADMAP.md" sg policy checked
  od=$(_orca_dir "$dir"); _TICK_ACTED=0; _TICK_ROWS=""
  orca_plan "$dir" || true
  if ! _orca_read "$dir" 1; then
    _TICK_ROWS=$(orca_derive "$dir"); date +%s > "$od/last-tick"; return 1
  fi
  _TICK_ROWS=$(orca_derive "$dir")
  while IFS=$'\t' read -r sg policy checked; do
    case "$policy" in gate|'gate!') ;; *) _orca_consume "$dir" "$sg" "$checked" ;; esac
  done < <(_subgoals "$roadmap")
  orca_gate "$dir"
  _orca_dispatch "$dir" "$_TICK_ROWS"
  date +%s > "$od/last-tick"
  return 0
}

# ---- gate -----------------------------------------------------------------------------------
# Gate sub-goals and the inbox. The operator's accept or rework is the only thing that checks a gate
# sub-goal's box. A Delivery is acked only when every message in it has been acted on.
_orca_msg_acted() {  # dir msg-json
  local dir="$1" m="$2" ty id task disp
  ty=$(_orca_jq "$m" '.type // empty'); id=$(_orca_jq "$m" '.id // empty')
  task=$(_orca_jq "$m" '.taskId // empty'); disp=$(_orca_jq "$m" '.dispatchId // empty')
  [ -n "$ty" ] && [ -n "$id" ] || return 1
  [ -n "$task" ] || { [ -n "$disp" ] && task=$(_orca_jq "$_O_WL" --arg d "$disp" '[.workers[]|select(.dispatchId==$d)][0].taskId // empty'); }
  case "$ty" in
    heartbeat) return 0 ;;
    worker_done)
      [ -n "$task" ] || return 1
      [ "$(_orca_task_status "$task")" = failed ] && return 0
      [ -n "$disp" ] || disp=$(_orca_latest_disp "$task")
      local sg; sg=$(awk -F'\t' -v t="$task" '$1==t{print $2; exit}' "$(_orca_dir "$dir")/map.tsv")
      [ -n "$sg" ] && [ -n "$(_orca_ev_note "$dir" "$sg" "${disp:--}" 'shipped|blocked|held')" ] ;;
    question)
      [ "$(_orca_jq "$_O_IB" --arg i "$id" '[.messages[]|select(.replyTo==$i)]|length')" -gt 0 ] ;;
    escalation)
      [ "$(_orca_jq "$_O_IB" --arg i "$id" '[.messages[]|select(.replyTo==$i)]|length')" -gt 0 ] && return 0
      [ -n "$task" ] && [ "$(_orca_task_status "$task")" != dispatched ] ;;
    *) return 1 ;;
  esac
}

orca_gate() {  # dir
  local dir="$1" roadmap="$1/ROADMAP.md" run sg policy checked task atask ts disp repo branch sha gate gid gstat gres out m did all
  run=$(_orca_run_id "$dir"); repo=$(_orca_repo "$dir")
  while IFS=$'\t' read -r sg policy checked; do
    case "$policy" in gate|'gate!') ;; *) continue ;; esac
    task=$(_orca_map_task "$dir" "$sg" work); atask=$(_orca_map_task "$dir" "$sg" accept)
    [ -n "$task" ] && [ -n "$atask" ] || continue
    branch=$(_sg_branch "$(_goalfile "$dir" "$sg")" "$sg")
    gate=$(_orca_jq "$_O_GL" --arg t "$atask" '[.gates[]|select(.taskId==$t)]|last // empty|[.id,.status,(.resolution // "")]|join("|")')
    IFS='|' read -r gid gstat gres <<<"$gate"
    # Worker finished: open the accept gate once, on the accept Task, when the branch is on origin.
    ts=$(_orca_task_status "$task"); disp=$(_orca_latest_disp "$task"); : "${disp:=-}"
    if [ "$ts" = completed ] && [ -z "$gate" ] && [ -z "$(_orca_ev_note "$dir" "$sg" "$disp" 'shipped|blocked|held')" ]; then
      _TICK_ACTED=$((_TICK_ACTED + 1))
      if _orca_pushed "$repo" "$branch"; then
        sha=$(_orca_sha "$repo" "$branch")
        out=$(_orca gate-create --task "$atask" --question "Accept $sg: branch $branch at $sha?" \
              --options '["accept","rework"]' --retry-request "$run-$sg-accept-gate" --json 2>/dev/null) \
          && { gid=$(printf '%s' "$out" | jq -r '.id // .gate.id // empty'); _orca_ev "$dir" "$sg" held "$disp" "$task" "awaiting gate $gid"
               [ "$disp" = "-" ] || _orca worker-release --dispatch "$disp" --json >/dev/null 2>&1 || true; } \
          || echo "[orchestrate] [orca] gate-create for $sg failed; will retry next tick." >&2
      else
        _orca_ev "$dir" "$sg" blocked "$disp" "$task" "branch $branch not on origin"
      fi
    fi
    # Operator accepted: flip the box (a human decision, not the worker's word), then close the accept Task.
    if [ "$gstat" = resolved ] && [ "$gres" = accept ]; then
      if [ "$checked" != 1 ]; then
        cmd_flip "$dir" "$sg" >/dev/null 2>&1 && { _emit_event "$dir" "$sg" shipped "gate $gid accept"; _TICK_ACTED=$((_TICK_ACTED + 1)); }
      fi
      if [ "$(_orca_task_status "$atask")" != completed ]; then
        _orca task-update --id "$atask" --status completed --run "$run" --json >/dev/null 2>&1 && _TICK_ACTED=$((_TICK_ACTED + 1))
      fi
    fi
  done < <(_subgoals "$roadmap")
  # Inbox: ack the oldest Delivery only when every message in it has been acted on.
  did=$(_orca_jq "$_O_CK" '.delivery.id // empty')
  [ -n "$did" ] || return 0
  all=1
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    _orca_msg_acted "$dir" "$m" || { all=0; break; }
  done < <(_orca_jq "$_O_CK" -c '.delivery.messages[]?')
  if [ "$all" = 1 ]; then
    _orca check --run "$run" --ack "$did" --json >/dev/null 2>&1 && _TICK_ACTED=$((_TICK_ACTED + 1))
  fi
  return 0
}

# ---- run ------------------------------------------------------------------------------------
_orca_version_ok() {  # version-text
  local v a b c ma mb mc
  v=$(printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); [ -n "$v" ] || return 1
  IFS=. read -r a b c <<<"$v"; IFS=. read -r ma mb mc <<<"$ORCA_MIN_VERSION"
  [ $((a * 1000000 * 1000000 + b * 1000000 + c)) -ge $((ma * 1000000 * 1000000 + mb * 1000000 + mc)) ]
}

# File-only pre-flight, before any Orca call: Harness, Model tier, SG-dependency fan-in.
_orca_preflight_files() {  # dir
  local dir="$1" roadmap="$1/ROADMAP.md" sg policy checked gf h line n
  while IFS=$'\t' read -r sg policy checked; do
    [ "$checked" = 0 ] || continue
    gf=$(_goalfile "$dir" "$sg")
    h=$(_harness_of "$gf") || return 64
    [ "$h" = claude ] || { echo "orchestrate: Harness: '$h' in $gf is not supported under --backend orca (claude only)" >&2; return 64; }
    _route "$gf" >/dev/null || return 64
    line=$(_sg_line "$roadmap" "$sg")
    n=$(printf '%s' "$line" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' | wc -l | tr -d ' ')
    [ "$n" -le 1 ] || { echo "orchestrate: $sg has $n SG dependencies; --backend orca supports one (no merge step without PRs)" >&2; return 64; }
  done < <(_subgoals "$roadmap")
  return 0
}

_orca_all_checked() { [ "$(_subgoals "$1/ROADMAP.md" | awk -F'\t' '$3==0{n++} END{print n+0}')" = 0 ]; }

orca_run() {  # dir dry
  local dir="$1" dry="${2:-0}" od lockdir out ticks=0 errs=0 wait gate_since="" now row_sg row_reason row
  _orca_preflight_files "$dir" || return 64
  if [ "$dry" = 1 ]; then
    _say "[plan] mega-goal: $dir (--backend orca --dry-run: no Orca call, no lock)"
    local sg policy checked line
    while IFS=$'\t' read -r sg policy checked; do
      [ "$checked" = 0 ] || continue
      line=$(_sg_line "$dir/ROADMAP.md" "$sg")
      _say "  task $sg ($policy) deps: $(printf '%s' "$line" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' | tr '\n' ' ')"
      case "$policy" in gate|'gate!') _say "  task $sg:accept (never dispatched)" ;; esac
    done < <(_subgoals "$dir/ROADMAP.md")
    return 0
  fi
  out=$("$ORCA_CMD" --version 2>/dev/null) || { echo "orchestrate: orca-unreachable: --version exit $?" >&2; return 1; }
  _orca_version_ok "$out" || { echo "orchestrate: orca-too-old: $(printf '%s' "$out" | head -1) (need $ORCA_MIN_VERSION or later)" >&2; return 64; }
  od=$(_orca_dir "$dir"); mkdir -p "$od"; lockdir="$od/run.lock"; _TICK_ACTED=0
  if ! mkdir "$lockdir" 2>/dev/null; then
    if _lock_stale "$lockdir"; then _lock_reclaim "$lockdir"; fi
    if ! mkdir "$lockdir" 2>/dev/null; then
      echo "orchestrate: another runner holds $lockdir (pid $(tr -dc '0-9' < "$lockdir/pid" 2>/dev/null)); exiting" >&2
      return 75
    fi
  fi
  printf '%s\n' "$$" > "$lockdir/pid"
  # shellcheck disable=SC2064
  trap "_unlock '$lockdir'" EXIT
  while :; do
    if _orca_all_checked "$dir"; then
      _unlock "$lockdir"; trap - EXIT
      if [ "${TIER4_CLOSE:-1}" = 1 ]; then _tier4_close "$dir" "$dir/ROADMAP.md"; return $?; fi
      _say "[orchestrate] all sub-goals checked; done."; return 0
    fi
    if [ -n "${ORCA_MAX_TICKS:-}" ] && [ "$ticks" -ge "$ORCA_MAX_TICKS" ]; then
      [ "$ticks" -gt 0 ] || { orca_plan "$dir" || true; }
      _unlock "$lockdir"; trap - EXIT; _say "[orchestrate] tick bound reached ($ticks)."; return 0
    fi
    ticks=$((ticks + 1))
    if orca_tick "$dir"; then
      errs=0
    else
      errs=$((errs + 1))
      echo "[orchestrate] [orca] tick read failed ($errs/$ORCA_ERROR_LIMIT): $_ORCA_FAIL" >&2
      if [ "$errs" -ge "$ORCA_ERROR_LIMIT" ]; then
        _unlock "$lockdir"; trap - EXIT
        echo "[orchestrate] halted: orca-unreachable: $_ORCA_FAIL" >&2; return 1
      fi
      wait=$((ORCA_POLL_SECS * (1 << errs))); [ "$wait" -le 300 ] || wait=300
      sleep "$wait"; continue
    fi
    # Gate timeout: a gate pending past the limit ends the run with the SG still HELD; a new run resumes.
    row_sg=$(printf '%s\n' "$_TICK_ROWS" | awk -F'\t' '$2=="HELD"{print $1; exit}')
    if [ -n "$row_sg" ]; then
      now=$(date +%s); [ -n "$gate_since" ] || gate_since=$now
      if [ $((now - gate_since)) -ge "$ORCA_GATE_TIMEOUT_SECS" ]; then
        row_reason=$(printf '%s\n' "$_TICK_ROWS" | awk -F'\t' '$2=="HELD"{sub(/^gate /,"",$3); print $3; exit}')
        _unlock "$lockdir"; trap - EXIT
        _say "held: $row_sg awaiting gate $row_reason"; return 0
      fi
    else
      gate_since=""
    fi
    # Nothing runnable, running or held, and this tick changed nothing: halt with the first reason.
    if [ "$_TICK_ACTED" = 0 ] && ! printf '%s\n' "$_TICK_ROWS" | awk -F'\t' '$2 ~ /^(READY|RUNNING|PARKED|HELD|DONE-UNSEEN|INDETERMINATE)$/{f=1} END{exit !f}' \
       && ! _orca_all_checked "$dir"; then
      row=$(printf '%s\n' "$_TICK_ROWS" | awk -F'\t' '$2!="DONE"{print $1" "$2" "$3; exit}')
      _unlock "$lockdir"; trap - EXIT
      echo "[orchestrate] halted: nothing runnable, running or held ($row)" >&2; return 1
    fi
    sleep "$ORCA_POLL_SECS"
  done
}

# ---- status ---------------------------------------------------------------------------------
cmd_status() {  # dir
  local dir="${1:-}" od pid alive ck age oldest out
  [ -f "$dir/ROADMAP.md" ] || { echo "no ROADMAP.md in '$dir'" >&2; return 64; }
  od=$(_orca_dir "$dir")
  [ -f "$od/run" ] || { echo "no Orca run for '$dir'" >&2; return 3; }
  _TICK_ACTED=0
  _orca_read "$dir" 0 || true
  printf 'sg\tstate\treason\ttask\tdispatch\trung\n'
  orca_derive "$dir"
  pid=$(tr -dc '0-9' < "$od/run.lock/pid" 2>/dev/null || true)
  if [ -z "$pid" ]; then alive="no runner"; elif kill -0 "$pid" 2>/dev/null; then alive="runner pid $pid alive"; else alive="runner pid $pid dead"; fi
  ck=$(cat "$od/last-tick" 2>/dev/null || true)
  if [ -n "$ck" ]; then age="$(( $(date +%s) - ck ))s ago"; else age="never"; fi
  oldest="?"
  if [ -n "${_O_OK:-}" ] && [ "$_O_OK" = 1 ]; then
    out=$(_orca check --run "$(_orca_run_id "$dir")" --peek --json 2>/dev/null) || out=""
    if [ -n "$out" ]; then
      oldest=$(printf '%s' "$out" | jq -r 'def secs: if type=="number" then (if .>1e12 then ./1000 else . end) else (sub("\\.[0-9]+";"")|fromdateiso8601) end;
        [.messages[]?.createdAt] | if length==0 then "none" else ((now - (map(secs)|min))|floor|tostring) + "s" end' 2>/dev/null || echo '?')
    fi
  fi
  printf '# %s; last tick %s; oldest unacked delivery: %s\n' "$alive" "$age" "$oldest"
}

# ---- reset ----------------------------------------------------------------------------------
# Rollback for ONE run: stop and release this Run's own Dispatches, block its unfinished Tasks, move
# the map aside. Never `orchestration reset` (global). Worktrees and branches stay.
orca_reset() {  # dir
  local dir="$1" od run wl tl d live dstat tid sg kind bad="" pid ts
  od=$(_orca_dir "$dir"); run=$(_orca_run_id "$dir")
  [ -n "$run" ] || { echo "orca-reset: no Orca run for '$dir'" >&2; return 1; }
  pid=$(tr -dc '0-9' < "$od/run.lock/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "orca-reset: runner pid $pid is alive; stop it first" >&2; return 75; fi
  _orca_get wl worker-list --run "$run" --json || { echo "orca-reset: $_ORCA_FAIL" >&2; return 1; }
  _orca_get tl task-list --run "$run" --json || { echo "orca-reset: $_ORCA_FAIL" >&2; return 1; }
  while IFS='|' read -r d live dstat; do
    [ -n "$d" ] || continue
    if [ "$live" != exited ] && [ "$dstat" != stopped ]; then
      _orca worker-stop --dispatch "$d" --json >/dev/null 2>&1 || bad="$bad $d"
    fi
    _orca worker-release --dispatch "$d" --json >/dev/null 2>&1 || bad="$bad $d"
  done < <(printf '%s' "$wl" | jq -r '.workers[] | [.dispatchId, (.projection.liveness // ""), (.dispatchStatus // "")] | join("|")')
  while IFS=$'\t' read -r tid sg kind; do
    [ -n "$tid" ] || continue
    ts=$(printf '%s' "$tl" | jq -r --arg t "$tid" '[.tasks[]|select(.id==$t)][0].status // empty')
    [ "$ts" = completed ] && continue
    _orca task-update --id "$tid" --status blocked --run "$run" --json >/dev/null 2>&1 || bad="$bad $tid"
  done < "$od/map.tsv"
  ts=$(date +%s)
  mv -f "$od/map.tsv" "$od/map.tsv.reset-$ts" 2>/dev/null
  mv -f "$od/run" "$od/run.reset-$ts" 2>/dev/null
  if [ -n "$bad" ]; then echo "orca-reset: could not settle:$bad" >&2; return 1; fi
  _say "[orchestrate] orca-reset: run $run settled; map moved aside."
}
