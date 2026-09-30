# wrap-deploy.sh -- the default-branch, follow-mode, and deploy-wait verbs; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- default-branch

cmd_default_branch() {
  [ $# -eq 1 ] || { echo "usage: wrap.sh default-branch <repo>" >&2; return 64; }
  _is_repo "$1" || { echo "wrap.sh default-branch: $1 is not a git repo" >&2; return 1; }
  local def
  def="$(_default_branch "$1")" || { echo "wrap.sh default-branch: no default branch resolved for $1" >&2; return 1; }
  printf '%s\n' "$def"
  return 0
}

# --------------------------------------------------------------------------- follow-mode

# cmd_follow_mode [lanes|all] -- commands/wrap.md step 10's switch, resolved once. The knob
# wrap.follow_through is root-only and takes off, lanes, or all. The argument is the
# invocation override for one run (the word `follow` passes lanes, `follow all` passes all)
# and wins over the knob. An unknown knob value prints one line naming the knob and the
# allowed values and resolves as off: a typo must never start work, and never passes
# silently. Prints `<mode> <lanes>`: <lanes> is the comma list step 10 builds, which is
# wrap.build_lanes without full, plus full under all, or `none` when the mode is off.
cmd_follow_mode() {
  [ $# -le 1 ] || { echo "usage: wrap.sh follow-mode [lanes|all]" >&2; return 64; }
  local mode lanes="" lane
  mode="$(kit_config_get_root wrap.follow_through off)"
  case "$mode" in
    off|lanes|all) ;;
    *) echo "wrap.follow_through: unknown value '${mode}' (allowed: off, lanes, all); running as off" >&2
       mode=off ;;
  esac
  case "${1:-}" in
    "") ;;
    lanes|all) mode="$1" ;;
    *) echo "usage: wrap.sh follow-mode [lanes|all]" >&2; return 64 ;;
  esac
  if [ "$mode" != off ]; then
    set -f   # word-split the list, never glob it
    for lane in $(kit_config_get_root wrap.build_lanes "tiny"); do
      [ "$lane" = full ] || lanes="${lanes:+$lanes,}$lane"
    done
    set +f
    [ "$mode" = all ] && lanes="${lanes:+$lanes,}full"
  fi
  printf '%s %s\n' "$mode" "${lanes:-none}"
}

# --------------------------------------------------------------------------- deploy-wait

# cmd_deploy_wait <owner>/<name> <sha> [--check <substr>]... [--timeout <secs>] -- step 4's
# wait for a repo that deploys on push: the deploy is a check run on the merge commit
# (Cloudflare "Workers Builds: <name>"), not a workflow_dispatch run. Polls the commit's check
# runs every DEPLOY_POLL_SECS until every --check value matches a run and every matching run is
# completed. A rerun gets a new, higher id, so only the highest id per name counts (the
# stale-rerun bug _pr_gate fixed). Only `success` passes: a skipped deploy deployed nothing.
# Exit 0 all success, 1 a completed run failed, 2 gh missing or a non-transient read error,
# 124 timeout, 64 usage. Writes nothing but its own temp file.
DEPLOY_POLL_SECS="${DEPLOY_POLL_SECS:-10}"

# _dw_seconds -- elapsed-time source for the timeout budget. Real runs read bash's $SECONDS.
# A test can set DEPLOY_WAIT_CLOCK_FILE to a path it advances itself instead, so a stubbed
# slow `gh` reports its own elapsed time deterministically rather than a real sleep racing
# against $SECONDS' one-second granularity.
_dw_seconds() {
  if [ -n "${DEPLOY_WAIT_CLOCK_FILE:-}" ]; then cat "$DEPLOY_WAIT_CLOCK_FILE"
  else printf '%s' "$SECONDS"; fi
}

cmd_deploy_wait() {
  local usage="usage: wrap.sh deploy-wait <owner>/<name> <sha> [--check <name-substring>]... [--timeout <secs>]"
  local slug="" sha="" checks="" timeout=600 count=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --check)   [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; return 64; }; checks="${checks}$2"$'\n'; shift 2 ;;
      --timeout) [ $# -ge 2 ] || { echo "$usage" >&2; return 64; }; timeout="$2"; shift 2 ;;
      -*) echo "$usage" >&2; return 64 ;;
      *) count=$((count + 1)); case "$count" in 1) slug="$1" ;; 2) sha="$1" ;; esac; shift ;;
    esac
  done
  [ "$count" -eq 2 ] || { echo "$usage" >&2; return 64; }
  # grep matches line by line, so a value carrying a newline is refused before it.
  case "$slug$sha" in *$'\n'*|*$'\r'*) echo "$usage" >&2; return 64 ;; esac
  # A `.` or `..` segment would rewrite the API path, so neither half may be one.
  printf '%s' "$slug" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || { echo "$usage" >&2; return 64; }
  case "/$slug/" in */./*|*/../*) echo "$usage" >&2; return 64 ;; esac
  printf '%s' "$sha" | grep -qE '^[0-9a-fA-F]{7,40}$' || { echo "$usage" >&2; return 64; }
  case "$timeout" in ''|*[!0-9]*) echo "$usage" >&2; return 64 ;; esac

  local ghs
  ghs="$(_gh_state)"
  [ "$ghs" = ok ] || { echo "ERROR ${sha:0:7}: $(_gh_note "$ghs")"; return 2; }
  # gh writes a partial page set to stdout even when a later page fails, so the JSON and the
  # error text travel apart: stdout is judged only on exit 0, stderr only on a failure.
  local errf rc
  errf="$(mktemp "${TMPDIR:-/tmp}/wrap-deploy-wait.XXXXXX")" || { echo "ERROR ${sha:0:7}: mktemp failed"; return 2; }
  # A killed wait (a caller's own time limit) must not leave the file behind.
  trap 'rm -f "$errf"' EXIT INT TERM
  _deploy_wait_poll "$slug" "$sha" "$checks" "$timeout" "$errf"; rc=$?
  rm -f "$errf"
  # The trap names a local; left armed it fires after return under set -u.
  trap - EXIT INT TERM
  return "$rc"
}

# _deploy_wait_poll <slug> <sha> <checks, newline-separated> <timeout> <errfile>
_deploy_wait_poll() {
  local slug="$1" sha="$2" checks="$3" timeout="$4" errf="$5" s7="${2:0:7}"
  local waited=0 good=0 raw rc err runs="[]" state start
  start=$(_dw_seconds)
  # Keep the runs whose name contains any --check value (all runs with none), the highest id
  # per name. `missing` lists each --check value no run matches yet.
  local judge='($cs | split("\n") | map(select(. != ""))) as $want
    | [.[].check_runs[]? | .name as $n
       | select(($want | length) == 0 or any($want[]; . as $c | $n | contains($c)))]
    | group_by(.name) | map(max_by(.id)) | sort_by(.name)'
  while :; do
    raw="$(gh api --paginate "repos/${slug}/commits/${sha}/check-runs?per_page=100" 2>"$errf")"; rc=$?
    err="$(head -n 1 "$errf")"
    if [ "$rc" -eq 0 ]; then
      runs="$(printf '%s' "$raw" | jq -s -c --arg cs "$checks" "$judge" 2>/dev/null)"
      [ -n "$runs" ] || { echo "ERROR ${s7}: unreadable check-runs answer"; return 2; }
      good=$((good + 1))
      state="$(printf '%s' "$runs" | jq -r --arg cs "$checks" '
        ($cs | split("\n") | map(select(. != ""))) as $want
        | . as $runs
        | [$want[] | . as $c | select(all($runs[]; (.name | contains($c)) | not))] as $missing
        | if length == 0 or ($missing | length) > 0 then "missing"
          elif all(.status == "completed") then "completed"
          else "open" end')"
      [ "$state" = completed ] && break
      echo "deploy-wait ${s7}: $(_deploy_wait_pending "$runs" "$checks"), ${waited}s of ${timeout}s" >&2
    elif _gh_merge_transient < "$errf"; then
      echo "deploy-wait ${s7}: transient read error, retrying: ${err:-exit $rc}" >&2
    else
      echo "ERROR ${s7}: ${err:-gh api exited $rc}"; return 2
    fi
    if [ "$waited" -ge "$timeout" ]; then
      printf '%s' "$runs" | jq -r '.[] | "\(.conclusion // .status) \(.name)"'
      if [ "$good" -eq 0 ]; then
        echo "TIMEOUT ${s7} after ${waited}s: no successful read of the check runs"
      else
        echo "TIMEOUT ${s7} after ${waited}s: $(_deploy_wait_pending "$runs" "$checks")"
      fi
      return 124
    fi
    sleep "$DEPLOY_POLL_SECS"; waited=$((waited + DEPLOY_POLL_SECS))
    # Wall time also counts, so slow gh calls cannot stretch the timeout.
    local now; now=$(_dw_seconds)
    [ $((now - start)) -gt "$waited" ] && waited=$((now - start))
  done

  printf '%s' "$runs" | jq -r '.[] | "\(.conclusion // "none") \(.name)"'
  local failed
  failed="$(printf '%s' "$runs" | jq -r '[.[] | select(.conclusion != "success") | .name] | join(", ")')"
  if [ -n "$failed" ]; then echo "FAILED ${s7}: ${failed}"; return 1; fi
  echo "DEPLOYED ${s7}: $(printf '%s' "$runs" | jq -r 'length') checks succeeded"
}

# _deploy_wait_pending <runs json> <checks> -- what the wait is still on, one phrase.
_deploy_wait_pending() {
  printf '%s' "$1" | jq -r --arg cs "$2" '
    ($cs | split("\n") | map(select(. != ""))) as $want
    | . as $runs
    | [$want[] | . as $c | select(all($runs[]; (.name | contains($c)) | not))] as $missing
    | [.[] | select(.status != "completed") | .name] as $open
    | if length == 0 and ($want | length) == 0 then "no matching check run appeared"
      elif ($missing | length) > 0 then "no matching check run appeared for: \($missing | join(", "))"
      else "open: \($open | join(", "))" end'
}

