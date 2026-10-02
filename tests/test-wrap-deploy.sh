#!/usr/bin/env bash
# test-wrap-deploy.sh -- the default-branch and deploy-wait cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ------------------------------------------------- seed: the scan section's clones
# default-branch reads clone-scan-main/-master/-develop (monolith lines 291-295).
for pair in "rmain main" "rmaster master" "rdev develop"; do
  set -- $pair
  rname="$1"; def="$2"
  make_clone "scan-$def" "$rname" "$def" unmerged
  set_stub "$rname" "$def"
done
# ===========================================================================
echo "=== default-branch: detection, fall-through, and the no-remote refusal ==="
# ===========================================================================
chk "default-branch prints main" "$([ "$("$WRAP" default-branch "$TMPD/clone-scan-main")" = "main" ]; echo $?)"
chk "default-branch prints master" "$([ "$("$WRAP" default-branch "$TMPD/clone-scan-master")" = "master" ]; echo $?)"
chk "default-branch prints develop" "$([ "$("$WRAP" default-branch "$TMPD/clone-scan-develop")" = "develop" ]; echo $?)"

git clone -q "$TMPD/bare-rmain" "$TMPD/clone-dangling"
gitc "$TMPD/clone-dangling"
git -C "$TMPD/clone-dangling" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/renamed-away
chk "default-branch falls through to main when origin/HEAD dangles" \
  "$([ "$("$WRAP" default-branch "$TMPD/clone-dangling")" = "main" ]; echo $?)"

mkdir -p "$TMPD/remoteless"
git -C "$TMPD/remoteless" init -q; gitc "$TMPD/remoteless"
echo x > "$TMPD/remoteless/x.txt"; git -C "$TMPD/remoteless" add -A; git -C "$TMPD/remoteless" commit -qm x
out="$("$WRAP" default-branch "$TMPD/remoteless" 2>&1)"; rc=$?
chk "default-branch exits 1 on a repo with no remote" "$([ "$rc" -eq 1 ]; echo $?)"

# ------------------------------------------------------- deploy-wait
# A push-deploy repo carries its deploy as a check run on the merge commit. The stub serves
# read k from $DW/read-<k>.json (the last file present once k runs past them), with an
# optional read-<k>.rc exit code, so a case scripts pending -> completed or a 502 -> success.
# The no-op sleep first on PATH makes every poll instant while the waited counter still
# advances by the verb's own 10s step, so a timeout case is deterministic.
echo
echo "=== deploy-wait: a SHA's push-deploy check runs, waited on until completed ==="
mkdir -p "$TMPD/dwstub"
cat > "$TMPD/dwstub/gh" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  auth) exit 0 ;;
  api)
    printf '%s\n' "$*" >> "$DW/calls.log"
    n=$(( $(cat "$DW/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$DW/count"
    k="$n"; while [ "$k" -gt 1 ] && [ ! -e "$DW/read-$k.json" ]; do k=$((k - 1)); done
    # A failing read prints its error on stderr, and any partial pages (read-<k>.out) on
    # stdout, the way real gh does when a later page of --paginate fails.
    rc="$(cat "$DW/read-$k.rc" 2>/dev/null || echo 0)"
    if [ "$rc" -eq 0 ]; then cat "$DW/read-$k.json"
    else cat "$DW/read-$k.out" 2>/dev/null; cat "$DW/read-$k.json" >&2; fi
    exit "$rc" ;;
esac
exit 1
STUB
chmod +x "$TMPD/dwstub/gh"
SHA=0123456789abcdef0123456789abcdef01234567
dw_case() { DW="$TMPD/dw-$1"; export DW; mkdir -p "$DW"; }
dw_read() { printf '%s\n' "$2" > "$DW/read-$1.json"; }
dw_run() { PATH="$TMPD/nosleep:$TMPD/dwstub:$PATH" "$WRAP" deploy-wait "$@" 2>&1; }
dw_reads() { cat "$DW/count" 2>/dev/null || echo 0; }
run_json() { # run_json <id> <name> <status> <conclusion|null>
  local c="null"; [ "$4" = null ] || c="\"$4\""
  printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "$3" "$c"
}
WB_OK="$(run_json 11 'Workers Builds: site' completed success)"
CI_OK="$(run_json 12 'ci / test' completed success)"
CI_BAD="$(run_json 13 'ci / test' completed failure)"
WB_OPEN="$(run_json 11 'Workers Builds: site' in_progress null)"

echo "--- all success: exit 0, one line per check, DEPLOYED"
dw_case ok; dw_read 1 "{\"total_count\":2,\"check_runs\":[$WB_OK,$CI_OK]}"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait all success exits 0" "$rc"
chk_has "deploy-wait prints the deploy check's conclusion" "$out" "success Workers Builds: site"
chk_has "deploy-wait prints the CI check's conclusion" "$out" "success ci / test"
chk_has "deploy-wait reports DEPLOYED with the short sha" "$out" "DEPLOYED 0123456: 2 checks succeeded"
chk_no "deploy-wait exits without an unbound-variable error" "$out" "unbound variable"
chk_has "deploy-wait reads the commit's check runs, paginated" "$(cat "$DW/calls.log")" \
  "api --paginate repos/o/r/commits/${SHA}/check-runs?per_page=100"

echo "--- one failure: non-zero, the failed check named"
dw_case fail; dw_read 1 "{\"check_runs\":[$WB_OK,$CI_BAD]}"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait with a failed check exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "deploy-wait names the failed check" "$out" "FAILED 0123456: ci / test"
chk_has "deploy-wait still prints the failed conclusion line" "$out" "failure ci / test"
chk_no "deploy-wait never claims DEPLOYED on a failure" "$out" "DEPLOYED"

echo "--- pending then success: waits, then exit 0"
dw_case pend; dw_read 1 "{\"check_runs\":[$WB_OPEN]}"; dw_read 3 "{\"check_runs\":[$WB_OK]}"
out="$(dw_run o/r "$SHA" --check "Workers Builds")"; rc=$?
chk "deploy-wait pending then success exits 0" "$rc"
chk "deploy-wait polled until the check completed (3 reads)" "$([ "$(dw_reads)" -eq 3 ]; echo $?)"
chk_has "deploy-wait names the open check while waiting" "$out" "open: Workers Builds: site"
chk_has "deploy-wait reports DEPLOYED once it completes" "$out" "DEPLOYED 0123456: 1 checks succeeded"

echo "--- timeout: a distinct exit code, the open check named"
dw_case to; dw_read 1 "{\"check_runs\":[$WB_OPEN]}"
out="$(dw_run o/r "$SHA" --timeout 20)"; rc=$?
chk "deploy-wait timeout exits 124" "$([ "$rc" -eq 124 ]; echo $?)"
chk_has "deploy-wait timeout names the open check" "$out" "TIMEOUT 0123456 after 20s: open: Workers Builds: site"
chk_has "deploy-wait timeout prints the open status" "$out" "in_progress Workers Builds: site"
chk "deploy-wait timeout is bounded (reads at 0s, 10s, 20s)" "$([ "$(dw_reads)" -eq 3 ]; echo $?)"

echo "--- timeout: slow gh calls count toward it (wall time, not just the poll sleeps)"
# A stubbed clock file stands in for wall time: the slow-gh stub advances it by 2 on every
# call instead of really sleeping, so the assertion is exact arithmetic, not a race between
# a real sleep and $SECONDS' one-second granularity.
mkdir -p "$TMPD/dwslow"
CLOCKF="$TMPD/dw-slow-clock"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = api ]; then echo $(($(cat "%s") + 2)) > "%s"; fi\nexec "%s/dwstub/gh" "$@"\n' \
  "$CLOCKF" "$CLOCKF" "$TMPD" > "$TMPD/dwslow/gh"
chmod +x "$TMPD/dwslow/gh"
dw_case slow; dw_read 1 "{\"check_runs\":[$WB_OPEN]}"
printf '0' > "$CLOCKF"
out="$(DEPLOY_POLL_SECS=1 DEPLOY_WAIT_CLOCK_FILE="$CLOCKF" PATH="$TMPD/nosleep:$TMPD/dwslow:$PATH" "$WRAP" deploy-wait o/r "$SHA" --timeout 3 2>&1)"; rc=$?
chk "deploy-wait slow-gh timeout exits 124" "$([ "$rc" -eq 124 ]; echo $?)"
chk "deploy-wait counts gh time: 3 reads of 2s pass a 3s timeout (sleeps alone take 4)" "$([ "$(dw_reads)" -eq 3 ]; echo $?)"

echo "--- no match: the filter keeps waiting, then times out saying so"
dw_case nomatch; dw_read 1 "{\"check_runs\":[$CI_OK]}"
out="$(dw_run o/r "$SHA" --check "Workers Builds" --timeout 10)"; rc=$?
chk "deploy-wait with no matching run exits 124" "$([ "$rc" -eq 124 ]; echo $?)"
chk_has "deploy-wait says no matching run appeared" "$out" "no matching check run appeared"

echo "--- --check: only the matching runs are judged"
dw_case filter; dw_read 1 "{\"check_runs\":[$WB_OK,$CI_BAD]}"
out="$(dw_run o/r "$SHA" --check "Workers Builds")"; rc=$?
chk "deploy-wait --check ignores a failed CI run" "$rc"
chk_no "deploy-wait --check never names the filtered-out run" "$out" "ci / test"

echo "--- a rerun supersedes the run it replaced"
dw_case rerun
dw_read 1 "{\"check_runs\":[$(run_json 21 'Workers Builds: site' completed success),$(run_json 20 'Workers Builds: site' completed failure)]}"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait judges the highest id per name" "$rc"
chk_no "deploy-wait drops the stale failed run" "$out" "failure"

echo "--- read errors: a transient one retries, any other one stops at once"
dw_case transient; dw_read 1 "HTTP 502: Bad Gateway"; echo 1 > "$DW/read-1.rc"
dw_read 2 "{\"check_runs\":[$WB_OK]}"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait retries past a 502" "$rc"
chk_has "deploy-wait names the transient retry" "$out" "transient read error"
dw_case hard; dw_read 1 "HTTP 422: No commit found for SHA"; echo 1 > "$DW/read-1.rc"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait stops on a non-transient error with exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "deploy-wait names the read error" "$out" "ERROR 0123456: HTTP 422"
chk "deploy-wait read only once on a hard error" "$([ "$(dw_reads)" -eq 1 ]; echo $?)"
dw_case hard-out; dw_read 1 "gh: HTTP 404: Not Found"; echo 1 > "$DW/read-1.rc"
printf '%s\n' '{"check_runs":[{"id":1,"name":"x","status":"completed","conclusion":"failure","output":{"summary":"build timed out"}}]}' > "$DW/read-1.out"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait classifies the error text only, never the partial stdout" "$([ "$rc" -eq 2 ]; echo $?)"

echo "--- every page is read: a check on page two still counts"
dw_case pages
printf '%s\n%s\n' "{\"check_runs\":[$CI_OK]}" "{\"check_runs\":[$(run_json 14 'Workers Builds: site' completed failure)]}" > "$DW/read-1.json"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait judges a failure on the second page" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "deploy-wait names the second page's failed check" "$out" "FAILED 0123456: Workers Builds: site"

echo "--- a partial page set from a failed read is never judged"
dw_case partial; dw_read 1 "gh: HTTP 502: Bad Gateway"; echo 1 > "$DW/read-1.rc"
printf '%s\n' "{\"check_runs\":[$CI_OK]}" > "$DW/read-1.out"
dw_read 2 "{\"check_runs\":[$CI_OK,$(run_json 15 'Workers Builds: site' completed failure)]}"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait rereads after a failed paginated read (exit 1 from the full read)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "deploy-wait read twice" "$([ "$(dw_reads)" -eq 2 ]; echo $?)"

echo "--- only success passes: a skipped deploy deployed nothing"
dw_case skipped; dw_read 1 "{\"check_runs\":[$(run_json 16 'Workers Builds: site' completed skipped)]}"
out="$(dw_run o/r "$SHA")"; rc=$?
chk "deploy-wait fails a skipped check" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "deploy-wait names the skipped check" "$out" "FAILED 0123456: Workers Builds: site"

echo "--- repeated --check: every value must match a run before the wait can end"
dw_case multi; dw_read 1 "{\"check_runs\":[$WB_OK]}"
out="$(dw_run o/r "$SHA" --check "Workers Builds: site" --check "Workers Builds: api" --timeout 10)"; rc=$?
chk "deploy-wait waits on a --check value no run matches yet" "$([ "$rc" -eq 124 ]; echo $?)"
chk_has "deploy-wait names the unmatched --check value" "$out" "no matching check run appeared for: Workers Builds: api"
dw_case multi-ok; dw_read 1 "{\"check_runs\":[$WB_OK,$(run_json 17 'Workers Builds: api' completed success)]}"
out="$(dw_run o/r "$SHA" --check "Workers Builds: site" --check "Workers Builds: api")"; rc=$?
chk "deploy-wait exits 0 once every --check value succeeded" "$rc"
chk_has "deploy-wait counts both checks" "$out" "DEPLOYED 0123456: 2 checks succeeded"

echo "--- a transient error on every read times out naming the reads, not the checks"
dw_case outage; dw_read 1 "gh: HTTP 503: Service Unavailable"; echo 1 > "$DW/read-1.rc"
out="$(dw_run o/r "$SHA" --timeout 10)"; rc=$?
chk "deploy-wait outage exits 124" "$([ "$rc" -eq 124 ]; echo $?)"
chk_has "deploy-wait outage says no read succeeded" "$out" "no successful read of the check runs"

echo "--- gh logged out: exit 2 before any read"
dw_case unauth; dw_read 1 '{"check_runs":[]}'
out="$(GH_STUB_UNAUTH=1 PATH="$TMPD/nosleep:$TMPD/stub:$PATH" "$WRAP" deploy-wait o/r "$SHA" 2>&1)"; rc=$?
chk "deploy-wait with gh logged out exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "deploy-wait names the gh state" "$out" "ERROR 0123456: (gh unauthenticated)"

echo "--- usage: exit 64"
dw_case usage; dw_read 1 '{"check_runs":[]}'
for args in "" "o/r" "not-a-slug $SHA" "./r $SHA" "o/.. $SHA" "o/r xyz" "o/r $SHA --timeout abc" "o/r $SHA --bogus"; do
  # shellcheck disable=SC2086
  out="$(dw_run $args)"; rc=$?
  chk "deploy-wait usage error exits 64 (args: ${args:-none})" "$([ "$rc" -eq 64 ]; echo $?)"
done
out="$(dw_run $'o/r\nx/y' "$SHA")"; rc=$?
chk "deploy-wait refuses a newline in the slug" "$([ "$rc" -eq 64 ]; echo $?)"
out="$(dw_run o/r $'0123456\nzz')"; rc=$?
chk "deploy-wait refuses a newline in the sha" "$([ "$rc" -eq 64 ]; echo $?)"
out="$(dw_run o/r "$SHA" --check "")"; rc=$?
chk "deploy-wait refuses an empty --check" "$([ "$rc" -eq 64 ]; echo $?)"
out="$(dw_run o/r "$SHA" --timeout)"; rc=$?
chk "deploy-wait refuses --timeout with no value" "$([ "$rc" -eq 64 ]; echo $?)"
chk "deploy-wait usage errors never read GitHub" "$([ "$(dw_reads)" -eq 0 ]; echo $?)"
chk_has "commands/wrap.md step 4 runs deploy-wait for a push deploy" "$(cat "$KIT_DIR/commands/wrap.md")" "bin/wrap deploy-wait <owner>/<name> <merge-sha> --check"
chk_has "commands/wrap.md step 4 claims DEPLOYED only on exit 0" "$(cat "$KIT_DIR/commands/wrap.md")" "The report claims \`DEPLOYED\` only after it exits 0."

# ------------------------------------------------------- autonomy knobs (wrap.*)
# The three knobs `commands/wrap.md` reads at step -1. They govern a write each, so the
# fence that matters is the third block: a project `.kit.toml` rides inside a pull request
# and must never widen what wrap does to the machine running it.
echo
echo "=== autonomy knobs ==="
# shellcheck source=/dev/null
. "$KIT_DIR/lib/config/kit-config.sh"
KNOB_OP="$TMPD/knob-operator"; KNOB_PROJ="$TMPD/knob-project"
mkdir -p "$KNOB_OP" "$KNOB_PROJ"
printf '[wrap]\nmerge_own_prs = false\ntidy_worktrees = false\nbuild_candidates = false\ndelete_merged_remote_branches = false\n' > "$KNOB_OP/kit.toml"
printf '[wrap]\nmerge_own_prs = false\ntidy_worktrees = false\nbuild_candidates = false\ndelete_merged_remote_branches = false\n' > "$KNOB_PROJ/.kit.toml"
for knob in merge_own_prs tidy_worktrees build_candidates delete_merged_remote_branches; do
  v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root "wrap.$knob" true)"
  chk "wrap.$knob ships as true" "$([ "$v" = "true" ]; echo $?)"
  v="$(KIT_CONFIG_OPERATOR="$KNOB_OP" kit_config_get_root "wrap.$knob" true)"
  chk "wrap.$knob honours the operator kit.toml" "$([ "$v" = "false" ]; echo $?)"
  v="$(KIT_PROJECT_ROOT="$KNOB_PROJ" kit_config_get_root "wrap.$knob" true)"
  chk "wrap.$knob ignores a project .kit.toml" "$([ "$v" = "true" ]; echo $?)"
done
for knob in merge_own_prs tidy_worktrees build_candidates delete_merged_remote_branches pull_past_dirty distill follow_through; do
  chk_has "commands/wrap.md reads wrap.$knob" "$(cat "$KIT_DIR/commands/wrap.md")" "wrap.$knob"
  chk_has "kit.toml declares $knob" "$(cat "$KIT_DIR/kit.toml")" "$knob"
done
# distill is the switch for the whole distill half (the pre-0 scan, the seams, step 7). It ships
# ON: operators asked for it every session, and a plain `/kit:wrap` still lands first regardless.
# `distill = false` in the operator kit.toml restores landing-only. It authorizes writes to home
# repos, so the project fence holds like every other [wrap] knob.
DS_OFF="$TMPD/distill-operator"; DS_PROJ="$TMPD/distill-project"; DS_NO_OP="$TMPD/distill-no-operator"
mkdir -p "$DS_OFF" "$DS_PROJ" "$DS_NO_OP"
printf '[wrap]\ndistill = false\n' > "$DS_OFF/kit.toml"
printf '[wrap]\ndistill = false\n' > "$DS_PROJ/.kit.toml"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$DS_NO_OP" kit_config_get_root wrap.distill false)"
chk "wrap.distill ships as true" "$([ "$v" = "true" ]; echo $?)"
v="$(KIT_CONFIG_OPERATOR="$DS_OFF" kit_config_get_root wrap.distill true)"
chk "wrap.distill honours the operator kit.toml" "$([ "$v" = "false" ]; echo $?)"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$DS_NO_OP" KIT_PROJECT_ROOT="$DS_PROJ" kit_config_get_root wrap.distill true)"
chk "wrap.distill ignores a project .kit.toml" "$([ "$v" = "true" ]; echo $?)"
chk_has "commands/wrap.md takes the distill argument" "$(cat "$KIT_DIR/commands/wrap.md")" "/kit:wrap distill"

# Built-in default resolution with NO operator file at all (KIT_CONFIG_OPERATOR points at an
# empty temp dir, not one that exists with content): distill=true, follow_through=off.
DS_EMPTY="$TMPD/distill-empty-operator"; mkdir -p "$DS_EMPTY"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$DS_EMPTY" kit_config_get_root wrap.distill false)"
chk "built-in default (no operator file): wrap.distill resolves true" "$([ "$v" = "true" ]; echo $?)"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$DS_EMPTY" kit_config_get_root wrap.follow_through lanes)"
chk "built-in default (no operator file): wrap.follow_through resolves off" "$([ "$v" = "off" ]; echo $?)"
# follow_through gates step 10, which starts new work after the operator has their report, so
# it ships "off"; it authorizes writes in home repos, so the project fence holds like every
# other [wrap] knob. `wrap follow-mode` is the one resolver: knob, override, lanes, and the
# loud fallback for a value it does not know.
FT_ON="$TMPD/follow-operator"; FT_PROJ="$TMPD/follow-project"; FT_BAD="$TMPD/follow-bad"
mkdir -p "$FT_ON" "$FT_PROJ" "$FT_BAD"
printf '[wrap]\nfollow_through = "lanes"\nbuild_lanes = "tiny normal full"\n' > "$FT_ON/kit.toml"
printf '[wrap]\nfollow_through = "all"\n' > "$FT_PROJ/.kit.toml"
printf '[wrap]\nfollow_through = true\n' > "$FT_BAD/kit.toml"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root wrap.follow_through lanes)"
chk "wrap.follow_through ships as off" "$([ "$v" = "off" ]; echo $?)"
out="$("$WRAP" follow-mode 2>&1)"; rc=$?
chk "follow-mode: the shipped default is off with no lanes" "$([ "$rc" -eq 0 ] && [ "$out" = "off none" ]; echo $?)"
out="$(KIT_CONFIG_OPERATOR="$FT_ON" "$WRAP" follow-mode 2>&1)"
chk "follow-mode: the operator kit.toml sets lanes, and full never joins them" "$([ "$out" = "lanes tiny,normal" ]; echo $?)"
out="$(KIT_PROJECT_ROOT="$FT_PROJ" "$WRAP" follow-mode 2>&1)"
chk "follow-mode: a project .kit.toml cannot turn it on" "$([ "$out" = "off none" ]; echo $?)"
out="$("$WRAP" follow-mode lanes 2>&1)"
chk "follow-mode: the follow argument runs lanes over an off knob" "$([ "$out" = "lanes tiny" ]; echo $?)"
out="$(KIT_CONFIG_OPERATOR="$FT_ON" "$WRAP" follow-mode all 2>&1)"
chk "follow-mode: follow all adds full to the lanes" "$([ "$out" = "all tiny,normal,full" ]; echo $?)"
out="$("$WRAP" follow-mode all 2>&1)"
chk "follow-mode: all adds full even when build_lanes lacks it" "$([ "$out" = "all tiny,full" ]; echo $?)"
err="$(KIT_CONFIG_OPERATOR="$FT_BAD" "$WRAP" follow-mode 2>&1 >/dev/null)"
out="$(KIT_CONFIG_OPERATOR="$FT_BAD" "$WRAP" follow-mode 2>/dev/null)"; rc=$?
chk "follow-mode: an unknown knob value runs as off" "$([ "$rc" -eq 0 ] && [ "$out" = "off none" ]; echo $?)"
chk_has "follow-mode: an unknown value is named with the allowed values" "$err" "wrap.follow_through: unknown value 'true' (allowed: off, lanes, all); running as off"
chk "follow-mode: the unknown-value warning is one line" "$([ "$(printf '%s\n' "$err" | grep -c .)" -eq 1 ]; echo $?)"
rc=0; "$WRAP" follow-mode everything >/dev/null 2>&1 || rc=$?
chk "follow-mode: an unknown override exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
rc=0; "$WRAP" follow-mode lanes extra >/dev/null 2>&1 || rc=$?
chk "follow-mode: a second argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
FT_GLOB="$TMPD/follow-glob"; mkdir -p "$FT_GLOB"
printf '[wrap]\nfollow_through = "lanes"\nbuild_lanes = "tiny *"\n' > "$FT_GLOB/kit.toml"
out="$(cd "$TMPD" && KIT_CONFIG_OPERATOR="$FT_GLOB" "$WRAP" follow-mode 2>&1)"
chk "follow-mode: a glob in build_lanes is never expanded against the cwd" "$([ "$out" = "lanes tiny,*" ]; echo $?)"
WRAP_MD="$(cat "$KIT_DIR/commands/wrap.md")"
chk_has "commands/wrap.md takes the follow argument" "$WRAP_MD" "the word \`follow\` (or \`--follow-through\`)"
chk_has "commands/wrap.md takes follow all, and all only right after follow" "$WRAP_MD" "\`all\` is an argument only right after \`follow\`"
chk_has "commands/wrap.md resolves the mode through follow-mode" "$WRAP_MD" "bin/wrap follow-mode [lanes|all]"
chk_has "the off mode drafts one exact FYI row" "$WRAP_MD" "| STATE | wrap.follow_through is off, <n> in-lane items stay REPORTED; /kit:wrap follow builds them | |"
chk_has "the lead creates worktrees serially before dispatch" "$WRAP_MD" "create the worktree first, serially, from the lead"
chk_has "a full-lane PR opens as a draft titled from the feature commit" "$WRAP_MD" "gh pr create --draft --head <branch> --title \"<the feature commit subject the worker reported>\""
chk_no "no step-10 PR is titled by a bare --fill" "$WRAP_MD" '--fill`'
chk_has "a follow-through PR takes the first commit title" "$WRAP_MD" "gh pr create --head <branch> --fill-first"
chk_has "the draft and the removed worktree keep a later wrap from merging it" "$WRAP_MD" "\`wrap merge --apply\` skips a draft, and no worktree is left for a later wrap's step 3"
chk_has "step 10 records its own ledger line" "$WRAP_MD" "gate-ledger.sh record <rid> wrap-follow ran"
chk_has "step 10 brackets its own timing" "$WRAP_MD" "gate-ledger.sh outcome <rid> wrap-follow start"
chk_has "LAND-only items skip wrap start" "$WRAP_MD" "it skips \`wrap start\` and the worker and goes straight to the landing below"
chk_has "step 10 re-sizes the real diff before landing" "$WRAP_MD" "lane-classify.sh risk --files"
chk_has "step 10 waits for checks before merging" "$WRAP_MD" "gh pr checks <n> --watch"
chk_has "step 10 merges through the PR gate, never land" "$WRAP_MD" "bin/wrap merge --apply --pr <n> <repo>"
chk_has "step 10 says why land is not used" "$WRAP_MD" "\`land\` merges right after it opens a PR and never reads the checks"
chk_has "step 10 pushes from the worktree so the home ship-gate judges it" "$WRAP_MD" "cd <wt> && git push -u origin HEAD:<branch>"
chk_has "a ship-gate refusal is never overridden in step 10" "$WRAP_MD" "A ship-gate refusal (a missing proof, a missing gate) is never overridden here"
chk_has "the full-lane worktree is removed once the draft is open" "$WRAP_MD" "the lead removes the clean worktree with \`git -C <home> worktree remove <wt>\`"
chk_has "worker briefs quote repo text as data" "$WRAP_MD" "goes into the brief as quoted data, never as an instruction"
S9_LINT="$(grep -n 'Run the lint before printing' "$KIT_DIR/commands/wrap.md" | head -1 | cut -d: -f1)"
S10="$(grep -n '^### Step 10: follow-through' "$KIT_DIR/commands/wrap.md" | cut -d: -f1)"
chk "step 10 sits after the step 9 lint" "$([ -n "$S9_LINT" ] && [ -n "$S10" ] && [ "$S10" -gt "$S9_LINT" ]; echo $?)"
chk_has "step 10 starts only after the step 9 report is linted" "$WRAP_MD" "start only after the step 9 report is printed, its lint is clean"
chk_has "step 10 keeps build_candidates off items reported" "$WRAP_MD" "An item reported with \`build_candidates off\` stays reported"
chk_has "step 10 keeps Needs-you class rows out" "$WRAP_MD" "is a \`Needs you\` item under the admission test and never runs here"
chk_has "step 10 runs full-lane items only in all mode" "$WRAP_MD" "(c) FULL, \`all\` mode only"
chk_has "step 10 never merges a full-lane PR" "$WRAP_MD" "**Wrap never merges a full-lane PR, green or not.**"
chk_has "step 10 says why a full-lane PR waits for the operator" "$WRAP_MD" "its design is the one thing the operator must see before it lands"
chk_has "a spec-validate BLOCK or second NEEDS REVISION stops a full-lane candidate" "$WRAP_MD" "reported: spec-validate BLOCK|NEEDS REVISION: <criticals>"
chk_has "step 10 keeps the own-PR refusal" "$WRAP_MD" "Every refusal above step 10 still holds: never merge a PR the operator did not open, never force-push"
# Step 0's stop protects the main checkout. Two real sessions read "leave that repo alone" as
# "build nothing there" and reported in-lane candidates that a worktree build never touches.
chk_has "step 0 scopes the stop to main-checkout writes" "$WRAP_MD" "STOP every write to that repo's MAIN CHECKOUT"
chk_has "step 0 says the stop covers exactly the checkout writes" "$WRAP_MD" "so it covers exactly the steps that write one of those"
chk_has "step 0 keeps land stopped, with the reason" "$WRAP_MD" "\`bin/wrap land\` (its closing fast-forward pull writes the checkout)"
chk_has "step 0 keeps the pull, stash and pop, and the stray-commits move stopped" "$WRAP_MD" "the stray-commits move of the default branch, the activity line (step 6)"
chk_has "step 0 says the stop does not cover the merge or the own-worktree tidy" "$WRAP_MD" "The stop does NOT cover the merge or the own-worktree tidy"
chk_has "step 0 merges under a stop with merge --apply --no-pull" "$WRAP_MD" "as \`bin/wrap merge --apply --no-pull <repo>\`"
chk_has "step 0 gives the verb's skip line for a PR the main checkout holds" "$WRAP_MD" "\`SKIP #<n>: head <branch> is checked out in the main checkout (--no-pull)\`"
chk_has "step 0 says why a main-held PR is skipped whatever its state" "$WRAP_MD" "merging it at all lands mid-iteration work"
chk_has "step 0 never names a draft with --pr" "$WRAP_MD" "Do not name a draft with \`--pr\`"
chk_no "step 0 dropped the prose-only head-compare protocol" "$WRAP_MD" "branch --show-current"
chk_no "step 0 no longer says a clean PR the main checkout holds still merges" "$WRAP_MD" "still merges when it is clean"
chk_has "step 0 gives the stopped step 5 command" "$WRAP_MD" "\`bin/wrap apply --apply --own <wt>... --no-pull <repo>\` (dry run first)"
chk_has "step 0 says the stopped tidy is --own only" "$WRAP_MD" "The tidy under a stop is \`--own\` only"
chk_has "step 0 names both unscoped SKIP lines" "$WRAP_MD" "\`SKIP worktree sweep: --no-pull needs --own\`, \`SKIP branch sweep: --no-pull needs --own\`"
chk_has "step 0 names both SKIP lines of --no-pull" "$WRAP_MD" "(\`SKIP pull: --no-pull\`, \`SKIP stray commits: --no-pull\`)"
chk_has "step 0 says stray lines are not pushed under a stop" "$WRAP_MD" "\`SKIP stray lines: --no-pull (N lines in <file> stay local)\`, makes no \`wrap/stray-*\` branch"
chk_has "step 0 says a session with no worktree skips the tidy" "$WRAP_MD" "A session that never had a worktree has nothing to name, so it skips the tidy under a stop"
chk_has "step 5 stray-lines bullet names the --no-pull skip" "$WRAP_MD" "Under \`--no-pull\` (a step 0 stop) the carry also pushes nothing"
chk_has "step 0 names the index.lock limit" "$WRAP_MD" "a held \`index.lock\` still makes \`apply\` skip every local removal"
chk_no "step 0 no longer says a build's PR stays OPEN because its merge is a step 3 write" "$WRAP_MD" "because its merge is a step 3 write"
chk_no "the re-check bullet no longer calls steps 3, 5 and 6 the three that write" "$WRAP_MD" "(the three steps that write)"
chk_has "step 3 names the stopped form and that land does not run" "$WRAP_MD" "\`bin/wrap merge --apply --no-pull <repo>\` instead (step 0 says what it skips) and does not run \`bin/wrap land\`"
chk_has "step 3 land bullet carries the stopped exception" "$WRAP_MD" "except in a stopped repo, where \`land\` does not run"
chk_has "step 5 runs the stopped form with --no-pull" "$WRAP_MD" "A stopped repo runs the same order as \`bin/wrap apply --own <wt>... --no-pull <repo>\`"
chk_has "step 5 runs the own EnterWorktree removal under a stop" "$WRAP_MD" "so it runs under a step 0 stop too"
chk_has "step 5 pull-only bullet names its opposite" "$WRAP_MD" "\`--no-pull\` is its opposite and refuses \`--pull-only\`"
chk_has "Left alone reports a skipped pull as PULL BLOCKED, from the closing scan" "$WRAP_MD" "the scan's behind count shows the checkout stayed behind"
chk_has "step 10 landing keeps the merge_own_prs false stop" "$WRAP_MD" "\`wrap.merge_own_prs\` false: stop here; \`Shipped\` lists the PR \`OPEN\`"
chk_has "step 10 landing no longer ends at a foreign-activity stop" "$WRAP_MD" "A foreign-activity stop does not end the landing: step 4 merges with \`--no-pull\` added"
chk_has "step 10 landing merge adds --no-pull when stopped" "$WRAP_MD" "(a stopped repo adds \`--no-pull\`): it merges only an own PR"
chk_has "step 10 landing tidy adds --no-pull when stopped" "$WRAP_MD" "a stopped repo adds \`--no-pull\`"
chk_has "step 0 exempts an isolated-worktree build, with the reason" "$WRAP_MD" "The stop does NOT cover a build in an isolated worktree"
chk_no "step 0 no longer says leave the repo alone for the whole pass" "$WRAP_MD" "leave that repo alone for the rest of the pass"
# pull_past_dirty is the one knob whose shipped default does NOT act: it authorizes a write to
# a dirty file in a checkout other sessions share, so it opts in, and the project fence holds.
v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root wrap.pull_past_dirty true)"
chk "wrap.pull_past_dirty ships as false" "$([ "$v" = "false" ]; echo $?)"
v="$(KIT_CONFIG_OPERATOR="$PD_ON" kit_config_get_root wrap.pull_past_dirty false)"
chk "wrap.pull_past_dirty honours the operator kit.toml" "$([ "$v" = "true" ]; echo $?)"
v="$(KIT_PROJECT_ROOT="$PD_PROJ" kit_config_get_root wrap.pull_past_dirty false)"
chk "wrap.pull_past_dirty ignores a project .kit.toml" "$([ "$v" = "false" ]; echo $?)"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-deploy: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-deploy: all $PASS passed"
