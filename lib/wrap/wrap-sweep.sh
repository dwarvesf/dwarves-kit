# wrap-sweep.sh -- the sweep verb and post-merge sweep helper; sourced by lib/wrap/wrap.sh.

_sweep_path_sha1() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 1 | awk '{print $1}'
  else
    printf '%s' "$1" | sha1sum | awk '{print $1}'
  fi
}

_sweep_now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    awk -v t="$EPOCHREALTIME" 'BEGIN { printf "%.0f\n", t * 1000 }'
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

_sweep_repo_has_candidates() {
  local repo="$1" def b nwt=0
  if [ "$WORKTREES" = 1 ]; then
    nwt="$(git -C "$repo" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"
    [ "${nwt:-0}" -gt 1 ] && return 0
  fi
  def="$(_default_branch "$repo" 2>/dev/null || true)"
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    case "$b" in "$def"|main|master) continue ;; esac
    return 0
  done < <(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/ 2>/dev/null)
  return 1
}

# _sweep_discover_repos <roots...> -- emits "<kind>\t<path>" lines:
#   REPO        git repo to sweep (explicit repo root, or depth 1-2 child with candidates)
#   SKIP_NON    non-repo root passed explicitly
_sweep_discover_repos() {
  local nl=$'\n'
  local seen="$nl" root c1 c2 canon found_any
  for root in "$@"; do
    root="${root%/}"
    [ -n "$root" ] || root="/"
    if [ ! -d "$root" ]; then
      printf 'SKIP_NON\t%s\n' "$root"
      continue
    fi
    if [ -e "$root/.git" ]; then
      canon="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
      canon="${canon%/.git}"; canon="${canon%/}"
      canon="$(cd "$canon" 2>/dev/null && pwd -P)"
      [ -n "$canon" ] || canon="$(cd "$root" 2>/dev/null && pwd -P)"
      case "$seen" in
        *"$nl${canon}$nl"*) ;;
        *) seen="${seen}${canon}${nl}"; printf 'REPO\t%s\n' "$canon" ;;
      esac
      continue
    fi

    found_any=0
    local cand_list=""
    for c1 in "$root"/*/; do
      [ -d "$c1" ] || continue
      c1="${c1%/}"
      if [ -e "$c1/.git" ]; then
        found_any=1
        cand_list="${cand_list}${c1}${nl}"
      else
        for c2 in "$c1"/*/; do
          [ -d "$c2" ] || continue
          c2="${c2%/}"
          if [ -e "$c2/.git" ]; then
            found_any=1
            cand_list="${cand_list}${c2}${nl}"
          fi
        done
      fi
    done

    if [ "$found_any" = 0 ]; then
      printf 'SKIP_NON\t%s\n' "$root"
      continue
    fi

    while IFS= read -r c1; do
      [ -n "$c1" ] || continue
      canon="$(git -C "$c1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
      canon="${canon%/.git}"; canon="${canon%/}"
      canon="$(cd "$canon" 2>/dev/null && pwd -P)"
      [ -n "$canon" ] || continue
      case "$seen" in
        *"$nl${canon}$nl"*) continue ;;
      esac
      seen="${seen}${canon}${nl}"
      if _sweep_repo_has_candidates "$canon"; then
        printf 'REPO\t%s\n' "$canon"
      fi
    done < <(printf '%s' "$cand_list" | env LC_ALL=C sort)
  done
}

_sweep_lock_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

_sweep_lock_alive() {
  local p="$1"
  [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null && return 0
  ps -p "$p" >/dev/null 2>&1 && return 0
  return 1
}

_sweep_one_repo() {
  local repo="$1" out_json="$2" out_human="$3" ghs="$4"
  local lock_base="${XDG_STATE_HOME:-$HOME/.local/state}/wrap/locks"
  mkdir -p "$lock_base" 2>/dev/null || true
  local mypid="${BASHPID:-}"
  [ -n "$mypid" ] || mypid="$(sh -c 'echo $PPID' 2>/dev/null)"
  local stale_msg="" lock_acquired=0
  _SWEEP_LOCK_DIR="$lock_base/$(_sweep_path_sha1 "$repo")"
  if mkdir "$_SWEEP_LOCK_DIR" 2>/dev/null; then
    lock_acquired=1
  else
    local holder_pid="" lock_mtime="" now_s="" age="" max_age="${WRAP_SWEEP_LOCK_MAX_AGE:-1800}" stale_reason=""
    case "$max_age" in ''|*[!0-9]*|0) max_age=1800 ;; esac
    holder_pid="$(cat "$_SWEEP_LOCK_DIR/pid" 2>/dev/null | tr -dc '0-9')"
    if [ -n "$holder_pid" ]; then
      if ! _sweep_lock_alive "$holder_pid"; then
        stale_reason="reclaimed stale lock (dead pid ${holder_pid})"
      fi
    else
      lock_mtime="$(_sweep_lock_mtime "$_SWEEP_LOCK_DIR")"
      if [ -n "$lock_mtime" ]; then
        now_s="$(date +%s)"
        age=$(( now_s - lock_mtime ))
        [ "$age" -ge "$max_age" ] && stale_reason="reclaimed stale lock (no live pid, age ${age}s)"
      fi
    fi
    if [ -n "$stale_reason" ]; then
      local stale_tmp="${_SWEEP_LOCK_DIR}.stale.${mypid}.${RANDOM}"
      if mv "$_SWEEP_LOCK_DIR" "$stale_tmp" 2>/dev/null; then
        rm -rf "$stale_tmp" 2>/dev/null || true
        if mkdir "$_SWEEP_LOCK_DIR" 2>/dev/null; then
          lock_acquired=1
          stale_msg="$stale_reason"
        fi
      fi
    fi
  fi
  if [ "$lock_acquired" != 1 ]; then
    _SWEEP_LOCK_DIR=""
    local def_locked
    def_locked="$(_default_branch "$repo" 2>/dev/null || true)"
    printf '== %s: SKIPPED (locked by another sweep)\n' "$repo" > "$out_human"
    jq -cn --arg path "$repo" --arg def "$def_locked" '{
      path: $path,
      default_branch: (if $def == "" then null else $def end),
      skipped: "locked",
      error: null,
      rows: []
    }' > "$out_json"
    return 0
  fi
  printf '%s\n' "$mypid" > "$_SWEEP_LOCK_DIR/pid" 2>/dev/null || true
  trap 'rm -rf "${_SWEEP_LOCK_DIR:-}"' EXIT
  trap 'rm -rf "${_SWEEP_LOCK_DIR:-}"; exit 130' INT
  trap 'rm -rf "${_SWEEP_LOCK_DIR:-}"; exit 143' TERM HUP

  local fetch_err first_err def cur rows_file rows_arr err_line=""
  : > "$out_human"
  [ -z "$stale_msg" ] || printf '== %s: %s\n' "$repo" "$stale_msg" >> "$out_human"
  if ! fetch_err="$(git -C "$repo" fetch --prune -q 2>&1)"; then
    first_err="$(printf '%s\n' "$fetch_err" | awk 'NF { print; exit }')"
    [ -n "$first_err" ] || first_err="exit non-zero"
    printf '== %s: ERROR git fetch failed: %s\n' "$repo" "$first_err" >> "$out_human"
    jq -cn --arg path "$repo" --arg err "git fetch failed: ${first_err}" '{
      path: $path,
      default_branch: null,
      skipped: null,
      error: $err,
      rows: []
    }' > "$out_json"
    return 0
  fi

  if ! def="$(_default_branch "$repo" 2>/dev/null)"; then
    printf '== %s: ERROR no default branch resolved\n' "$repo" >> "$out_human"
    jq -cn --arg path "$repo" '{
      path: $path,
      default_branch: null,
      skipped: null,
      error: "no default branch resolved",
      rows: []
    }' > "$out_json"
    return 0
  fi

  cur="$(git -C "$repo" branch --show-current 2>/dev/null)"
  rows_file="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || rows_file="/dev/null"
  : > "$rows_file"

  FAILURES=0
  {
    echo "== ${repo}"
    _sweep_repo_apply "$repo" "$def" "$cur" "$ghs" "$rows_file"
  } >> "$out_human" 2>&1

  if [ -s "$rows_file" ]; then
    rows_arr="$(jq -cs '.' "$rows_file" 2>/dev/null || echo '[]')"
  else
    rows_arr="[]"
  fi
  [ "$rows_file" != "/dev/null" ] && rm -f "$rows_file"

  err_line="$(printf '%s' "$rows_arr" | jq -r '[.[] | select(.verdict == "error") | .reason][0] // ""' 2>/dev/null || true)"
  if [ -z "$err_line" ] && [ "$FAILURES" != 0 ]; then
    err_line="one or more cleanup operations failed"
  fi

  jq -cn --arg path "$repo" --arg def "$def" --arg err "$err_line" --argjson rows "$rows_arr" '{
    path: $path,
    default_branch: $def,
    skipped: null,
    error: (if $err == "" then null else $err end),
    rows: $rows
  }' > "$out_json"
}

cmd_sweep() {
  APPLY=0; WORKTREES=0; MODE="DRY-RUN"; FAILURES=0
  OWN_SET=""; OWN_SEEN=""; OWN_BRANCHES=""; OWN_N=0
  ARCHIVE_UNMERGED=0; ARCHIVE_WORKTREES=0; PULL_ONLY=0; NO_PULL=0

  local json_out=0 arg nroots=0
  local -a roots=()
  for arg in "$@"; do
    case "$arg" in
      --apply) APPLY=1 ;;
      --worktrees) WORKTREES=1 ;;
      --json) json_out=1 ;;
      -*) echo "wrap.sh sweep: unknown flag '$arg'" >&2; return 1 ;;
      *) _reject_packed sweep "$arg" || return 1
         roots[$nroots]="$arg"; nroots=$(( nroots + 1 )) ;;
    esac
  done

  if [ "$nroots" -eq 0 ]; then
    local cfg_roots r
    cfg_roots="$(kit_config_get_root wrap.sweep_roots "")"
    if [ -z "$cfg_roots" ]; then
      echo "wrap.sh sweep: no <root> given and wrap.sweep_roots is empty" >&2
      return 1
    fi
    for r in $cfg_roots; do
      roots[$nroots]="$r"; nroots=$(( nroots + 1 ))
    done
  fi

  local -a exp_roots=()
  local ri=0
  while [ "$ri" -lt "$nroots" ]; do
    arg="${roots[$ri]}"
    case "$arg" in
      "~") arg="$HOME" ;;
      "~/"*) arg="$HOME/${arg#\~/}" ;;
    esac
    exp_roots[$ri]="$arg"
    ri=$(( ri + 1 ))
  done

  [ "$APPLY" = 1 ] && MODE="APPLY"
  local started_at t0_ms t1_ms duration_ms mode_str
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  t0_ms="$(_sweep_now_ms)"
  if [ "$APPLY" = 1 ]; then mode_str="apply"; else mode_str="dry-run"; fi

  local ghs
  if [ -n "${_WRAP_GH_STATE:-}" ]; then
    ghs="$_WRAP_GH_STATE"
  else
    ghs="$(_gh_state)"
    export _WRAP_GH_STATE="$ghs"
  fi

  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/wrap-sweep.XXXXXX")" || return 2
  local -a pids=()
  local npids=0
  _sweep_cleanup() {
    local _p
    for _p in ${pids[@]+"${pids[@]}"}; do kill -TERM "$_p" 2>/dev/null || true; done
    wait 2>/dev/null || true
    rm -rf "$tmpdir"
  }
  trap '_sweep_cleanup' EXIT
  trap '_sweep_cleanup; exit 130' INT
  trap '_sweep_cleanup; exit 143' TERM HUP

  local max_jobs="${WRAP_SWEEP_JOBS:-6}"
  case "$max_jobs" in ''|*[!0-9]*|0) max_jobs=6 ;; esac

  local idx=0 kind target
  local -a json_files=() human_files=() repo_targets=()
  while IFS=$'\t' read -r kind target; do
    [ -n "$kind" ] || continue
    local jf="$tmpdir/repo-${idx}.json" hf="$tmpdir/repo-${idx}.human"
    json_files[$idx]="$jf"
    human_files[$idx]="$hf"
    repo_targets[$idx]="$target"
    idx=$(( idx + 1 ))

    if [ "$kind" = "SKIP_NON" ]; then
      printf '== %s: not a git repo, skipped\n' "$target" > "$hf"
      jq -cn --arg path "$target" '{
        path: $path,
        default_branch: null,
        skipped: "not a git repo",
        error: null,
        rows: []
      }' > "$jf"
      continue
    fi

    while [ "$npids" -ge "$max_jobs" ]; do
      local -a next_pids=()
      local next_n=0 p
      for p in ${pids[@]+"${pids[@]}"}; do
        if kill -0 "$p" 2>/dev/null; then
          next_pids[$next_n]="$p"; next_n=$(( next_n + 1 ))
        else
          wait "$p" 2>/dev/null || true
        fi
      done
      pids=(${next_pids[@]+"${next_pids[@]}"})
      npids="$next_n"
      [ "$npids" -ge "$max_jobs" ] && sleep 0.05
    done

    ( _sweep_one_repo "$target" "$jf" "$hf" "$ghs" ) &
    pids[$npids]="$!"; npids=$(( npids + 1 ))
  done < <(_sweep_discover_repos "${exp_roots[@]}")

  local p
  for p in ${pids[@]+"${pids[@]}"}; do
    wait "$p" 2>/dev/null || true
  done
  pids=(); npids=0

  local i=0 jf_chk hf_chk rpath_chk
  while [ "$i" -lt "$idx" ]; do
    jf_chk="${json_files[$i]}"
    hf_chk="${human_files[$i]}"
    rpath_chk="${repo_targets[$i]}"
    if [ ! -s "$jf_chk" ] || ! jq -e 'type == "object" and (.path | type == "string") and (.rows | type == "array")' "$jf_chk" >/dev/null 2>&1; then
      printf '== %s: ERROR worker exited without valid output\n' "$rpath_chk" >> "$hf_chk"
      jq -cn --arg path "$rpath_chk" '{
        path: $path,
        default_branch: null,
        skipped: null,
        error: "worker exited without valid output",
        rows: []
      }' > "$jf_chk"
    fi
    i=$(( i + 1 ))
  done

  t1_ms="$(_sweep_now_ms)"
  duration_ms=$(( t1_ms - t0_ms ))
  [ "$duration_ms" -lt 0 ] && duration_ms=0

  local roots_json repos_json doc
  roots_json="$(printf '%s\n' "${exp_roots[@]}" | jq -Rsc 'split("\n")[:-1]')"
  if [ "$idx" -gt 0 ]; then
    repos_json="$(jq -cs '.' "${json_files[@]}")"
  else
    repos_json="[]"
  fi

  doc="$(jq -n \
    --arg mode "$mode_str" \
    --arg started "$started_at" \
    --argjson dur "$duration_ms" \
    --argjson roots "$roots_json" \
    --argjson repos "$repos_json" '
    {
      schema: "wrap-sweep/1",
      mode: $mode,
      started_at: $started,
      duration_ms: $dur,
      roots: $roots,
      repos: $repos,
      summary: {
        repos: ($repos | length),
        removed: ([ $repos[].rows[] | select(.verdict == "removed") ] | length),
        would_remove: ([ $repos[].rows[] | select(.verdict == "would_remove") ] | length),
        keep: ([ $repos[].rows[] | select(.verdict == "keep") ] | length),
        errors: ([ $repos[] | select(.error != null) ] | length),
        skipped: ([ $repos[] | select(.skipped != null) ] | length)
      }
    }')"

  local hf
  if [ "$json_out" = 1 ]; then
    for hf in ${human_files[@]+"${human_files[@]}"}; do
      [ -s "$hf" ] && cat "$hf" >&2
    done
    printf '%s\n' "$doc"
  else
    for hf in ${human_files[@]+"${human_files[@]}"}; do
      [ -s "$hf" ] && cat "$hf"
    done
    echo "== ${MODE} sweep complete."
  fi

  local exit_rc=0 errors_cnt all_locked
  errors_cnt="$(printf '%s' "$doc" | jq -r '.summary.errors')"
  all_locked="$(printf '%s' "$doc" | jq -r '(.repos | length) > 0 and all(.repos[]; .skipped == "locked")')"
  if [ "$all_locked" = "true" ]; then
    exit_rc=3
  elif [ "${errors_cnt:-0}" -gt 0 ]; then
    exit_rc=2
  fi

  rm -rf "$tmpdir"
  trap - EXIT INT TERM HUP
  return "$exit_rc"
}

# _post_merge_sweep <repo> -- runs `wrap sweep --apply --worktrees` on <repo> after a merge.
# Reports removed count on stdout if > 0; never fails or alters caller exit code.
_post_merge_sweep() {
  local repo="$1" out removed
  out="$( cmd_sweep --apply --worktrees --json "$repo" 2>/dev/null )" || true
  removed="$(printf '%s' "$out" | jq -r '.summary.removed // 0' 2>/dev/null || echo 0)"
  case "$removed" in
    ''|*[!0-9]*|0) ;;
    *) echo "     post-merge sweep: removed ${removed} item(s)" ;;
  esac
  return 0
}
