# wrap-apply.sh -- the apply verb and its helpers; sourced by lib/wrap/wrap.sh.


_scanned_tip() { awk -v b="$1" '$1 == b { print $2 }' "$TIPS_FILE"; }


# _wt_locked <worktree path> -- 0 when the worktree carries a lock. git keeps the lock as a
# `locked` file in that worktree's admin directory, the same state `worktree list` reports.
_wt_locked() {
  local gd
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  [ -n "$gd" ] && [ -f "${gd}/locked" ]
}

# _wt_lock_pid <worktree path> -- echoes the pid named in the worktree's lock reason, empty when
# unlocked or the reason names none. The Agent tool writes a reason shaped like
# "claude agent <id> (pid 47291 start ...)".
_wt_lock_pid() {
  local gd
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return
  [ -f "${gd}/locked" ] || return
  grep -oE 'pid [0-9]+' "${gd}/locked" 2>/dev/null | grep -oE '[0-9]+' | head -1
}

# _wt_lock_live <worktree path> -- 0 when the lock names a pid that is still alive.
_wt_lock_live() {
  local pid
  pid="$(_wt_lock_pid "$1")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# _wt_cleared <repo> <worktree path> -- 0 when the path is gone AND the list no longer names it.
# A removal that cannot delete the directory (a read-only parent) still prunes the admin entry,
# so neither half alone proves the worktree went. The removal is believed only after both.
_wt_cleared() {
  [ -e "$2" ] && return 1
  git -C "$1" worktree list --porcelain -z 2>/dev/null | tr '\0' '\n' \
    | grep -qxF "worktree $2" && return 1
  return 0
}

# _wt_busy <worktree path> -- 0 when a live process outside this wrap run holds the worktree:
# its current directory or an open file or mapping sits at or under the path. Sets BUSY_MSG to
# the one-line `SKIP <wt>: busy, held by pid <pid> (<command>)` (plus `and N more`). A
# subagent that reported done can still run a headless browser, a blocked `cp -i` or a test
# loop in its worktree; removing the directory under it makes every later write vanish. The
# form is one whole-system `lsof -Fpcn` filtered by path prefix: about 0.3s on a worktree of
# any size, where `lsof +D <wt>` walks the tree (3.6s on a 160k-file one). This run's own pid,
# its descendants and its ancestors never count: they hold the path only because the operator
# or a caller ran wrap from inside it. So does a pipeline reader: a process whose stdin is a
# pipe and whose process group is wrap's own or that of a shell above it (`timeout` puts wrap in
# a group of its own). The `| tail -6` of `wrap land <wt> | tail -6` inherits the shell's cwd
# inside the worktree, lives only until wrap exits, and would otherwise read as a holder that
# never leaves. A background job (stdin not a pipe) or one from an earlier call (another
# group) still counts.
# KIT_WRAP_SKIP_BUSY_CHECK=1 turns the check off. Without lsof it prints one NOTE per run and
# answers "not busy", today's behavior.
BUSY_MSG=""
BUSY_PID=""
_WT_BUSY_NOTED=0
_WT_BUSY_LAZY_SNAP=0
_WT_LSOF_SNAP=""
_WT_PSNAP_SNAP=""

_wt_busy_snap_init() {
  _wt_busy_snap_clear
  _WT_BUSY_LAZY_SNAP=1
}

_wt_busy_snap_clear() {
  [ -n "$_WT_LSOF_SNAP" ] && rm -f "$_WT_LSOF_SNAP"
  [ -n "$_WT_PSNAP_SNAP" ] && rm -f "$_WT_PSNAP_SNAP"
  _WT_LSOF_SNAP=""
  _WT_PSNAP_SNAP=""
  _WT_BUSY_LAZY_SNAP=0
}

_wt_busy() {
  local wt="$1" mode="${2:-snap}" canon holders psnap pid cmd n
  BUSY_MSG=""
  BUSY_PID=""
  [ "${KIT_WRAP_SKIP_BUSY_CHECK:-0}" = 1 ] && return 1
  if ! command -v lsof >/dev/null 2>&1; then
    if [ "$_WT_BUSY_NOTED" = 0 ]; then
      echo "     NOTE: busy check unavailable (no lsof)"; _WT_BUSY_NOTED=1
    fi
    return 1
  fi
  canon="$(cd "$wt" 2>/dev/null && pwd -P)" || return 1
  if [ "$mode" != "live" ] && [ "$_WT_BUSY_LAZY_SNAP" = 1 ] && [ -z "$_WT_LSOF_SNAP" ]; then
    _WT_LSOF_SNAP="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || _WT_LSOF_SNAP=""
    _WT_PSNAP_SNAP="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || _WT_PSNAP_SNAP=""
    if [ -n "$_WT_LSOF_SNAP" ] && [ -n "$_WT_PSNAP_SNAP" ]; then
      ( cd / && lsof -nP -w +c 0 -Fpcftn 2>/dev/null ) > "$_WT_LSOF_SNAP"
      ps -axo pid=,ppid=,pgid=,comm= 2>/dev/null > "$_WT_PSNAP_SNAP"
    else
      rm -f "$_WT_LSOF_SNAP" "$_WT_PSNAP_SNAP"
      _WT_LSOF_SNAP=""; _WT_PSNAP_SNAP=""
    fi
  fi
  if [ "$mode" != "live" ] && [ -n "$_WT_PSNAP_SNAP" ] && [ -r "$_WT_PSNAP_SNAP" ]; then
    psnap="$(cat "$_WT_PSNAP_SNAP" 2>/dev/null)"
  else
    psnap="$(ps -axo pid=,ppid=,pgid=,comm= 2>/dev/null)"
  fi
  # lsof runs from /, so this shell's own cwd inside the worktree cannot match.
  local awk_prog='
    BEGIN {
      n = split(ENVIRON["PSNAP"], rows, "\n")
      for (i = 1; i <= n; i++) {
        split(rows[i], f, " ")
        if (f[1] == "") continue
        par[f[1]] = f[2]; grp[f[1]] = f[3]
        c = f[4]; sub(/.*\//, "", c); sub(/^-/, "", c); sh[f[1]] = (c ~ /^(sh|bash|zsh|fish|dash|ksh)$/)
      }
      self = ENVIRON["SELF"]; wt = ENVIRON["WT"]; wl = length(wt)
      if (grp[self] + 0 > 1) callgrp[grp[self]] = 1
      for (p = self; p != "" && p + 0 > 1 && !(p in anc); p = par[p]) {
        anc[p] = 1
        if (sh[p] && grp[p] + 0 > 1) callgrp[grp[p]] = 1
      }
    }
    function mine(pid,   p, hops) {
      if (pid in anc) return 1
      if (pipein[pid] && (grp[pid] in callgrp)) return 1
      for (p = pid; p != "" && p + 0 > 1 && hops < 64; p = par[p]) { if (p == self) return 1; hops++ }
      return 0
    }
    /^p/ { pid = substr($0, 2); fd = ""; next }
    /^c/ { cmdof[pid] = substr($0, 2); next }
    /^f/ { fd = substr($0, 2); next }
    /^t/ { if (fd == "0" && ($0 == "tPIPE" || $0 == "tFIFO")) pipein[pid] = 1; next }
    /^n/ {
      name = substr($0, 2)
      if (name != wt && substr(name, 1, wl + 1) != wt "/") next
      if (pid in seen) next
      seen[pid] = 1
      order[++k] = pid
    }
    END {
      for (i = 1; i <= k; i++) {
        if (mine(order[i])) continue
        if (count == 0) { fpid = order[i]; fcmd = cmdof[order[i]] }
        count++
      }
      if (count > 0) printf "%s\t%s\t%d\n", fpid, fcmd, count
    }
  '
  if [ "$mode" != "live" ] && [ -n "$_WT_LSOF_SNAP" ] && [ -r "$_WT_LSOF_SNAP" ]; then
    holders="$(WT="$canon" SELF="$$" PSNAP="$psnap" awk "$awk_prog" < "$_WT_LSOF_SNAP")"
  else
    holders="$(cd / && lsof -nP -w +c 0 -Fpcftn 2>/dev/null | WT="$canon" SELF="$$" PSNAP="$psnap" awk "$awk_prog")"
  fi
  [ -n "$holders" ] || return 1
  IFS=$'\t' read -r pid cmd n <<< "$holders"
  BUSY_PID="$pid"
  BUSY_MSG="SKIP ${wt}: busy, held by pid ${pid} (${cmd})"
  [ "${n:-1}" -gt 1 ] 2>/dev/null && BUSY_MSG="${BUSY_MSG} and $(( n - 1 )) more"
  return 0
}

_WT_CALLER_CWDS=""

# _wt_caller_cwds_init -- caches canonical caller working directories (this process plus up to
# 8 ancestor processes via targeted lsof -p -d cwd) so cleanup never removes its own worktree.
_wt_caller_cwds_init() {
  local nl=$'\n' c="" pids=""
  _WT_CALLER_CWDS=""
  if [ -n "${_WRAP_CALLER_PWD:-}" ]; then
    c="$(cd "$_WRAP_CALLER_PWD" 2>/dev/null && pwd -P)" || c="$_WRAP_CALLER_PWD"
    [ -n "$c" ] && _WT_CALLER_CWDS="${_WT_CALLER_CWDS}${c}${nl}"
  fi
  c="$(pwd -P 2>/dev/null || pwd)"
  if [ -n "$c" ]; then
    case "${nl}${_WT_CALLER_CWDS}" in
      *"${nl}${c}${nl}"*) ;;
      *) _WT_CALLER_CWDS="${_WT_CALLER_CWDS}${c}${nl}" ;;
    esac
  fi
  if command -v lsof >/dev/null 2>&1; then
    pids="$(ps -axo pid=,ppid= 2>/dev/null | awk -v start="${PPID:-0}" '
      { par[$1] = $2 }
      END {
        p = start
        for (i = 0; i < 8 && p != "" && p + 0 > 1; i++) {
          out = (out == "" ? p : out "," p)
          if (p == par[p]) break
          p = par[p]
        }
        if (out != "") print out
      }')"
    if [ -n "$pids" ]; then
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        case "${nl}${_WT_CALLER_CWDS}" in
          *"${nl}${c}${nl}"*) ;;
          *) _WT_CALLER_CWDS="${_WT_CALLER_CWDS}${c}${nl}" ;;
        esac
      done < <(lsof -nP -w -a -p "$pids" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    fi
  fi
}

_wt_is_caller_cwd() {
  local wt_c="$1" c=""
  [ -n "$wt_c" ] && [ -n "$_WT_CALLER_CWDS" ] || return 1
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$c" in
      "$wt_c"|"$wt_c"/*) return 0 ;;
    esac
  done <<< "$_WT_CALLER_CWDS"
  return 1
}

_SWEEP_ROWS_FILE=""
_APPLY_WORKSPACE_RM=""

# _run_seam_workspace_rm <cmd> <worktree> <repo> -- invokes the optional wrap.workspace_rm seam
# with `<worktree> <repo>` and a 20s (or WRAP_WORKSPACE_RM_TIMEOUT) cap. Prints `ok`, `failed`,
# `timeout`, or `null` when empty. Never alters exit code or undoes a removal.
_run_seam_workspace_rm() {
  local cmd_str="${1:-}" wt="$2" repo="$3"
  [ -n "$cmd_str" ] || { printf 'null\n'; return 0; }
  local secs="${WRAP_WORKSPACE_RM_TIMEOUT:-20}"
  case "$secs" in ''|*[!0-9]*|0) secs=20 ;; esac

  local -a words=()
  set -f
  # shellcheck disable=SC2206
  words=($cmd_str)
  set +f
  [ "${#words[@]}" -gt 0 ] || { printf 'null\n'; return 0; }
  case "${words[0]}" in
    "~") words[0]="$HOME" ;;
    "~/"*) words[0]="$HOME/${words[0]#\~/}" ;;
  esac

  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "${words[@]}" "$wt" "$repo" </dev/null >/dev/null 2>&1; rc=$?
    case "$rc" in
      0) printf 'ok\n' ;;
      124) printf 'timeout\n' ;;
      *) printf 'failed\n' ;;
    esac
    return 0
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "${words[@]}" "$wt" "$repo" </dev/null >/dev/null 2>&1; rc=$?
    case "$rc" in
      0) printf 'ok\n' ;;
      124) printf 'timeout\n' ;;
      *) printf 'failed\n' ;;
    esac
    return 0
  fi

  local cpid wpid to_flag
  to_flag="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || to_flag=""
  rm -f "$to_flag"
  "${words[@]}" "$wt" "$repo" </dev/null >/dev/null 2>&1 &
  cpid=$!
  (
    sleep "$secs"
    if kill -0 "$cpid" 2>/dev/null; then
      [ -n "$to_flag" ] && : > "$to_flag"
      kill -TERM "$cpid" 2>/dev/null || true
      sleep 1
      kill -KILL "$cpid" 2>/dev/null || true
    fi
  ) >/dev/null 2>&1 &
  wpid=$!
  wait "$cpid" 2>/dev/null; rc=$?
  kill "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  if [ -n "$to_flag" ] && [ -e "$to_flag" ]; then
    rm -f "$to_flag"
    printf 'timeout\n'
  elif [ "$rc" -eq 0 ]; then
    printf 'ok\n'
  else
    printf 'failed\n'
  fi
  return 0
}

_sweep_row_pr_info() {
  local repo="$1" def="$2" ghs="$3" b="$4" tip="$5"
  [ -n "$b" ] || { printf 'null\tnull\n'; return 0; }
  if [ -n "$_APPLY_PRS_MERGED" ] || [ -n "$_APPLY_PRS_OPEN" ] || [ -n "$_APPLY_PRS_CLOSED" ]; then
    _branch_pr_info "$b" "$tip" "$def" "$_APPLY_PRS_MERGED" "$_APPLY_PRS_OPEN" "$_APPLY_PRS_CLOSED"
  else
    _branch_pr_info_fallback "$repo" "$def" "$ghs" "$b" "$tip"
  fi
}

_sweep_wt_holder() {
  local wt="$1" pid=""
  if _wt_locked "$wt" && _wt_lock_live "$wt"; then
    pid="$(_wt_lock_pid "$wt")"
  fi
  if [ -z "$pid" ] && _wt_busy "$wt"; then
    pid="$BUSY_PID"
  fi
  case "$pid" in
    ''|*[!0-9]*) printf 'null\n' ;;
    *) printf '%s\n' "$pid" ;;
  esac
}

# _emit_sweep_row <kind> <path> <branch> <verdict> <reason> <pr> <pr_state> <dirty> <holder> <own_commits> <workspace_rm>
_emit_sweep_row() {
  [ -n "${_SWEEP_ROWS_FILE:-}" ] || return 0
  local kind="$1" path="$2" branch="$3" verdict="$4" reason="$5"
  local pr="$6" pr_state="$7" dirty="$8" holder="$9" own_commits="${10}" workspace_rm="${11}"
  jq -cn \
    --arg kind "$kind" \
    --arg path "$path" \
    --arg branch "$branch" \
    --arg verdict "$verdict" \
    --arg reason "$reason" \
    --arg pr "$pr" \
    --arg pr_state "$pr_state" \
    --arg dirty "$dirty" \
    --arg holder "$holder" \
    --arg own_commits "$own_commits" \
    --arg workspace_rm "$workspace_rm" '
    {
      kind: $kind,
      path: (if $path == "" then null else $path end),
      branch: (if $branch == "" then null else $branch end),
      verdict: $verdict,
      reason: $reason,
      pr: (if ($pr | test("^[0-9]+$")) then ($pr | tonumber) else null end),
      pr_state: (if ($pr_state == "" or $pr_state == "null") then null else $pr_state end),
      dirty: (if $dirty == "true" then true elif $dirty == "false" then false else null end),
      holder: (if ($holder | test("^[0-9]+$")) then ($holder | tonumber) else null end),
      own_commits: (if ($own_commits | test("^[0-9]+$")) then ($own_commits | tonumber) else null end),
      workspace_rm: (if ($workspace_rm == "" or $workspace_rm == "null") then null else $workspace_rm end)
    }' >> "$_SWEEP_ROWS_FILE"
}

# A worktree path may carry a newline, so the record stream is NUL-delimited: `--porcelain -z`
# terminates every attribute with NUL, which keeps the path whole.
_apply_worktrees() {
  local repo="$1" def="$2" cur="$3" fetch_succeeded="$4" ghs="$5"
  local main_wt rec wt wt_c wtb lcode lreason proof lock verdict tip scanned wrm_res
  local pr_n pr_st own_c hpid
  _APPLY_WORKSPACE_RM=""
  [ "$APPLY" = 1 ] && _APPLY_WORKSPACE_RM="$(kit_config_get_root wrap.workspace_rm "")"
  [ -z "${_SWEEP_ROWS_FILE:-}" ] || _wt_caller_cwds_init
  echo "-- worktrees:"
  [ -n "$OWN_SET" ] && echo "     scope --own: only the named worktrees are candidates"
  main_wt="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  main_wt="${main_wt%/.git}"; main_wt="${main_wt%/}"
  main_wt="$(cd "$main_wt" 2>/dev/null && pwd -P)"
  while IFS= read -r -d '' rec; do
    case "$rec" in "worktree "*) wt="${rec#worktree }" ;; *) continue ;; esac
    wt_c="$(cd "$wt" 2>/dev/null && pwd -P)"
    if [ -z "$wt_c" ]; then
      echo "     SKIP ${wt}: unresolvable"
      _emit_sweep_row worktree "$wt" "" error "unresolvable" null null null null null null
      continue
    fi
    if [ -n "$OWN_SET" ]; then
      # --own is the operator's worktree opt-in for the named set only; an unnamed
      # entry is skipped without a line so a shared repo stays readable. Seen is
      # marked before the guards so a refused named worktree is never misreported.
      if printf '%s' "$OWN_SET" | grep -qxF "$wt_c"; then
        OWN_SEEN="${OWN_SEEN}${wt_c}"$'\n'
      else
        continue
      fi
    fi
    [ "$wt_c" = "$main_wt" ] && continue
    # The named worktrees' branches are the whole scope of the origin sweep under --own, so they
    # are read before any guard or removal can drop the worktree. A detached worktree adds nothing.
    if [ -n "$OWN_SET" ]; then
      wtb="$(git -C "$wt" branch --show-current 2>/dev/null)"
      [ -z "$wtb" ] || OWN_BRANCHES="${OWN_BRANCHES}${wtb}"$'\n'
    fi
    if [ -z "$OWN_SET" ] && [ "$WORKTREES" != 1 ]; then
      echo "     SKIP ${wt}: --worktrees not given (the operator must ask for worktree cleanup)"
      _emit_sweep_row worktree "$wt" "" keep "--worktrees not given" null null null null null null
      continue
    fi
    if [ -n "${_SWEEP_ROWS_FILE:-}" ] && _wt_is_caller_cwd "$wt_c"; then
      echo "     SKIP ${wt}: caller's own worktree (leave it)"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        local _cw_dirty="false"
        [ -n "$(git -C "$wt" status --short 2>/dev/null)" ] && _cw_dirty="true"
        wtb="$(git -C "$wt" branch --show-current 2>/dev/null)"
        tip=""; [ -n "$wtb" ] && tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="null"; [ -n "$wtb" ] && own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "caller's own worktree (leave it)" "$pr_n" "$pr_st" "$_cw_dirty" null "$own_c" null
      fi
      continue
    fi
    if [ -n "$(git -C "$wt" status --short 2>/dev/null)" ]; then
      echo "     SKIP ${wt}: dirty (another session's work stays)"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        wtb="$(git -C "$wt" branch --show-current 2>/dev/null)"
        tip=""; [ -n "$wtb" ] && tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="null"; [ -n "$wtb" ] && own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "dirty (another session's work stays)" "$pr_n" "$pr_st" true "$hpid" "$own_c" null
      fi
      continue
    fi
    wtb="$(git -C "$wt" branch --show-current 2>/dev/null)"
    if [ -z "$wtb" ]; then
      echo "     SKIP ${wt}: detached HEAD (removal could orphan the commit)"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "" keep "detached HEAD (removal could orphan the commit)" null null false "$hpid" null null
      fi
      continue
    fi
    case "$wtb" in "$def"|main|master)
      echo "     SKIP ${wt}: ${wtb} is the default or a protected branch name"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "${wtb} is the default or a protected branch name" null null false "$hpid" null null
      fi
      continue ;;
    esac
    if [ "$wtb" = "$cur" ]; then
      echo "     SKIP ${wt}: ${wtb} is the main checkout's branch"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "${wtb} is the main checkout's branch" "$pr_n" "$pr_st" false "$hpid" "$own_c" null
      fi
      continue
    fi
    if [ "$fetch_succeeded" != 1 ]; then
      echo "     SKIP ${wt}: fetch failed, stale merge proof for ${wtb}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "fetch failed, stale merge proof for ${wtb}" null null false "$hpid" null null
      fi
      continue
    fi
    read -r lcode lreason proof <<< "$(_apply_branch_merged "$repo" "$def" "$ghs" "$wtb")"
    if [ "$lcode" != SAFE ]; then
      local skip_reason
      if [ "${lcode} ${lreason}" = "LEAVE fresh" ]; then
        skip_reason="${proof}"
      else
        skip_reason="${wtb} is not proven merged into ${def} (leave it)"
      fi
      echo "     SKIP ${wt}: ${skip_reason}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "$skip_reason" "$pr_n" "$pr_st" false "$hpid" "$own_c" null
      fi
      continue
    fi
    # The proof above can cost a network round trip, so both destructive inputs are re-read right
    # before the force: `-f -f` overrides a worktree that went dirty, and `-D` discards a commit
    # made since the run's own tip snapshot.
    if [ -n "$(git -C "$wt" status --short 2>/dev/null)" ]; then
      echo "     SKIP ${wt}: went dirty while the proof was read"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "went dirty while the proof was read" "$pr_n" "$pr_st" true "$hpid" "$own_c" null
      fi
      continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
    scanned="$(_scanned_tip "$wtb")"
    if [ -n "$scanned" ] && [ "$tip" != "$scanned" ]; then
      local moved_msg="${wtb} tip moved during this run ($(_short "$scanned") -> $(_short "$tip"))"
      echo "     SKIP ${wt}: ${moved_msg}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        hpid="$(_sweep_wt_holder "$wt")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "$moved_msg" "$pr_n" "$pr_st" false "$hpid" "$own_c" null
      fi
      continue
    fi
    lock="unlocked"; _wt_locked "$wt" && lock="locked"
    if [ "$lock" = "locked" ] && _wt_lock_live "$wt"; then
      local lpid; lpid="$(_wt_lock_pid "$wt")"
      local lmsg="locked by live pid ${lpid} (an agent is still running)"
      echo "     SKIP ${wt}: ${lmsg}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "$lmsg" "$pr_n" "$pr_st" false "$lpid" "$own_c" null
      fi
      continue
    fi
    if _wt_busy "$wt"; then
      echo "     ${BUSY_MSG}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "${BUSY_MSG#SKIP ${wt}: }" "$pr_n" "$pr_st" false "$BUSY_PID" "$own_c" null
      fi
      continue
    fi
    verdict="remove worktree ${wt} [${wtb}, ${lock}] and delete ${wtb} (${proof})"
    if [ "$APPLY" != 1 ]; then
      echo "     WOULD ${verdict}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        _emit_sweep_row worktree "$wt" "$wtb" would_remove "${proof}" "$pr_n" "$pr_st" false null "$own_c" null
      fi
      continue
    fi
    if ! _write_guard "$repo"; then
      echo "     SKIP ${wt}: index.lock held by another writer"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
        _emit_sweep_row worktree "$wt" "$wtb" keep "index.lock held by another writer" "$pr_n" "$pr_st" false null "$own_c" null
      fi
      continue
    fi
    # A lock alone is not proof the run finished: the Agent tool locks every worktree it creates,
    # including one made seconds ago for a subagent still running, so a fresh branch can be a
    # trivial ancestor of origin/<def> while the lock's pid is still alive (checked above, which
    # skips before this point). What remains here is a lock whose pid is dead or absent, safe to
    # override. `-f -f`, not `--force`: one --force refuses a locked worktree outright (`cannot
    # remove a locked working tree`), measured on git 2.55; two overrides the lock once every
    # guard above has passed.
    if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
      IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$wtb" "$tip")"
      own_c="$(_branch_own_commits "$repo" "$def" "$wtb")"
    fi
    if _wt_busy "$wt" live; then
      echo "     ${BUSY_MSG}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        _emit_sweep_row worktree "$wt" "$wtb" keep "${BUSY_MSG#SKIP ${wt}: }" "$pr_n" "$pr_st" false "${BUSY_PID:-null}" "$own_c" null
      fi
      continue
    fi
    run "$repo" "$verdict" git -C "$repo" worktree remove -f -f "$wt"
    if _wt_cleared "$repo" "$wt"; then
      wrm_res="$(_run_seam_workspace_rm "$_APPLY_WORKSPACE_RM" "$wt" "$repo")"
      run "$repo" "delete ${wtb} (${proof}, its ${lock} worktree is gone)" \
        git -C "$repo" branch -D "$wtb"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        _emit_sweep_row worktree "$wt" "$wtb" removed "${proof}" "$pr_n" "$pr_st" false null "$own_c" "$wrm_res"
      fi
    else
      echo "     FAILED ${verdict}: ${wt} survived the removal, ${wtb} not deleted"
      FAILURES=1
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        _emit_sweep_row worktree "$wt" "$wtb" error "${wt} survived the removal, ${wtb} not deleted" "$pr_n" "$pr_st" false null "$own_c" null
      fi
    fi
  done < <(git -C "$repo" worktree list --porcelain -z 2>/dev/null)
  if [ -n "$OWN_SET" ]; then
    local k=1 canon
    while [ "$k" -le "$OWN_N" ]; do
      canon="$(cd "${OWN_PATHS[$k]}" 2>/dev/null && pwd -P)"
      canon="${canon:-${OWN_PATHS[$k]}}"
      printf '%s' "$OWN_SEEN" | grep -qxF "$canon" \
        || echo "     SKIP ${OWN_PATHS[$k]}: not a registered worktree"
      k=$(( k + 1 ))
    done
  fi
}

_apply_branches() {
  local repo="$1" def="$2" cur="$3" fetch_succeeded="$4" ghs="$5"
  echo "-- branches:"
  local b tip scanned lcode lreason ldetail pr_n pr_st own_c wt_held_refs=""
  [ -n "${_SWEEP_ROWS_FILE:-}" ] && wt_held_refs="$(git -C "$repo" worktree list --porcelain 2>/dev/null)"
  for b in $(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/); do
    case "$b" in "$def"|main|master) echo "     SKIP ${b}: default or protected branch name"; continue ;; esac
    if [ "$b" = "$cur" ]; then
      echo "     SKIP ${b}: currently checked out"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$b" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$b")"
        _emit_sweep_row branch "" "$b" keep "currently checked out" "$pr_n" "$pr_st" null null "$own_c" null
      fi
      continue
    fi
    if git -C "$repo" worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/${b}"; then
      echo "     SKIP ${b}: held by a worktree"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ] && [ "$WORKTREES" != 1 ]; then
        tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$b" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$b")"
        _emit_sweep_row branch "" "$b" keep "held by a worktree" "$pr_n" "$pr_st" null null "$own_c" null
      fi
      continue
    fi
    if [ "$fetch_succeeded" != 1 ]; then
      echo "     SKIP ${b}: fetch failed, stale ancestor data"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        _emit_sweep_row branch "" "$b" keep "fetch failed, stale ancestor data" null null null null null null
      fi
      continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
    scanned="$(_scanned_tip "$b")"
    if [ -n "$scanned" ] && [ "$tip" != "$scanned" ]; then
      local moved_msg="tip moved during this run ($(_short "$scanned") -> $(_short "$tip"))"
      echo "     SKIP ${b}: ${moved_msg}"
      if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$b" "$tip")"
        own_c="$(_branch_own_commits "$repo" "$def" "$b")"
        _emit_sweep_row branch "" "$b" keep "$moved_msg" "$pr_n" "$pr_st" null null "$own_c" null
      fi
      continue
    fi
    if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
      IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "$b" "$tip")"
      own_c="$(_branch_own_commits "$repo" "$def" "$b")"
    fi
    # -D, not -d: the proof is wrap's own, against origin/<def>. `branch -d` judges against the
    # branch's OWN upstream (or HEAD when it has none), so it refused a branch that tracks
    # another ref or nothing even though origin/<def> already holds its tip. The proof judges the
    # sha read above, see branch_merged.
    read -r lcode lreason ldetail <<< "$(_apply_branch_merged --tip "$tip" "$repo" "$def" "$ghs" "$b")"
    local b_verdict="keep" b_reason=""
    case "${lcode} ${lreason}" in
      "SAFE ancestor"|"SAFE absorbed")
        b_reason="${ldetail}"
        run "$repo" "delete ${b} (${ldetail})" git -C "$repo" branch -D "$b" ;;
      "SAFE squash")
        b_reason="squash-merged into ${def}, tip matches the PR head"
        run "$repo" "delete ${b} (${b_reason})" \
          git -C "$repo" branch -D "$b" ;;
      "LEAVE fresh")
        b_reason="${ldetail}"
        echo "     SKIP ${b}: ${ldetail}" ;;
      "LEAVE nogh")
        b_reason="${ldetail}, no squash proof available"
        echo "     SKIP ${b}: ${b_reason}" ;;
      "LEAVE tip")
        b_reason="tip $(_short "$tip") != merged PR head $(_short "$ldetail") (unpushed commits, leave it)"
        echo "     SKIP ${b}: ${b_reason}" ;;
      "LEAVE base")
        b_reason="merged into ${ldetail}, not the default branch"
        echo "     SKIP ${b}: ${b_reason}" ;;
      *)
        b_reason="no merged PR found for this head"
        echo "     SKIP ${b}: ${b_reason}" ;;
    esac
    if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
      if [ "$lcode" = SAFE ]; then
        if [ "$APPLY" != 1 ]; then
          b_verdict="would_remove"
        elif ! _ref_exists "$repo" "refs/heads/${b}"; then
          b_verdict="removed"
        else
          b_verdict="error"
        fi
      fi
      _emit_sweep_row branch "" "$b" "$b_verdict" "$b_reason" "$pr_n" "$pr_st" null null "$own_c" null
    fi
  done
}

# _archive_slug <branch> -- an origin-ref-safe slug: lower-case alnum runs joined by `-`,
# trimmed of leading/trailing dashes. Same shape as `_carry_stray_file`'s file slug, so a
# branch name carrying a `/` (e.g. feat/foo) collapses to one path segment under refs/archive/.
_archive_slug() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//'
}

# _apply_archive_unmerged <repo> <default branch> <current branch> <fetch_succeeded> -- opt-in
# (--archive-unmerged, never under --own) sweep: every local branch that is not the current
# or default branch, is not held by a worktree, and carries at least one commit patch
# origin/<default> lacks (`git cherry origin/<default> <branch>` shows a `+`) gets pushed to
# a new origin refs/archive/<slug>-<YYYYMMDD> ref (hidden from the branch list) and, only once that push lands, its local ref
# deleted. No force: an already-existing archive ref refuses the push and the branch stays
# local, reported FAILED. A branch with zero unique patches is already covered by
# `_apply_branches` above (an ancestor or a squash-merged proof) or is simply reported here
# and never deleted under this flag.
_apply_archive_unmerged() {
  local repo="$1" def="$2" cur="$3" fetch_succeeded="$4"
  echo "-- archive unmerged:"
  if [ -n "$OWN_SET" ]; then
    echo "     SKIP archive sweep: --own scopes cleanup to the named worktrees"; return 0
  fi
  if [ -z "$(_origin_url "$repo")" ]; then
    echo "     SKIP archive sweep: no origin remote"; return 0
  fi
  if [ "$fetch_succeeded" != 1 ]; then
    echo "     SKIP archive sweep: fetch failed, stale data"; return 0
  fi
  local b tip pushed cherry n slug ref err first rl
  # Full refs throughout, as in branch_merged: a tag named like the branch once made the push
  # source ambiguous, and a bare origin/<def> can resolve a tag or local branch.
  for b in $(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/); do
    case "$b" in "$def"|main|master) continue ;; esac
    [ "$b" = "$cur" ] && continue
    # A symbolic ref names another branch's work: its guards would check the alias while the
    # push and the delete reached the target.
    if git -C "$repo" symbolic-ref -q "refs/heads/${b}" >/dev/null 2>&1; then
      echo "     SKIP ${b}: a symbolic ref, not a branch of its own"; continue
    fi
    if git -C "$repo" worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/${b}"; then
      echo "     SKIP ${b}: held by a worktree"; continue
    fi
    cherry="$(git -C "$repo" cherry "refs/remotes/origin/${def}" "refs/heads/${b}" 2>/dev/null)" # merged-ok: git cherry counts unique patches for the archive-first sweep, nothing is deleted on it alone
    n="$(printf '%s\n' "$cherry" | grep -c '^+')"
    if [ "$n" -eq 0 ]; then
      echo "     ${b}: nothing unique, left for the merged sweep"; continue
    fi
    slug="$(_archive_slug "$b")"
    ref="refs/archive/${slug}-$(date +%Y%m%d)"
    if [ "$APPLY" != 1 ]; then
      echo "     WOULD archive ${b} -> origin ${ref} (${n} unique commits)"; continue
    fi
    if ! _write_guard "$repo"; then
      echo "     SKIP ${b}: index.lock held by another writer"; continue
    fi
    if ! rl="$(git -C "$repo" ls-remote origin "$ref" 2>/dev/null)"; then
      echo "     FAILED archive ${b}: origin could not be read"; FAILURES=1; continue
    fi
    if [ -n "$(printf '%s\n' "$rl" | awk -v r="$ref" '$2 == r')" ]; then
      echo "     FAILED archive ${b}: origin ${ref} already exists"; FAILURES=1; continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}")"
    if err="$(git -C "$repo" push "--force-with-lease=${ref}:" origin "refs/heads/${b}:${ref}" 2>&1)"; then
      # The local delete is leased to the tip read above, and only once origin holds that
      # tip: a commit made during the push, or an archive ref holding anything else, keeps
      # the branch.
      pushed="$(git -C "$repo" ls-remote origin "$ref" 2>/dev/null \
        | awk -v r="$ref" '$2 == r { print $1 }')"
      if [ -z "$tip" ] || [ "$pushed" != "$tip" ]; then
        echo "     FAILED archive ${b}: origin ${ref} holds $(_short "${pushed:-nothing}"), not the local tip $(_short "${tip:-unread}"); the branch stays"
        FAILURES=1
      # update-ref lacks branch -D's refusals, and the guards above ran before a network push,
      # so the checked-out and worktree-held checks are repeated right before the delete.
      # The list is captured, never piped into `grep -q`: an early grep exit can SIGPIPE the
      # writer, and under pipefail that 141 would read as "not held" and let the delete run.
      elif [ "$(git -C "$repo" symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/${b}" ] \
          || ! _wt_list="$(git -C "$repo" worktree list --porcelain 2>/dev/null)" \
          || case $'\n'"${_wt_list}"$'\n' in *$'\n'"branch refs/heads/${b}"$'\n'*) true ;; *) false ;; esac; then
        echo "     kept ${b}: archived to ${ref}, but it was checked out during the push"
      elif git -C "$repo" update-ref --no-deref -d "refs/heads/${b}" "$tip" >/dev/null 2>&1; then
        git -C "$repo" config --remove-section "branch.${b}" >/dev/null 2>&1
        echo "     archived ${b} -> ${ref}"
      else
        echo "     FAILED archive ${b}: pushed to ${ref} but the local branch delete refused"
        FAILURES=1
      fi
    else
      first="$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | head -1)"
      echo "     FAILED archive ${b}: ${first:-push refused}"
      FAILURES=1
    fi
  done
}

# _ARCHIVE_IGNORED_REGENERABLE -- ignored entries `apply --archive-worktrees` may delete with a
# worktree, because a build or an install recreates them (forms: _ignored_match). Never land's
# list or wrap.land_ignored_allow: those also allow local config such as `.env` and `.envrc`,
# which in a stale worktree may be the only copy.
_ARCHIVE_IGNORED_REGENERABLE="node_modules .wrangler dist build .next coverage *.tsbuildinfo __pycache__ target .pytest_cache/ .venv/ .mypy_cache/ .ruff_cache/ .DS_Store tests/.cache .claude/session-state lib/*/bin/*-rs"

# _wt_status <wt> -- one `git status` read for every archive guard, with --no-optional-locks so
# the read never rewrites a worktree's index. Sets WT_ST_DIRTY and WT_ST_UNMERGED (0/1),
# WT_ST_ODD (1 when an uncommitted path holds a newline or tab, which the newline lists below
# cannot carry), WT_ST_N (non-ignored records), and newline lists: WT_ST_PATHS (every
# non-ignored path, renamed-from included, for the idle age), WT_ST_NEW (untracked, added and
# renamed-to paths, for the secret scan), WT_ST_NESTED (`??` directories holding .git) and
# WT_ST_IGNORED (`!!` paths, trailing `/` stripped), plus WT_ST_MOD (modified tracked paths). In `all` mode git lists untracked files one
# by one but stops at a nested repository and prints it as a directory ending in `/`.
# Returns 1 when the read fails.
_wt_status() {
  local wt="$1" tmp rec xy p orig
  WT_ST_DIRTY=0; WT_ST_UNMERGED=0; WT_ST_ODD=0; WT_ST_N=0
  WT_ST_PATHS=""; WT_ST_NEW=""; WT_ST_MOD=""; WT_ST_NESTED=""; WT_ST_IGNORED=""
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1
  if ! git -C "$wt" --no-optional-locks status --porcelain=v1 -z --untracked-files=all \
      --ignored=matching > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 1
  fi
  while IFS= read -r -d '' rec; do
    xy="${rec:0:2}"; p="${rec:3}"; orig=""
    # -z reverses a rename: `R  <to>` NUL `<from>`, on either side (` R` is an intent-to-add
    # rename in the worktree).
    case "$xy" in R?|C?|?R|?C) IFS= read -r -d '' orig || orig="" ;; esac
    case "$p$orig" in *$'\n'*|*$'\t'*) WT_ST_ODD=1; continue ;; esac
    if [ "$xy" = '!!' ]; then WT_ST_IGNORED="${WT_ST_IGNORED}${p%/}"$'\n'; continue; fi
    WT_ST_DIRTY=1; WT_ST_N=$(( WT_ST_N + 1 ))
    case "$xy" in DD|AU|UD|UA|DU|AA|UU) WT_ST_UNMERGED=1 ;; esac
    WT_ST_PATHS="${WT_ST_PATHS}${p%/}"$'\n'
    [ -n "$orig" ] && WT_ST_PATHS="${WT_ST_PATHS}${orig}"$'\n'
    case "$xy" in
      '??') case "$p" in */) { [ -e "$wt/${p}.git" ] || [ -L "$wt/${p}.git" ]; } \
                               && WT_ST_NESTED="${WT_ST_NESTED}${p%/}"$'\n' ;; esac
            WT_ST_NEW="${WT_ST_NEW}${p%/}"$'\n' ;;
      A?|R?|C?|?A|?R|?C) WT_ST_NEW="${WT_ST_NEW}${p}"$'\n' ;;
      M?|?M|T?|?T) WT_ST_MOD="${WT_ST_MOD}${p}"$'\n' ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  return 0
}

# _wt_idle_secs <wt> <admin dir> -- prints the idle age in seconds, after _wt_status. The
# newest of: the newest reflog entry's own time (`%gd` with --date=unix, never `%ct`, which is
# the commit's date and reads a fresh checkout of an old commit as stale), the admin HEAD,
# commondir and locked mtimes, and every uncommitted path's mtime (a deleted path counts its
# nearest existing parent directory). Never the admin index or logs/HEAD mtime: `git status`
# rewrites the first, `reflog expire` and `gc --auto` the second. Any unreadable time, and a
# time in the future, prints 0: unknown reads as fresh.
_wt_idle_secs() {
  local wt="$1" gd="$2" now newest=0 t f d sel rest
  now="$(date +%s)"
  sel="$(git -C "$wt" log -g -1 --date=unix --format=%gd HEAD 2>/dev/null)"
  case "$sel" in
    *@\{*\}) t="${sel##*@\{}"; t="${t%\}}"
             case "$t" in ''|*[!0-9]*) ;; *) [ "$t" -gt "$newest" ] && newest="$t" ;; esac ;;
  esac
  for f in "$gd/HEAD" "$gd/commondir" "$gd/locked"; do
    if [ ! -e "$f" ]; then [ "$f" = "$gd/locked" ] && continue; echo 0; return; fi
    t="$(_mtime "$f")"
    case "$t" in ''|*[!0-9]*) echo 0; return ;; esac
    [ "$t" -gt "$newest" ] && newest="$t"
  done
  rest="$WT_ST_PATHS"
  while [ -n "$rest" ]; do
    f="${rest%%$'\n'*}"; rest="${rest#*$'\n'}"
    d="$wt/$f"
    while [ ! -e "$d" ] && [ ! -L "$d" ] && [ "$d" != "$wt" ]; do d="$(dirname "$d")"; done
    t="$(_mtime "$d")"
    case "$t" in ''|*[!0-9]*) echo 0; return ;; esac
    [ "$t" -gt "$newest" ] && newest="$t"
  done
  [ "$newest" -lt "$now" ] || { echo 0; return; }
  echo $(( now - newest ))
}

# _wt_synced_copy <wt> <main checkout> <path> -- 0 when every non-directory entry at or under
# <wt>/<path> has a twin at the same relative path in the main checkout: a byte-identical
# regular file, or a link with the same target. The main checkout copies such `.claude/`
# paths into each worktree and keeps the canonical copy, so removing the worktree loses
# nothing. A failed listing, a missing twin, or any other file type returns 1.
_wt_synced_copy() {
  local wt="$1" main="$2" p="$3" lst f rel rc=0
  [ -n "$main" ] && [ "$main" != "$wt" ] || return 1
  lst="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1
  if ! find "$wt/$p" ! -type d -print0 > "$lst" 2>/dev/null; then rm -f "$lst"; return 1; fi
  while IFS= read -r -d '' f; do
    rel="${f#"$wt"/}"
    if [ -L "$f" ]; then
      [ -L "$main/$rel" ] && [ "$(readlink "$f")" = "$(readlink "$main/$rel")" ] || { rc=1; break; }
    elif [ -f "$f" ]; then
      [ -f "$main/$rel" ] && [ ! -L "$main/$rel" ] && cmp -s "$f" "$main/$rel" || { rc=1; break; }
    else
      rc=1; break
    fi
  done < "$lst"
  rm -f "$lst"
  return "$rc"
}

# _wt_ignored_blockers <wt> <main checkout> -- prints each WT_ST_IGNORED path removal would
# lose: on neither _ARCHIVE_IGNORED_REGENERABLE nor a `.claude/` copy identical to the main
# checkout's (_wt_synced_copy).
_wt_ignored_blockers() {
  local wt="$1" main="$2" rest p
  rest="$WT_ST_IGNORED"
  while [ -n "$rest" ]; do
    p="${rest%%$'\n'*}"; rest="${rest#*$'\n'}"
    _ignored_match "$p" "$_ARCHIVE_IGNORED_REGENERABLE" && continue
    case "$p" in .claude|.claude/*) _wt_synced_copy "$wt" "$main" "$p" && continue ;; esac
    printf '%s\n' "$p"
  done
}

# _wt_trees <wt> <admin dir> -- prints `<staged tree> <snapshot tree>`, or `ERR <line>` and
# returns 1. The staged tree is the worktree's real index; the snapshot tree is the working
# tree as `git add -A` sees it (gitignored files left out). Both come from a COPY of the index
# in a temp file: the worktree's own index, HEAD and files are never written. Writes objects.
_WT_TMP_INDEX=""
_wt_trees() {
  local wt="$1" gd="$2" staged snap err
  _WT_TMP_INDEX="$(mktemp "${TMPDIR:-/tmp}/kit-idx.XXXXXX")" || { echo "ERR mktemp failed"; return 1; }
  trap 'rm -f "$_WT_TMP_INDEX"; exit 130' INT TERM HUP
  local msg="" fail=0 g=(env GIT_INDEX_FILE="$_WT_TMP_INDEX" git -C "$wt")
  if [ -f "$gd/index" ]; then
    err="$(cp -f "$gd/index" "$_WT_TMP_INDEX" 2>&1)" || { fail=1; msg="$err"; }
  else
    # An empty temp file is not a valid index; read-tree writes a fresh one.
    rm -f "$_WT_TMP_INDEX"
    err="$("${g[@]}" read-tree HEAD 2>&1)" || { fail=1; msg="$err"; }
  fi
  # Each step keeps its own output, so the report quotes the step that failed.
  [ "$fail" = 1 ] || staged="$("${g[@]}" write-tree 2>&1)" || { fail=1; msg="$staged"; }
  [ "$fail" = 1 ] || err="$("${g[@]}" add -A 2>&1)" || { fail=1; msg="$err"; }
  [ "$fail" = 1 ] || snap="$("${g[@]}" write-tree 2>&1)" || { fail=1; msg="$snap"; }
  rm -f "$_WT_TMP_INDEX"; trap - INT TERM HUP
  if [ "$fail" = 0 ]; then printf '%s %s\n' "$staged" "$snap"; return 0; fi
  [ -n "$msg" ] || msg="step failed with no output"
  printf 'ERR %s\n' "$(printf '%s\n' "$msg" | grep -v '^[[:space:]]*$' | grep -v '^hint:' | head -1)"
  return 1
}

# _wt_snapshot <wt> <head> <staged tree> <snapshot tree> <slug> -- prints the archive tip, or
# `ERR <line>` and returns 1. Clean: HEAD itself. Dirty: a snapshot commit on HEAD, with a
# staged commit between them only when the index differs from both HEAD and the snapshot, so a
# partly staged file keeps both versions. The messages carry the slug, never a local path.
_wt_snapshot() {
  local wt="$1" head="$2" staged="$3" snap="$4" slug="$5" head_tree parent out
  head_tree="$(git -C "$wt" rev-parse "${head}^{tree}" 2>&1)" || { printf 'ERR %s\n' "$head_tree"; return 1; }
  if [ "$snap" = "$head_tree" ] && [ "$staged" = "$head_tree" ]; then printf '%s\n' "$head"; return 0; fi
  parent="$head"
  if [ "$staged" != "$head_tree" ] && [ "$staged" != "$snap" ]; then
    out="$(git -C "$wt" commit-tree "$staged" -p "$head" -m "wrap: staged state of ${slug} [skip ci]" 2>&1)" \
      || { printf 'ERR %s\n' "$(printf '%s\n' "$out" | head -1)"; return 1; }
    parent="$out"
  fi
  out="$(git -C "$wt" commit-tree "$snap" -p "$parent" -m "wrap: snapshot of uncommitted files in ${slug} [skip ci]" 2>&1)" \
    || { printf 'ERR %s\n' "$(printf '%s\n' "$out" | head -1)"; return 1; }
  printf '%s\n' "$out"
}

# _wt_gitlinks <wt> <tree-ish> -- prints `<sha> <path>` for every gitlink in the tree. Paths
# stay in git's quoted form, so a pair compares exactly.
_wt_gitlinks() {
  local out
  out="$(git -C "$1" ls-tree -r "$2" 2>/dev/null)" || return 1
  printf '%s\n' "$out" | awk -F'\t' '{ split($1, a, " "); if (a[1] == "160000") print a[3] " " $2 }'
}

# _wt_new_gitlink <wt> <head> <tree> -- prints the first gitlink pair (path plus sha) <tree>
# holds and HEAD's tree does not. Exit 0 found, 1 none, 2 unreadable.
_wt_new_gitlink() {
  local base cur hit
  base="$(_wt_gitlinks "$1" "$2")" || return 2
  cur="$(_wt_gitlinks "$1" "$3")" || return 2
  [ -n "$cur" ] || return 1
  hit="$(printf '%s\n' "$cur" | BASE="$base" awk 'BEGIN { n = split(ENVIRON["BASE"], b, "\n"); for (i = 1; i <= n; i++) if (b[i] != "") s[b[i]] = 1 }
    $0 != "" && !($0 in s) { sub(/^[^ ]* /, ""); print; exit }')"
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
}

# _wt_new_secret <wt> <head> <tree> -- prints the first path <tree> adds over HEAD that
# _secret_shaped flags, or modifies and _secret_shaped flags as strong (an edit to an ordinary
# source file named like `token.go` stays pushable). Exit 0 found, 1 none, 2 unreadable.
_wt_new_secret() {
  local tmp st p rc=1
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 2
  if ! git -C "$1" diff-tree -r --no-renames --diff-filter=AMT --name-status -z "$2" "$3" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 2
  fi
  while IFS= read -r -d '' st && IFS= read -r -d '' p; do
    case "$st" in
      A) _secret_shaped "$p" || continue ;;
      *) _secret_shaped "$p" strong || continue ;;
    esac
    printf '%s\n' "$p"; rc=0; break
  done < "$tmp"
  rm -f "$tmp"
  return "$rc"
}

# _apply_archive_worktrees <repo> <default branch> <current branch> <fetch_succeeded> <gh state> --
# opt-in (--archive-worktrees) sweep over registered worktrees whose work origin/<default>
# lacks: a branch-held one with an unmerged patch, a detached one with a commit origin lacks,
# or any dirty one. Each must be stale (wrap.archive_worktree_min_age_hours, root-only, default
# 72), unlocked or locked by a dead pid, idle in lsof, and free of anything a removal would
# lose that the push cannot carry: an embedded repo, a submodule, a non-regenerable ignored
# path. Its tip, or a snapshot commit of its uncommitted files built from a temp index, goes to
# a new origin refs/archive/<slug>-<YYYYMMDD> (hidden from the branch list) through a create-only lease (never forced), is read
# back, and only then is the worktree removed and its branch deleted, leased to the HEAD read
# before the push. A secret-shaped uncommitted path is never pushed. The operator names the
# flag knowing origin receives every uncommitted, non-ignored byte of an archived worktree.
_apply_archive_worktrees() {
  local repo="$1" def="$2" cur="$3" fetch_succeeded="$4" ghs="$5"
  echo "-- archive worktrees:"
  if [ -n "$OWN_SET" ]; then
    echo "     SKIP archive worktrees: --own scopes cleanup to the named worktrees"; return 0
  fi
  if [ "$NO_PULL" = 1 ]; then
    echo "     SKIP archive worktrees: --no-pull (a step 0 stop; other sessions' worktrees stay)"; return 0
  fi
  if [ -z "$(_origin_url "$repo")" ]; then
    echo "     SKIP archive worktrees: no origin remote"; return 0
  fi
  if [ "$fetch_succeeded" != 1 ]; then
    echo "     SKIP archive worktrees: fetch failed, stale data"; return 0
  fi
  local min
  min="$(kit_config_get_root wrap.archive_worktree_min_age_hours 72)"
  # Six digits at most: a leading zero (`08`) would read as octal in $(( )).
  case "$min" in
    [1-9]|[1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) echo "     SKIP archive worktrees: wrap.archive_worktree_min_age_hours=$(_san "$min") is not a whole number >= 1"
       FAILURES=1; return 0 ;;
  esac
  # Fail closed: --worktrees removes only proven-merged work and proceeds without lsof; this
  # sweep pushes and removes unmerged work, so it needs the busy check.
  if [ "${KIT_WRAP_SKIP_BUSY_CHECK:-0}" = 1 ] || ! command -v lsof >/dev/null 2>&1; then
    echo "     SKIP archive worktrees: busy check unavailable (no lsof, or KIT_WRAP_SKIP_BUSY_CHECK=1)"; return 0
  fi
  # lsof always lists its caller: empty output means it failed (denied, broken), and
  # _wt_busy would then read every worktree as idle.
  if [ -z "$(cd / && lsof -nP -w -p "$$" -Fp 2>/dev/null)" ]; then
    echo "     SKIP archive worktrees: busy check unavailable (lsof returned nothing)"; return 0
  fi
  local main_wt repo_c pwd_c recs rec wt wtb prunable
  main_wt="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  main_wt="${main_wt%/.git}"; main_wt="${main_wt%/}"
  main_wt="$(cd "$main_wt" 2>/dev/null && pwd -P)"
  repo_c="$(cd "$repo" 2>/dev/null && pwd -P)"
  pwd_c="$(pwd -P 2>/dev/null)"
  recs="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || { echo "     FAILED archive worktrees: mktemp"; FAILURES=1; return 0; }
  if ! git -C "$repo" worktree list --porcelain -z > "$recs" 2>/dev/null; then
    rm -f "$recs"; echo "     FAILED archive worktrees: git worktree list failed"; FAILURES=1; return 0
  fi
  # A record is every attribute up to its empty NUL terminator: `prunable` follows the
  # `worktree` line, so the guard reads the whole record before acting.
  wt=""; wtb=""; prunable=""
  while IFS= read -r -d '' rec; do
    case "$rec" in
      "worktree "*) wt="${rec#worktree }"; wtb=""; prunable="" ;;
      "branch refs/heads/"*) wtb="${rec#branch refs/heads/}" ;;
      prunable*) prunable="${rec#prunable}"; prunable="${prunable# }"; [ -n "$prunable" ] || prunable="prunable" ;;
      "") [ -n "$wt" ] && _archive_worktree_one; wt="" ;;
    esac
  done < "$recs"
  [ -n "$wt" ] && _archive_worktree_one
  rm -f "$recs"
}

# _archive_worktree_one -- one record of _apply_archive_worktrees (reads its locals: repo def
# cur ghs min main_wt repo_c pwd_c wt wtb prunable). Every guard runs before any write.
_archive_worktree_one() {
  local wt_s wt_c gd head cherry n lcode proof idle h lv rec mode p first nb blockers slug ref label
  wt_s="$(_san "$wt")"
  if [ -n "$prunable" ]; then echo "     SKIP ${wt_s}: prunable ($(_san "$prunable"))"; return; fi
  wt_c="$(cd "$wt" 2>/dev/null && pwd -P)"
  if [ -z "$wt_c" ]; then echo "     SKIP ${wt_s}: unresolvable"; return; fi
  [ "$wt_c" = "$main_wt" ] && return
  [ "$wt_c" = "$repo_c" ] && return
  case "$pwd_c/" in "$wt_c"/*) echo "     SKIP ${wt_s}: wrap runs from inside it"; return ;; esac
  if [ -n "$wtb" ] && [ -n "$cur" ] && [ "$wtb" = "$cur" ]; then
    echo "     SKIP ${wt_s}: $(_san "$wtb") is the main checkout's branch"; return
  fi
  if [ -n "$wtb" ]; then
    case "$wtb" in "$def"|main|master)
      echo "     SKIP ${wt_s}: $(_san "$wtb") is the default or a protected branch name"; return ;;
    esac
  fi
  gd="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  if [ -z "$gd" ] || [ ! -d "$gd" ]; then echo "     SKIP ${wt_s}: unresolvable"; return; fi
  if [ -e "$gd/MERGE_HEAD" ] || [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ] \
      || [ -e "$gd/CHERRY_PICK_HEAD" ] || [ -e "$gd/REVERT_HEAD" ] || [ -e "$gd/BISECT_LOG" ]; then
    echo "     SKIP ${wt_s}: a merge, rebase, cherry-pick, revert or bisect is in progress"; return
  fi
  head="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)"
  if ! _wt_status "$wt"; then echo "     SKIP ${wt_s}: git status failed"; return; fi
  if [ -z "$head" ] || [ "$WT_ST_UNMERGED" = 1 ]; then
    echo "     SKIP ${wt_s}: unmerged index or unborn HEAD (nothing to snapshot safely)"; return
  fi
  if [ "$WT_ST_ODD" = 1 ]; then
    echo "     SKIP ${wt_s}: an uncommitted path holds a newline or tab"; return
  fi
  # Skip-worktree (S) and assume-unchanged (lower-case) entries hide edits from `git status`
  # and from `add -A`, so a removal would lose them. Captured, never piped into `grep -q`.
  if ! lv="$(git -C "$wt" ls-files -v 2>/dev/null)"; then
    echo "     SKIP ${wt_s}: git ls-files failed"; return
  fi
  # [[:lower:]], never [a-z]: bash 3.2 in a UTF-8 locale collates [a-z] over `H` too.
  case $'\n'"$lv" in *$'\n'[[:lower:]S]' '*)
    echo "     SKIP ${wt_s}: skip-worktree or assume-unchanged entries hide their edits"; return ;;
  esac
  cherry="$(git -C "$repo" cherry "refs/remotes/origin/${def}" "$head" 2>/dev/null)" # merged-ok: git cherry counts unique patches for the archive-first sweep, nothing is deleted on it alone
  n="$(printf '%s\n' "$cherry" | grep -c '^+')"
  if [ "$WT_ST_DIRTY" = 0 ]; then
    if [ "$n" -eq 0 ]; then echo "     ${wt_s}: nothing unique, left alone"; return; fi
    if [ -n "$wtb" ]; then
      read -r lcode _ proof <<< "$(branch_merged "$repo" "$def" "$ghs" "$wtb")"
      if [ "$lcode" = SAFE ]; then
        echo "     SKIP ${wt_s}: $(_san "$wtb") proven merged (${proof}), left for --worktrees"; return
      fi
    fi
  fi
  idle="$(_wt_idle_secs "$wt" "$gd")"; h=$(( idle / 3600 ))
  if [ "$idle" -lt $(( min * 3600 )) ]; then
    echo "     SKIP ${wt_s}: fresh, idle ${h}h < ${min}h (wrap.archive_worktree_min_age_hours)"; return
  fi
  if _wt_locked "$wt" && _wt_lock_live "$wt"; then
    echo "     SKIP ${wt_s}: locked by live pid $(_wt_lock_pid "$wt") (an agent is still running)"; return
  fi
  if _wt_busy "$wt"; then echo "     $(_san "$BUSY_MSG")"; return; fi
  if ! _write_guard "$wt"; then echo "     SKIP ${wt_s}: index.lock held in the worktree"; return; fi
  # An initialized submodule: `-f -f` would delete its own unpushed work.
  local lsf
  lsf="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || { echo "     SKIP ${wt_s}: mktemp failed"; return; }
  if ! git -C "$wt" ls-files -s -z > "$lsf" 2>/dev/null; then
    rm -f "$lsf"; echo "     SKIP ${wt_s}: git ls-files failed"; return
  fi
  while IFS= read -r -d '' rec; do
    mode="${rec%% *}"; p="${rec#*$'\t'}"
    if [ "$mode" = 160000 ] && { [ -e "$wt/$p/.git" ] || [ -L "$wt/$p/.git" ]; }; then
      rm -f "$lsf"; echo "     SKIP ${wt_s}: holds an initialized submodule ($(_san "$p"))"; return
    fi
  done < "$lsf"
  rm -f "$lsf"
  if [ -n "$WT_ST_NESTED" ]; then
    echo "     SKIP ${wt_s}: holds an embedded git repository ($(_san "${WT_ST_NESTED%%$'\n'*}"))"; return
  fi
  blockers="$(_wt_ignored_blockers "$wt" "$main_wt")"
  if [ -n "$blockers" ]; then
    nb="$(printf '%s\n' "$blockers" | grep -c .)"; first="${blockers%%$'\n'*}"
    echo "     SKIP ${wt_s}: ${nb} ignored paths would be lost, first $(_san "$first") (never pushed, never deleted)"; return
  fi
  # Added, renamed-to and untracked paths against the full list; an uncommitted edit of a
  # tracked file against the strong list only, so `token.go` stays pushable while an edited
  # `.env.sample` does not. Committed history is pushed unscanned (DEC-L).
  p="$WT_ST_NEW"
  while [ -n "$p" ]; do
    first="${p%%$'\n'*}"; p="${p#*$'\n'}"
    if _secret_shaped "$first"; then
      echo "     SKIP ${wt_s}: uncommitted $(_san "$first") looks like a secret (never pushed)"; return
    fi
  done
  p="$WT_ST_MOD"
  while [ -n "$p" ]; do
    first="${p%%$'\n'*}"; p="${p#*$'\n'}"
    if _secret_shaped "$first" strong; then
      echo "     SKIP ${wt_s}: uncommitted $(_san "$first") looks like a secret (never pushed)"; return
    fi
  done
  if [ -n "$wtb" ]; then slug="$(_archive_slug "$wtb")"; label="$(_san "$wtb")"
  else slug="$(_archive_slug "${wt_c##*/}")"; label="detached"; fi
  [ -n "$slug" ] || slug="wt"
  ref="refs/archive/${slug}-$(date +%Y%m%d)"
  if [ "$APPLY" != 1 ]; then
    echo "     WOULD archive worktree ${wt_s} [${label}, ${n} unique commits, ${WT_ST_N} uncommitted paths, idle ${h}h] -> origin ${ref}, then remove it"
    return
  fi
  _archive_worktree_push
}

# _archive_worktree_push -- the --apply half of _archive_worktree_one (reads its locals).
_archive_worktree_push() {
  local rl trees staged snap tip out rc err pushed head2 trees2 t
  if ! _write_guard "$repo"; then echo "     SKIP ${wt_s}: index.lock held by another writer"; return; fi
  # The full ref, matched exactly: ls-remote matches a pattern against ref TAILS, so
  # refs/heads/foo/refs/archive/x would answer a bare refs/archive/x pattern.
  if ! rl="$(git -C "$repo" ls-remote origin "$ref" 2>/dev/null)"; then
    echo "     FAILED archive worktree ${wt_s}: origin could not be read"; FAILURES=1; return
  fi
  if [ -n "$(printf '%s\n' "$rl" | awk -v r="$ref" '$2 == r')" ]; then
    echo "     FAILED archive worktree ${wt_s}: origin ${ref} already exists"; FAILURES=1; return
  fi
  if ! trees="$(_wt_trees "$wt" "$gd")"; then
    echo "     FAILED archive worktree ${wt_s}: snapshot failed ($(_san "${trees#ERR }"))"; FAILURES=1; return
  fi
  staged="${trees%% *}"; snap="${trees##* }"
  if ! tip="$(_wt_snapshot "$wt" "$head" "$staged" "$snap" "$slug")"; then
    echo "     FAILED archive worktree ${wt_s}: snapshot failed ($(_san "${tip#ERR }"))"; FAILURES=1; return
  fi
  # The tree guards read exactly what would leave: a nested repo becomes a gitlink whose
  # objects never reach origin, and a secret-shaped added path would be disclosed.
  for t in "$staged" "$snap"; do
    out="$(_wt_new_gitlink "$wt" "$head" "$t")"; rc=$?
    if [ "$rc" -eq 0 ]; then echo "     SKIP ${wt_s}: holds an embedded git repository ($(_san "$out"))"; return; fi
    if [ "$rc" -eq 2 ]; then echo "     FAILED archive worktree ${wt_s}: snapshot tree unreadable"; FAILURES=1; return; fi
    out="$(_wt_new_secret "$wt" "$head" "$t")"; rc=$?
    if [ "$rc" -eq 0 ]; then echo "     SKIP ${wt_s}: uncommitted $(_san "$out") looks like a secret (never pushed)"; return; fi
    if [ "$rc" -eq 2 ]; then echo "     FAILED archive worktree ${wt_s}: snapshot tree unreadable"; FAILURES=1; return; fi
  done
  # Create-only lease: an empty expect means "the ref must not exist", so a ref made after the
  # pre-read is refused even where a plain push would fast-forward it. Never forced otherwise.
  if ! err="$(git -C "$repo" push "--force-with-lease=${ref}:" origin "${tip}:${ref}" 2>&1)"; then
    err="$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | head -1)"
    echo "     FAILED archive worktree ${wt_s}: $(_san "${err:-push refused}")"; FAILURES=1; return
  fi
  pushed="$(git -C "$repo" ls-remote origin "$ref" 2>/dev/null | awk -v r="$ref" '$2 == r { print $1 }')"
  if [ -z "$pushed" ] || [ "$pushed" != "$tip" ]; then
    echo "     FAILED archive worktree ${wt_s}: origin ${ref} holds $(_short "${pushed:-nothing}"), not the archive tip $(_short "$tip")"
    FAILURES=1; return
  fi
  # The push took a network round trip: re-read everything a removal would destroy.
  head2="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)"
  trees2="$(_wt_trees "$wt" "$gd")" || trees2=""
  if [ "$head2" != "$head" ] || [ "$trees2" != "$trees" ]; then
    echo "     kept ${wt_s}: archived to ${ref}, but it changed during the push (the ref holds the earlier state)"; return
  fi
  if ! _wt_status "$wt" || [ -n "$(_wt_ignored_blockers "$wt" "$main_wt")" ] || [ -n "$WT_ST_NESTED" ]; then
    echo "     kept ${wt_s}: archived to ${ref}, but it changed during the push (the ref holds the earlier state)"; return
  fi
  if _wt_locked "$wt" && _wt_lock_live "$wt"; then
    echo "     kept ${wt_s}: archived to ${ref}, but live pid $(_wt_lock_pid "$wt") locked it during the push"; return
  fi
  if _wt_busy "$wt"; then echo "     kept ${wt_s}: archived to ${ref}, but $(_san "${BUSY_MSG#SKIP }")"; return; fi
  if ! _write_guard "$wt"; then echo "     kept ${wt_s}: archived to ${ref}, but its index.lock is held"; return; fi
  git -C "$repo" worktree remove -f -f "$wt" >/dev/null 2>&1
  if ! _wt_cleared "$repo" "$wt"; then
    echo "     FAILED archive worktree ${wt_s}: ${wt_s} survived the removal${wtb:+, $(_san "$wtb") not deleted}"
    FAILURES=1; return
  fi
  if [ -z "$wtb" ]; then
    echo "     archived worktree ${wt_s} -> ${ref} ($(_short "$tip")); removed"; return
  fi
  # update-ref lacks branch -D's refusals, so the checked-out checks repeat right before it.
  # Captured, never piped into `grep -q` (a SIGPIPE under pipefail would read as "not held").
  local wl
  if [ "$(git -C "$repo" symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/${wtb}" ] \
      || ! wl="$(git -C "$repo" worktree list --porcelain 2>/dev/null)" \
      || case $'\n'"${wl}"$'\n' in *$'\n'"branch refs/heads/${wtb}"$'\n'*) true ;; *) false ;; esac; then
    echo "     kept $(_san "$wtb"): archived to ${ref}, worktree removed, but the branch was checked out elsewhere during the push"
    return
  fi
  if git -C "$repo" update-ref --no-deref -d "refs/heads/${wtb}" "$head" >/dev/null 2>&1; then
    git -C "$repo" config --remove-section "branch.${wtb}" >/dev/null 2>&1
    echo "     archived worktree ${wt_s} -> ${ref} ($(_short "$tip")); removed, $(_san "$wtb") deleted"
  else
    echo "     FAILED archive worktree ${wt_s}: removed, but the local delete of $(_san "$wtb") refused"
    FAILURES=1
  fi
}

# _apply_origin_branches <repo> <default branch> <gh state> -- deletes origin branches
# whose work already merged. `merge` never passes --delete-branch, so without this pass every
# merged head lives on origin forever. A branch qualifies only when a same-repo MERGED PR has its
# exact origin tip, it is not the default branch, and no OPEN PR uses it as head or base
# (deleting a base closes the dependent PR). Everything else is kept without a line. Tips come
# from `ls-remote`, not refs/remotes: a checkout whose fetch refspec names only the default
# branch tracks a handful of origin's branches. Each delete is leased to the tip it read, so a
# branch pushed to after the read is refused rather than lost. Under --own the sweep considers
# only the branches the named worktrees held (OWN_BRANCHES): a wrap cleans up its own session.
_APPLY_PRS_MERGED=""
_APPLY_PRS_OPEN=""
_APPLY_PRS_CLOSED=""
_APPLY_BATCH_BRANCHES=""
_APPLY_ORIGIN_HEADS_CACHE=""
_APPLY_ORIGIN_HEADS_OK=0

# _origin_heads_ref_list <repo> <fetch_succeeded> -- prints "<sha>\trefs/heads/<branch>" lines
# matching `git ls-remote --heads origin`. After a successful `fetch --prune` with the standard
# wildcard fetch refspec, `refs/remotes/origin/*` already holds that exact map locally.
_origin_heads_ref_list() {
  local repo="$1" fetch_ok="${2:-0}" spec has_glob=0
  if [ "$fetch_ok" = 1 ]; then
    while IFS= read -r spec; do
      case "$spec" in
        "+refs/heads/*:refs/remotes/origin/*"|"refs/heads/*:refs/remotes/origin/*") has_glob=1; break ;;
      esac
    done < <(git -C "$repo" config --get-all remote.origin.fetch 2>/dev/null)
  fi
  if [ "$has_glob" = 1 ]; then
    git -C "$repo" for-each-ref --format='%(objectname)%09refs/heads/%(refname:lstrip=3)' refs/remotes/origin/ 2>/dev/null \
      | awk -F'\t' '$2 != "refs/heads/HEAD"'
  else
    git -C "$repo" ls-remote --heads origin 2>/dev/null
  fi
}

_apply_batch_prs_clear() {
  [ -n "$_APPLY_PRS_MERGED" ] && rm -f "$_APPLY_PRS_MERGED"
  [ -n "$_APPLY_PRS_OPEN" ] && rm -f "$_APPLY_PRS_OPEN"
  [ -n "$_APPLY_PRS_CLOSED" ] && rm -f "$_APPLY_PRS_CLOSED"
  _APPLY_PRS_MERGED=""
  _APPLY_PRS_OPEN=""
  _APPLY_PRS_CLOSED=""
  _APPLY_BATCH_BRANCHES=""
  _APPLY_ORIGIN_HEADS_CACHE=""
  _APPLY_ORIGIN_HEADS_OK=0
}

_apply_origin_sweep_max() {
  local max
  max="$(kit_config_get_root wrap.origin_sweep_max 500)"
  case "$max" in ''|*[!0-9]*) max=500 ;; esac
  printf '%s\n' "$max"
}

_apply_origin_head_count() {
  printf '%s' "$1" | awk 'NF { n++ } END { print n + 0 }'
}

_apply_batch_prs_init() {
  local repo="$1" def="$2" fetch_ok="$3" ghs="$4" want_closed="${5:-0}"
  _apply_batch_prs_clear
  [ "$ghs" = "ok" ] || return 0
  local remote_url
  remote_url="$(git -C "$repo" config --get remote.origin.url 2>/dev/null)"
  [ -n "$remote_url" ] || remote_url="$(_origin_url "$repo")"
  _gh_owner_repo "$remote_url" >/dev/null 2>&1 || return 0

  local nl=$'\n'
  local cand="" local_names="$nl" b tip heads_n=0 remote_max=500 include_remote=0
  for b in $(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/ 2>/dev/null); do
    case "$b" in "$def"|main|master|"") continue ;; esac
    local_names="${local_names}${b}${nl}"
    cand="${cand}${b}${nl}"
  done
  if _APPLY_ORIGIN_HEADS_CACHE="$(_origin_heads_ref_list "$repo" "$fetch_ok")"; then
    _APPLY_ORIGIN_HEADS_OK=1
    heads_n="$(_apply_origin_head_count "$_APPLY_ORIGIN_HEADS_CACHE")"
    remote_max="$(_apply_origin_sweep_max)"
    [ "$heads_n" -le "$remote_max" ] && include_remote=1
    while IFS=$'\t' read -r tip b; do
      b="${b#refs/heads/}"
      [ -n "$tip" ] && [ -n "$b" ] && [ "$b" != "$def" ] || continue
      if [ "$include_remote" = 1 ]; then
        cand="${cand}${b}${nl}"
      else
        case "$local_names" in
          *"$nl$b$nl"*) cand="${cand}${b}${nl}" ;;
        esac
      fi
    done <<< "$_APPLY_ORIGIN_HEADS_CACHE"
  fi

  local brs=() n_brs=0
  while IFS= read -r b; do
    [ -n "$b" ] && { brs[$n_brs]="$b"; n_brs=$(( n_brs + 1 )); }
  done <<< "$cand"

  _APPLY_PRS_MERGED="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || { _apply_batch_prs_clear; return 0; }
  _APPLY_PRS_OPEN="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || { _apply_batch_prs_clear; return 0; }
  if [ "$want_closed" = 1 ]; then
    _APPLY_PRS_CLOSED="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || { _apply_batch_prs_clear; return 0; }
  fi

  if branch_merged_batch_fetch "$repo" "$ghs" "$_APPLY_PRS_MERGED" "$_APPLY_PRS_OPEN" "$_APPLY_PRS_CLOSED" -- ${brs[@]+"${brs[@]}"}; then
    _APPLY_BATCH_BRANCHES="${nl}"
    for b in ${brs[@]+"${brs[@]}"}; do
      _APPLY_BATCH_BRANCHES="${_APPLY_BATCH_BRANCHES}${b}${nl}"
    done
  else
    _apply_batch_prs_clear
  fi
}

_apply_branch_merged() {
  local tip="" repo="" def="" ghs="" b="" nl=$'\n'
  while [ $# -gt 0 ]; do
    case "$1" in
      --tip) tip="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  repo="$1"; def="$2"; ghs="$3"; b="$4"
  local args=()
  [ -n "$tip" ] && { args[${#args[@]}]="--tip"; args[${#args[@]}]="$tip"; }
  if [ -n "$_APPLY_PRS_MERGED" ] && [ -r "$_APPLY_PRS_MERGED" ]; then
    case "$_APPLY_BATCH_BRANCHES" in
      *"${nl}${b}${nl}"*) args[${#args[@]}]="--prs-json"; args[${#args[@]}]="$_APPLY_PRS_MERGED" ;;
    esac
  fi
  branch_merged ${args[@]+"${args[@]}"} "$repo" "$def" "$ghs" "$b"
}

# ponytail: a branch whose merged PR sits past the list cap is kept; raise the cap if that bites.
_ORIGIN_PR_LIMIT=1000
# Names per `git push`; the env override is a test seam for the chunk loop.
_ORIGIN_DELETE_CHUNK=${WRAP_ORIGIN_DELETE_CHUNK:-100}
_apply_origin_branches() {
  local repo="$1" def="$2" ghs="$3" fetch_ok="${4:-0}" url merged open elig names n k left heads push_args own_json="null"
  if [ -n "$OWN_SET" ]; then
    own_json="$(printf '%s' "$OWN_BRANCHES" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')" || own_json="[]"
    echo "-- origin branches (own scope: $(printf '%s' "$own_json" | jq 'length') named branches):"
  else
    echo "-- origin branches:"
  fi
  case "$(git -C "$repo" config --get remote.origin.url)" in
    *github.com[:/]*) ;;
    *) echo "     SKIP origin sweep: origin is not a GitHub remote"; return 0 ;;
  esac
  [ "$ghs" = "ok" ] || { echo "     SKIP origin sweep: $(_gh_note "$ghs")"; return 0; }
  url="$(_origin_url "$repo")"
  local heads_out protect mnames mfile b tip verdict nl=$'\n' heads_n=0 origin_max=500
  if [ "$_APPLY_ORIGIN_HEADS_OK" = 1 ]; then
    heads_out="$_APPLY_ORIGIN_HEADS_CACHE"
  else
    heads_out="$(_origin_heads_ref_list "$repo" "$fetch_ok")" || {
      echo "     SKIP origin sweep: origin's branches or PRs could not be read"; return 0
    }
  fi
  heads_n="$(_apply_origin_head_count "$heads_out")"
  origin_max="$(_apply_origin_sweep_max)"
  if [ "$heads_n" -gt "$origin_max" ]; then
    echo "     SKIP origin sweep: ${heads_n} remote heads over cap"; return 0
  fi
  # A failed read leaves its list empty, which is no JSON array, so the sweep skips.
  if [ -n "$_APPLY_PRS_MERGED" ] && [ -s "$_APPLY_PRS_MERGED" ]; then
    merged="$(cat "$_APPLY_PRS_MERGED" 2>/dev/null)" || merged=""
  else
    merged="$(gh pr list --repo "$url" --state merged --limit "$_ORIGIN_PR_LIMIT" --json headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository 2>/dev/null)" || merged="" # merged-ok: the one repo-wide list branch_merged --prs-json judges
  fi
  if [ -n "$_APPLY_PRS_OPEN" ] && [ -s "$_APPLY_PRS_OPEN" ]; then
    open="$(cat "$_APPLY_PRS_OPEN" 2>/dev/null)" || open=""
  else
    open="$(gh pr list --repo "$url" --state open --limit "$_ORIGIN_PR_LIMIT" \
      --json headRefName,baseRefName 2>/dev/null)" || open=""
  fi
  # A full open page may hide the PR that protects a base branch, so the sweep stands down.
  if [ "$(printf '%s' "$open" | jq -r 'length' 2>/dev/null)" = "$_ORIGIN_PR_LIMIT" ]; then
    echo "     SKIP origin sweep: ${_ORIGIN_PR_LIMIT}+ open PRs, an unread one could need a branch"; return 0
  fi
  if ! printf '%s' "$merged" | jq -e 'type == "array"' >/dev/null 2>&1 \
     || ! printf '%s' "$open" | jq -e 'type == "array" and all(.[]; (.headRefName | type) == "string" and (.baseRefName | type) == "string")' >/dev/null 2>&1; then
    echo "     SKIP origin sweep: origin's branches or PRs could not be read"; return 0
  fi
  # One "<name> <tip>" line per eligible branch. The merged-ness of each is branch_merged's answer on
  # the one merged-PR list read above; the sweep keeps its own guards on top: not the default branch,
  # inside the --own scope, and no OPEN PR uses the branch as head or base.
  protect="$(printf '%s' "$open" | jq -r '.[] | (.headRefName, .baseRefName) | select(. != null)' 2>/dev/null)" \
    || { echo "     SKIP origin sweep: origin's branches or PRs could not be read"; return 0; }
  mnames="$(printf '%s' "$merged" | jq -r '.[].headRefName // empty' 2>/dev/null | sort -u)"
  mfile="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" \
    || { echo "     SKIP origin sweep: no scratch file for the merged-PR list"; return 0; }
  printf '%s' "$merged" > "$mfile"
  local b_arr=() t_arr=() idx=0 pr_n pr_st
  elig=""
  while IFS=$'\t' read -r tip b; do
    b="${b#refs/heads/}"
    [ -n "$tip" ] && [ -n "$b" ] && [ "$b" != "$def" ] || continue
    # Matched in the shell with a case on newline-delimited text, never through a pipe into grep -q:
    # grep exits on its first hit, the writer takes SIGPIPE, and under pipefail the "found" answer
    # reads as "not found" once the list passes the pipe buffer, which would let a protected branch go.
    if [ -n "$OWN_SET" ]; then case "$nl$OWN_BRANCHES$nl" in *"$nl$b$nl"*) ;; *) continue ;; esac; fi
    case "$nl$mnames$nl" in *"$nl$b$nl"*) ;; *) continue ;; esac
    case "$nl$protect$nl" in *"$nl$b$nl"*) continue ;; esac
    verdict="$(branch_merged --need pr --tip "$tip" --prs-json "$mfile" "$repo" "$def" ok "$b")"
    case "$verdict" in "SAFE squash "*)
      elig="${elig}${b} ${tip}"$'\n'
      b_arr[$idx]="$b"; t_arr[$idx]="$tip"; idx=$(( idx + 1 )) ;;
    esac
  done <<< "$heads_out"
  rm -f "$mfile"
  elig="${elig%$'\n'}"
  names="$(printf '%s' "$elig" | cut -d' ' -f1)"
  n="$(printf '%s' "$names" | grep -c .)"
  if [ "$n" -eq 0 ]; then echo "     no merged branches left on origin"; return 0; fi
  if [ "$(kit_config_get_root wrap.delete_merged_remote_branches true)" != "true" ]; then
    echo "     ${n} merged branches left on origin (wrap.delete_merged_remote_branches=false)"
    if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
      local j=0
      while [ "$j" -lt "$idx" ]; do
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "${b_arr[$j]}" "${t_arr[$j]}")"
        _emit_sweep_row origin_branch "" "${b_arr[$j]}" keep "wrap.delete_merged_remote_branches=false" "$pr_n" "$pr_st" null null null null
        j=$(( j + 1 ))
      done
    fi
    return 0
  fi
  if [ "$APPLY" != 1 ]; then
    echo "     WOULD delete ${n} merged branches on origin:"
    printf '%s\n' "$names" | sed 's/^/       /'
    if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
      local j=0
      while [ "$j" -lt "$idx" ]; do
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "${b_arr[$j]}" "${t_arr[$j]}")"
        _emit_sweep_row origin_branch "" "${b_arr[$j]}" would_remove "merged branch on origin" "$pr_n" "$pr_st" null null null null
        j=$(( j + 1 ))
      done
    fi
    return 0
  fi
  # Ref names hold no whitespace or glob characters, so word splitting yields exact
  # name/tip pairs. A full refs/heads/ refspec keeps a same-named tag or a leading dash inert.
  # shellcheck disable=SC2086
  set -- $elig
  while [ $# -gt 0 ]; do
    k=0
    while [ $# -gt 0 ] && [ "$k" -lt "$_ORIGIN_DELETE_CHUNK" ]; do
      push_args[k * 2]="--force-with-lease=refs/heads/$1:$2"
      push_args[k * 2 + 1]=":refs/heads/$1"
      k=$(( k + 1 )); shift 2
    done
    git -C "$repo" push -q origin "${push_args[@]:0:$(( k * 2 ))}" \
      || { echo "     FAILED delete ${k} origin branches: exit $? (protected, no permission, or pushed since the read)"; FAILURES=1; }
  done
  # A multi-ref push is not atomic, so the count comes from what origin still holds.
  if ! heads="$(git -C "$repo" ls-remote --heads origin 2>/dev/null)"; then
    echo "     FAILED re-read origin after the delete, so the deleted count is unknown"; FAILURES=1
    if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
      local j=0
      while [ "$j" -lt "$idx" ]; do
        IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "${b_arr[$j]}" "${t_arr[$j]}")"
        _emit_sweep_row origin_branch "" "${b_arr[$j]}" error "re-read origin after delete failed" "$pr_n" "$pr_st" null null null null
        j=$(( j + 1 ))
      done
    fi
    return 0
  fi
  local rem_names
  rem_names="$(printf '%s\n' "$heads" | sed 's|.*refs/heads/||')"
  left="$(printf '%s\n' "$rem_names" | grep -cxF -f <(printf '%s\n' "$names"))"
  echo "     deleted $(( n - left )) of ${n} merged branches on origin"
  if [ -n "${_SWEEP_ROWS_FILE:-}" ]; then
    local j=0 ov
    while [ "$j" -lt "$idx" ]; do
      IFS=$'\t' read -r pr_n pr_st <<< "$(_sweep_row_pr_info "$repo" "$def" "$ghs" "${b_arr[$j]}" "${t_arr[$j]}")"
      if printf '%s\n' "$rem_names" | grep -qxF "${b_arr[$j]}"; then
        _emit_sweep_row origin_branch "" "${b_arr[$j]}" error "failed to delete merged branch on origin" "$pr_n" "$pr_st" null null null null
      else
        _emit_sweep_row origin_branch "" "${b_arr[$j]}" removed "merged branch on origin" "$pr_n" "$pr_st" null null null null
      fi
      j=$(( j + 1 ))
    done
  fi
}

# _sweep_repo_apply <repo> <def> <cur> <ghs> <rows_file> -- runs the apply cleanup logic
# for one already-fetched repo under wrap sweep, emitting structured JSON rows to <rows_file>
# without pulling or touching the main checkout's working tree.
_sweep_repo_apply() {
  local repo="$1" def="$2" cur="$3" ghs="$4" rows_file="$5"
  _SWEEP_ROWS_FILE="$rows_file"
  TIPS_FILE="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || TIPS_FILE=""
  if [ -n "$TIPS_FILE" ]; then
    git -C "$repo" for-each-ref --format='%(refname:lstrip=2) %(objectname)' refs/heads/ > "$TIPS_FILE" 2>/dev/null
  fi
  _apply_batch_prs_init "$repo" "$def" 1 "$ghs" 1
  _wt_busy_snap_init
  if [ "$WORKTREES" = 1 ]; then
    _apply_worktrees "$repo" "$def" "$cur" 1 "$ghs"
  fi
  _apply_branches "$repo" "$def" "$cur" 1 "$ghs"
  _apply_origin_branches "$repo" "$def" "$ghs" 1
  _wt_busy_snap_clear
  _apply_batch_prs_clear
  [ -n "$TIPS_FILE" ] && rm -f "$TIPS_FILE"
  TIPS_FILE=""
  _SWEEP_ROWS_FILE=""
}


_apply_repo() {
  local repo="$1" ghs="$2" ghs_file="${3:-}" ghs_pid="${4:-}"
  _is_repo "$repo" || { echo "== ${repo}: not a git repo, skipped"; return 0; }
  echo "== ${repo}"
  local fetch_succeeded=1
  if ! git -C "$repo" fetch --prune -q 2>/dev/null; then
    fetch_succeeded=0
    if [ "$PULL_ONLY" = 1 ]; then
      echo "     (fetch failed; the pull below will likely fail too)"
    else
      echo "     (fetch failed; every delete is skipped)"
    fi
  fi

  if [ -z "$ghs" ] && [ -n "$ghs_file" ]; then
    [ -n "$ghs_pid" ] && wait "$ghs_pid" 2>/dev/null || true
    ghs="$(cat "$ghs_file" 2>/dev/null)"
    [ -n "$ghs" ] || ghs="$(_gh_state)"
    export _WRAP_GH_STATE="$ghs"
  fi

  local def
  def="$(_default_branch "$repo")" || {
    echo "     SKIP ${repo}: no default branch resolved (origin/HEAD, origin/main and origin/master all absent)"
    [ "$PULL_ONLY" = 1 ] && FAILURES=1
    return 0
  }
  local cur; cur="$(git -C "$repo" branch --show-current 2>/dev/null)"

  # Tip snapshot for this repo, taken once, compared right before each delete. --tips-file
  # substitutes a prepared snapshot so a test can stage a tip that moved mid-run.
  # --pull-only runs no delete, so nothing reads a snapshot.
  local own_snapshot=1
  if [ "$PULL_ONLY" = 1 ]; then
    own_snapshot=0
  elif [ -n "$TIPS_OVERRIDE" ]; then
    TIPS_FILE="$TIPS_OVERRIDE"; own_snapshot=0
  else
    TIPS_FILE="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
    git -C "$repo" for-each-ref --format='%(refname:lstrip=2) %(objectname)' refs/heads/ > "$TIPS_FILE" 2>/dev/null
  fi

  # --pull-only runs the fetch + pull stage alone: no worktree, branch, archive, origin-branch,
  # stray-line, or stray-commit write.
  if [ "$PULL_ONLY" != 1 ]; then
    _apply_batch_prs_init "$repo" "$def" "$fetch_succeeded" "$ghs"
    _wt_busy_snap_init
    if [ "$NO_PULL" = 1 ] && [ -z "$OWN_SET" ]; then
      # A step 0 stop tidies the session's own worktrees only: an unscoped sweep would
      # delete other live sessions' merged worktrees and branches.
      echo "-- worktrees:"
      echo "     SKIP worktree sweep: --no-pull needs --own (the session's own worktrees only)"
    else
      _apply_worktrees "$repo" "$def" "$cur" "$fetch_succeeded" "$ghs"
    fi
    if [ "$NO_PULL" = 1 ] && [ -z "$OWN_SET" ]; then
      echo "-- branches:"
      echo "     SKIP branch sweep: --no-pull needs --own (the all-branches sweep reaches other sessions' branches)"
    elif [ -n "$OWN_SET" ]; then
      # The named worktrees' branches were deleted by the worktree step itself; the
      # all-branches sweep would reach past the session's scope into other sessions'.
      echo "-- branches:"
      echo "     SKIP branch sweep: --own scopes cleanup to the named worktrees"
    else
      _apply_branches "$repo" "$def" "$cur" "$fetch_succeeded" "$ghs"
    fi
    # Opt-in and never under --own (see the function's own comment); a flag-off run prints
    # no new section, so the report is byte-identical to before this flag existed.
    [ "$ARCHIVE_UNMERGED" = 1 ] && _apply_archive_unmerged "$repo" "$def" "$cur" "$fetch_succeeded"
    # Opt-in, same contract: no default flow passes it, and a flag-off report is unchanged.
    [ "$ARCHIVE_WORKTREES" = 1 ] && _apply_archive_worktrees "$repo" "$def" "$cur" "$fetch_succeeded" "$ghs"
    # Under --own it considers only the branches the named worktrees held: a wrap's default
    # cleanup is the current session, and other sessions' merged heads wait for a plain
    # apply or --worktrees run. The same proof applies (merged PR at the exact tip, no open PR).
    _apply_origin_branches "$repo" "$def" "$ghs" "$fetch_succeeded"
    _wt_busy_snap_clear
    _apply_batch_prs_clear

    # Any checked-out branch: the incident state is a shared main checkout sitting on a
    # feature branch while a session writes the board there.
    if [ "$fetch_succeeded" = 1 ]; then
      _carry_stray "$repo" "$def"
    else
      echo "-- stray lines:"
      echo "     SKIP stray lines: fetch failed, origin/${def} may be stale"
    fi
    # Before the pull, which a default branch ahead of origin can never fast-forward.
    if [ "$NO_PULL" = 1 ]; then
      echo "-- stray commits:"
      echo "     SKIP stray commits: --no-pull"
    elif [ "$fetch_succeeded" != 1 ]; then
      echo "-- stray commits:"
      echo "     SKIP stray commits: fetch failed, origin/${def} may be stale"
    elif [ "$cur" = "$def" ]; then
      _carry_stray_commits "$repo" "$def"
    fi
  fi

  echo "-- pull:"
  if [ "$NO_PULL" = 1 ]; then
    # --no-pull is a step 0 stop: the pull and the stray-commits move write HEAD and the
    # working tree of a checkout another session is writing.
    echo "     SKIP pull: --no-pull"
  elif [ "$cur" = "$def" ]; then
    # --pull-only skips the stray-commits carry, so name what it leaves behind rather than
    # letting unpushed commits on the default branch go silent run after run.
    if [ "$PULL_ONLY" = 1 ] && [ "$fetch_succeeded" = 1 ]; then
      local ahead; ahead="$(git -C "$repo" rev-list --count "origin/${def}..HEAD" 2>/dev/null)" # merged-ok: ahead count of the main checkout's default branch for the pull step, no delete rides on it
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && \
        echo "     NOTE: ${def} is ${ahead} commits ahead of origin/${def}; --pull-only never carries them, plain apply --apply does"
    fi
    _pull_default "$repo" "$cur"
  else
    echo "     SKIP pull: checkout on '${cur:-<detached>}', not the default branch ${def}"
    run "$repo" "fetch origin ${def}:${def} (ff-only by nature)" git -C "$repo" fetch origin "${def}:${def}"
  fi

  [ "$own_snapshot" = 1 ] && rm -f "$TIPS_FILE"
  TIPS_FILE=""
}

cmd_apply() {
  # Indexed assignment plus a counter, not `arr+=()` with `${#arr[@]}`: an empty array reads
  # as unbound under `set -u` in bash 3.2, which is what macOS ships.
  local arg count=0 i=1 want_tips=0 want_own=0 want_under=0 nu=0
  local repos unders
  for arg in "$@"; do
    case "$arg" in
      --apply) APPLY=1 ;;
      --worktrees) WORKTREES=1 ;;
      --archive-unmerged) ARCHIVE_UNMERGED=1 ;;
      --archive-worktrees) ARCHIVE_WORKTREES=1 ;;
      --pull-only) PULL_ONLY=1 ;;
      --no-pull) NO_PULL=1 ;;
      --under=*) nu=$(( nu + 1 )); unders[nu]="${arg#--under=}" ;;
      --under) want_under=1 ;;
      --own=*) OWN_N=$(( OWN_N + 1 )); OWN_PATHS[OWN_N]="${arg#--own=}" ;;
      --own) want_own=1 ;;
      --tips-file=*) TIPS_OVERRIDE="${arg#--tips-file=}" ;;
      --tips-file) want_tips=1 ;;
      -*) echo "wrap.sh apply: unknown flag '$arg'" >&2; return 64 ;;
      *) _reject_packed apply "$arg" || return 64
         if [ "$want_own" = 1 ]; then OWN_N=$(( OWN_N + 1 )); OWN_PATHS[OWN_N]="$arg"; want_own=0
         elif [ "$want_under" = 1 ]; then nu=$(( nu + 1 )); unders[nu]="$arg"; want_under=0
         elif [ "$want_tips" = 1 ]; then TIPS_OVERRIDE="$arg"; want_tips=0
         else count=$(( count + 1 )); repos[count]="$arg"; fi ;;
    esac
  done
  [ "$want_tips" = 0 ] || { echo "wrap.sh apply: --tips-file needs a path" >&2; return 64; }
  [ "$want_own" = 0 ] || { echo "wrap.sh apply: --own needs a worktree path" >&2; return 64; }
  # --pull-only runs only the fetch + pull stage, so every other write-capable flag is a
  # conflict rather than a silent no-op. Checked before the --tips-file existence check just
  # below: a combination with --tips-file is refused for the conflict, not for whether the
  # path exists.
  if [ "$PULL_ONLY" = 1 ] && [ "$NO_PULL" = 1 ]; then
    echo "wrap.sh apply: --no-pull cannot combine with --pull-only" >&2; return 64
  fi
  if [ "$PULL_ONLY" = 1 ]; then
    if [ "$WORKTREES" = 1 ]; then echo "wrap.sh apply: --pull-only cannot combine with --worktrees" >&2; return 64; fi
    if [ "$ARCHIVE_UNMERGED" = 1 ]; then echo "wrap.sh apply: --pull-only cannot combine with --archive-unmerged" >&2; return 64; fi
    if [ "$ARCHIVE_WORKTREES" = 1 ]; then echo "wrap.sh apply: --pull-only cannot combine with --archive-worktrees" >&2; return 64; fi
    if [ "$OWN_N" -gt 0 ]; then echo "wrap.sh apply: --pull-only cannot combine with --own" >&2; return 64; fi
    if [ -n "$TIPS_OVERRIDE" ]; then echo "wrap.sh apply: --pull-only cannot combine with --tips-file" >&2; return 64; fi
  fi
  if [ -n "$TIPS_OVERRIDE" ] && [ ! -f "$TIPS_OVERRIDE" ]; then
    echo "wrap.sh apply: --tips-file '${TIPS_OVERRIDE}' is not an existing file" >&2; return 64
  fi
  if [ "$want_under" = 1 ]; then _expand_bare_under apply || return 64; fi
  [ "$count" -ge 1 ] || [ "$nu" -ge 1 ] || { echo "usage: wrap.sh apply [--apply] [--worktrees] [--archive-unmerged] [--archive-worktrees] [--pull-only|--no-pull] [--own <path>]... [--under <root>]... <repo> [<repo>...]" >&2; _hint_no_repo apply; return 64; }
  while [ "$i" -le "$nu" ]; do _add_under "${unders[$i]}"; i=$(( i + 1 )); done
  # Canonicalise the own set once: the worktree loop compares against `pwd -P`
  # paths, so the same normalisation must apply to the names the operator typed.
  i=1
  while [ "$i" -le "$OWN_N" ]; do
    local canon
    canon="$(cd "${OWN_PATHS[$i]}" 2>/dev/null && pwd -P)"
    OWN_SET="${OWN_SET}${canon:-${OWN_PATHS[$i]}}"$'\n'
    i=$(( i + 1 ))
  done
  [ "$APPLY" = 1 ] && MODE="APPLY"
  # Every gh reader is a sweep --pull-only turns off, so skip the auth probe with them.
  # Overlap `_gh_state` with the first repo's `git fetch --prune` when running multiple steps.
  local ghs="" ghs_file="" ghs_pid=""
  if [ "$PULL_ONLY" != 1 ]; then
    if [ -n "${_WRAP_GH_STATE:-}" ]; then
      ghs="$_WRAP_GH_STATE"
    else
      ghs_file="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || ghs_file=""
      if [ -n "$ghs_file" ]; then
        ( _gh_state > "$ghs_file" ) &
        ghs_pid="$!"
      else
        ghs="$(_gh_state)"
        export _WRAP_GH_STATE="$ghs"
      fi
    fi
  fi
  i=1
  while [ "$i" -le "$count" ]; do
    _apply_repo "${repos[$i]}" "$ghs" "$ghs_file" "$ghs_pid"
    ghs="${_WRAP_GH_STATE:-$ghs}"; ghs_pid=""
    i=$(( i + 1 ))
  done
  [ -n "$ghs_pid" ] && wait "$ghs_pid" 2>/dev/null || true
  [ -n "$ghs_file" ] && rm -f "$ghs_file"
  echo "== ${MODE} complete. PR merges, deploy dispatch and board rows stay with the command."
  [ "$FAILURES" = 0 ] || return 2
  return 0
}

