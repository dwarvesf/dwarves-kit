#!/usr/bin/env bash
# negative-controls.sh -- proves each must-have behavior of the Orca backend can fail.
# For every control: break the COMMITTED file, run the case that guards it (expect RED), restore with
# `git checkout -- <file>`, run the case again (expect GREEN). Prints one table row per control.
# Run from the worktree root with the tracked files committed and clean.
#   bash docs/verification/orca-trial/negative-controls.sh [control-id ...]
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT" || exit 2
SUITE=tests/test-orchestrate-orca.sh

[ -z "$(git status --porcelain --untracked-files=no -- lib/queue tests/test-orchestrate-orca.sh)" ] || { echo "refusing: lib/queue or the suite has uncommitted changes" >&2; exit 2; }

# Fields are separated by ~ : id ~ file ~ case ~ description ~ kind ~ pattern ~ replacement.
# kind sed: replace the first match with `s#pattern#replacement#` (BRE, no alternation, BSD and GNU safe).
# kind awk-insert: insert the replacement as a line before the first line matching the ERE pattern.
BK=lib/queue/orca-backend.sh; OR=lib/queue/orchestrate.sh
CONTROLS=$(cat <<'CTL'
default-path~lib/queue/orchestrate.sh~AC1~default path sources the backend~awk-insert~^  case "[$]backend" in$~  _orca_load
exited-parks~lib/queue/orca-backend.sh~AC4~rule 7 loses the exited branch~sed~\[ "\$live" = exited \]~false
no-self-claim~lib/queue/orca-backend.sh~AC8~an open box no longer blocks~sed~^  if \[ "\$checked" != 1 \]; then$~  if false; then
grounded-release~lib/queue/orca-backend.sh~AC6~the shipped worker is not released~sed~^    \[ "\$disp" = "-" \] || _orca worker-release.*$~    :
gate-accept-only~lib/queue/orca-backend.sh~AC7~rework also flips the box~sed~\[ "\$gstat" = resolved \] && \[ "\$gres" = accept \]~[ "$gstat" = resolved ]
rollback-scope~lib/queue/orca-backend.sh~AC9~reset stops an exited Dispatch too~sed~if \[ "\$live" != exited \] && \[ "\$dstat" != stopped \]; then~if true; then
backend-allowlist~lib/queue/orchestrate.sh~AC10~any backend value passes~sed~^    claude|orca) ;;$~    *) ;;
ack-after-acting~lib/queue/orca-backend.sh~AC13~a Delivery is acked before it is acted on~sed~^  if \[ "\$all" = 1 \]; then$~  if true; then
status-no-consume~lib/queue/orca-backend.sh~AC13~status consumes mail~sed~_orca_read "\$dir" 0 || true~_orca_read "$dir" 1 || true
run-lock~lib/queue/orca-backend.sh~AC15~a second runner is allowed~sed~; return 75; }$~; }
version-preflight~lib/queue/orca-backend.sh~AC16~an old Orca passes pre-flight~sed~^  \[ \$((a \* .*$~  true
prior-dispatch~lib/queue/orca-backend.sh~AC3~a Task with a Dispatch is started again~sed~^    \[ -z "\$(_orca_latest_disp "\$task")" \] || continue$~    :
blocked-first~lib/queue/orca-backend.sh~rule-order~BLOCKED no longer beats DONE-UNSEEN~sed~^  if \[ -n "\$bnote" \]; then$~  if false; then
unknown-stays-unknown~lib/queue/orca-backend.sh~AC5~unverifiable liveness reads RUNNING~sed~else _S_STATE=INDETERMINATE; _S_REASON="liveness-.*"$~else _S_STATE=RUNNING
terminal-halt~lib/queue/orca-backend.sh~terminal-halts~unresolvable states no longer halt the run~sed~^    if \[ -n "[$]row" \]; then$~    if false; then
start-guard~lib/queue/orca-backend.sh~start-guard~a recorded start no longer blocks a restart~sed~^    \[ -z "[$](_orca_start_recorded .*$~    :
reset-map-scope~lib/queue/orca-backend.sh~AC9~reset touches rows outside this run's map~sed~select(.taskId as [$]t | any([$]ids\[\]; . == [$]t)) | ~
reset-stop-fail~lib/queue/orca-backend.sh~reset-safety~a failed stop is followed by a release~sed~|| { bad="[$]bad [$]d"; continue; }~|| bad="$bad $d"
reset-lock~lib/queue/orca-backend.sh~reset-safety~reset runs without the run lock~sed~^  _orca_lock_take "[$]1" .*$~  :
occupied-unknown~lib/queue/orca-backend.sh~occupied-unknown~an INDETERMINATE worker frees its slot~sed~^      INDETERMINATE) .*$~      INDETERMINATE) ;;
gate-bang-block~lib/queue/orca-backend.sh~gate-bang~a started gate! sub-goal no longer blocks other starts~sed~DONE|READY|WAITING) ;; \*) return 0 ;;~*) ;;
gate-per-dispatch~lib/queue/orca-backend.sh~gate-per-dispatch~the gate retry key ignores the Dispatch~sed~--retry-request "[$]run-[$]sg-[$]disp-gate"~--retry-request "$run-$sg-accept-gate"
footer-type~lib/queue/orca-backend.sh~footer-type~the footer drops the message type~sed~+ "s (" + ([$]m.type // "unknown") + ")" end~+ "s" end
lock-start~lib/queue/orca-backend.sh~lock-start~a recycled pid is taken for the holder~sed~^  \[ -z "[$]rec" \] .*$~  :
env-validate~lib/queue/orca-backend.sh~env-validate~bad ORCA_* env values pass~sed~^  _orca_preflight_env .*$~  :
backoff~lib/queue/orca-backend.sh~backoff~the error backoff does not wait~sed~wait=[$]((ORCA_POLL_SECS \* (1 << errs)))~wait=0
permission-pin~lib/queue/orca-backend.sh~permission-pin~the permission attestation is not required~sed~\[ "[$]{ORCA_PERMISSION_MODE:-}" = bypass \] || {~true || {
CTL
)

run_cases() { ONLY="$1" bash "$SUITE" 2>&1 | grep -E '^(PASS|FAIL) ' | tr '\n' ' '; }
green_of() { case "$1" in *FAIL*) echo no ;; *PASS*) echo yes ;; *) echo no ;; esac; }

printf '| control | mutation | guarding case | red when broken | green when restored |\n|---|---|---|---|---|\n'
rc=0
while IFS='~' read -r id file cases desc kind pat rep; do
  [ -n "$id" ] || continue
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue ;; esac; fi
  tmp="$(mktemp)"
  if [ "$kind" = sed ]; then sed -e "s#${pat}#${rep}#" "$file" > "$tmp"
  else awk -v pat="$pat" -v ins="$rep" 'BEGIN{done=0} { if (!done && $0 ~ pat) { print ins; done=1 } print }' "$file" > "$tmp"; fi
  if cmp -s "$tmp" "$file"; then echo "| $id | $desc | $cases | MUTATION DID NOT APPLY | - |"; rc=1; git checkout -- "$file"; continue; fi
  cat "$tmp" > "$file"
  bash -n "$file" || { echo "| $id | $desc | $cases | MUTANT DOES NOT PARSE | - |"; rc=1; git checkout -- "$file"; continue; }
  red=$(run_cases "$cases")
  git checkout -- "$file"
  green=$(run_cases "$cases")
  r=no; case "$red" in *FAIL*) r=yes ;; esac
  g=$(green_of "$green")
  [ "$r" = yes ] && [ "$g" = yes ] || rc=1
  echo "| $id | $desc | $cases | $r | $g |"
done <<< "$CONTROLS"
exit "$rc"
