# wrap-ci.sh -- merge-time CI: on-merge toggle, label sync, checks wait; sourced by lib/wrap/wrap.sh.

# _ci_label_sync <repo-url> <pr> -- repos whose PR workflows run on `pull_request:
# types: [labeled]` only test a head when the PR carries the `ci` label, so an unlabeled
# PR reports an empty rollup and a pending-check wait reads it as "nothing pending" on an
# untested head. When the repo carries the label this adds it to the PR, or removes and
# re-adds it when the label predates the head (a `labeled` event fired before the pushed
# commits starts no run on them, which reads as the label present but an empty rollup on
# the current head). Returns 0 when the repo gates on `ci` and the PR now carries it, 1
# when the repo has no such label (a repo without one, or a repo whose label read failed,
# behaves exactly as before), 2 when the repo gates but the label could not be set: that
# merge would run untested, so the caller refuses it.
# A PR read that fails on a gating repo returns 2 as well: without it the sync cannot tell
# which checks predate the label, and the wait would end on them.
# When it adds the label it also sets the out-param CI_PRELABEL_KEYS to the keys of the checks
# already on the PR, so `_ci_checks_wait` can tell the runs the label starts from runs that
# predate it; in every other case CI_PRELABEL_KEYS is [] (the re-add branch runs only on an
# empty rollup).
#
# The `ci` label gate is opt-in: merges trigger no CI by default, so `--with-ci` on
# `merge`/`land` or `KIT_WRAP_CI_ON_MERGE=1` in the environment (the only switch
# `apply`'s autoland reads) is what arms it. Off, every merge runs as it did before the
# gate existed: no label, no wait, an empty rollup is mergeable.
KIT_WRAP_CI_ON_MERGE=${KIT_WRAP_CI_ON_MERGE:-0}
_ci_on_merge() { [ "$KIT_WRAP_CI_ON_MERGE" = "1" ]; }

# CI_JQ_DEFS is the one jq definition of a rollup entry that the ci wait, the carry wait and
# `_pr_gate` share. gh emits an absent URL as "" and an absent time as the zero time, never
# null, so `real` drops all three; `ckey` takes the first real URL or time after the check
# name, which keeps apart third-party checks sharing one detailsUrl; `pending` is a check
# not yet COMPLETED, or a commit status still PENDING or EXPECTED.
CI_JQ_DEFS='
  def real: select(. != null and . != "" and . != "0001-01-01T00:00:00Z");
  def pending: ((.status // "COMPLETED") != "COMPLETED")
    or ((.state // "") == "PENDING") or ((.state // "") == "EXPECTED");
  def ckey: (.name // .context // "") + "@" + ([.detailsUrl, .targetUrl, .startedAt, .createdAt] | map(real) | .[0] // "");
'
_ci_label_sync() {
  local url="$1" n="$2" detail
  CI_PRELABEL_KEYS='[]'
  gh label list --repo "$url" --search ci --limit 200 --json name 2>/dev/null \
    | jq -e '[.[] | select(.name == "ci")] | length > 0' >/dev/null 2>&1 || return 1
  detail="$(gh pr view "$n" --repo "$url" --json labels,statusCheckRollup 2>/dev/null)"
  printf '%s' "$detail" | jq -e 'type == "object"' >/dev/null 2>&1 || {
    echo "     could not read the labels and checks of #${n}" >&2; return 2; }
  if ! printf '%s' "$detail" | jq -e '[.labels // [] | .[] | select(.name == "ci")] | length > 0' >/dev/null 2>&1; then
    CI_PRELABEL_KEYS="$(printf '%s' "$detail" | jq -c "${CI_JQ_DEFS} [(.statusCheckRollup // [])[] | ckey]" 2>/dev/null)"
    [ -n "$CI_PRELABEL_KEYS" ] || CI_PRELABEL_KEYS='[]'
    gh pr edit "$n" --repo "$url" --add-label ci >/dev/null 2>&1 || {
      echo "     could not add the ci label to #${n}" >&2; return 2; }
    echo "     labeled #${n} ci (this repo runs PR checks only on the label)"
  elif [ "$(printf '%s' "$detail" | jq -r '(.statusCheckRollup // []) | length' 2>/dev/null)" = "0" ]; then
    { gh pr edit "$n" --repo "$url" --remove-label ci >/dev/null 2>&1 \
      && gh pr edit "$n" --repo "$url" --add-label ci >/dev/null 2>&1; } || {
      echo "     could not re-add the ci label on #${n}" >&2; return 2; }
    echo "     re-labeled #${n} ci (the label predates the head)"
  fi
  return 0
}

# _ci_checks_wait <repo-url> <pr> -- the bounded wait for the runs a `ci` label just
# started, used instead of the ordinary pending-check wait on a label-gated repo. Pending
# checks, and an unreadable read, wait to KIT_WRAP_CARRY_CHECKS_SECS. With nothing pending,
# the wait still holds while no NEW check has appeared: one outside CI_PRELABEL_KEYS that
# is not SKIPPED (another label's `labeled` event adds SKIPPED runs, which test nothing).
# The `labeled` event registers its runs a few seconds after the edit, and until then the
# rollup holds only checks that predate the label. That hold is bounded by
# KIT_WRAP_CI_GRACE_SECS; past it, the workflow is a paths-filtered one that started nothing
# and the wait ends. The out-param CI_WAIT_END is the last read's state (NONEW when the hold
# ran out), so `cmd_merge` can ask for a CLEAN merge state on that path. What red checks do
# is not this wait's call: the merge and its gate read them as they always did.
KIT_WRAP_CI_GRACE_SECS=${KIT_WRAP_CI_GRACE_SECS:-90}
case "$KIT_WRAP_CI_GRACE_SECS" in ''|*[!0-9]*) KIT_WRAP_CI_GRACE_SECS=90 ;; esac
_ci_checks_wait() {
  local url="$1" n="$2" waited=0 state
  while :; do
    state="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null \
      | jq -r --argjson prelabel "${CI_PRELABEL_KEYS:-[]}" "${CI_JQ_DEFS}"'
      (.statusCheckRollup // []) as $r
      | ([$r[] | select(pending)] | length) as $p
      | if $p > 0 then $p
        elif ([$r[] | select(((.conclusion // .state // "") | ascii_upcase) != "SKIPPED")
                    | ckey | select(IN($prelabel[]) | not)] | length) == 0 then "NONEW"
        else 0 end' 2>/dev/null)"
    [ "$state" = "0" ] && break
    if [ "$state" = "NONEW" ]; then
      [ "$waited" -lt "$KIT_WRAP_CI_GRACE_SECS" ] || break
    else
      [ "$waited" -lt "$KIT_WRAP_CARRY_CHECKS_SECS" ] || break
    fi
    sleep 10; waited=$(( waited + 10 ))
  done
  CI_WAIT_END="$state"
}

