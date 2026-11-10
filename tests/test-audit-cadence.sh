#!/usr/bin/env bash
# test-audit-cadence.sh -- the audit-loop cadence trigger (bin/audit -> lib/audit/audit.sh).
#
#   1. CENSUS: the `## Cadence` table of docs/patterns/audit-loop.md declares exactly the
#      in-kit audit-loop instances, and every declared row has a real skill directory.
#      Set-equality, same precedent as the bin/ census: a renamed instance must not leave a
#      dead cadence row, and a new instance must not be silently unschedulable.
#   2. PARSE: only the Cadence table feeds the instance set, and every cadence word maps to
#      its period in days.
#   3. DUE: never-run reads as DUE, a fresh marker clears it, an aged marker brings it back.
#   4. PASS STATE: `start` logs a started line; running / abandoned / cleared-by-ran; ran-only
#      logs read as before.
#   5. NC: an undeclared instance is refused and writes no marker; an unknown verb refuses.
#
# Hermetic: KIT_LEDGER_DIR points at a temp dir, so no real ledger is read or written.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$KIT_DIR/bin/audit"

PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
assert_true() { if [ "$2" = "0" ]; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; trap 'rm -rf "$TMP"' EXIT
export KIT_LEDGER_DIR="$TMP/ledger"

echo "== census: the Cadence table is exactly the in-kit instance set =="
EXPECTED="backlog-reconcile ci-drift doc-drift gauntlet-proof-audit memory-tidy repo-hygiene topology-drift web-drift"
ACTUAL="$(bash "$AUDIT" cadences | cut -f1 | sort | tr '\n' ' ' | sed 's/ $//')"
EXPECTED_SORTED="$(printf '%s\n' $EXPECTED | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$ACTUAL" = "$EXPECTED_SORTED" ]; then
  ok "cadence census matches ($ACTUAL)"
else
  bad "cadence census drifted. expected: $EXPECTED_SORTED / actual: $ACTUAL"
fi

echo "== every declared instance has a skill directory =="
missing=""
for i in $(bash "$AUDIT" cadences | cut -f1); do
  [ -f "$KIT_DIR/skills/$i/SKILL.md" ] || missing="$missing $i"
done
assert_true "no cadence row without skills/<name>/SKILL.md ($missing)" "$([ -z "$missing" ]; echo $?)"

echo "== parse: cadence words map to their period in days =="
# Captured once, then matched from a here-string: `audit cadences | grep -q` dies of SIGPIPE
# upstream, and this file runs under pipefail, so the pipeline would report 141 on a MATCH.
CADENCES="$(bash "$AUDIT" cadences)"
assert_true "backlog-reconcile is weekly (7d)" "$(grep -qxF "$(printf 'backlog-reconcile\t7')" <<<"$CADENCES"; echo $?)"
assert_true "memory-tidy is biweekly (14d)" "$(grep -qxF "$(printf 'memory-tidy\t14')" <<<"$CADENCES"; echo $?)"
assert_true "doc-drift is monthly (30d)" "$(grep -qxF "$(printf 'doc-drift\t30')" <<<"$CADENCES"; echo $?)"

echo "== parse NC: a table row outside the Cadence section is not an instance =="
# "Doc drift" and "Backlog reconcile" are row labels in the SDLC-instances table above the
# Cadence section; a looser parser would pick them up as instances with an unknown cadence.
spacey="$(bash "$AUDIT" cadences | cut -f1 | grep -c ' ')"
assert_true "instance names are slugs, not table prose ($spacey with a space)" "$([ "$spacey" = "0" ]; echo $?)"

echo "== due: a never-run instance is DUE =="
out="$(bash "$AUDIT" due)"
assert_true "doc-drift reports never / DUE" "$(echo "$out" | grep -E '^doc-drift .*never .*DUE' >/dev/null; echo $?)"

echo "== due: recording a run clears it =="
bash "$AUDIT" ran doc-drift "test run" >/dev/null
out="$(bash "$AUDIT" due)"
assert_true "doc-drift is no longer DUE" "$(echo "$out" | grep -E '^doc-drift .*0d +-$' >/dev/null; echo $?)"
assert_true "web-drift is still DUE" "$(echo "$out" | grep -E '^web-drift .*DUE' >/dev/null; echo $?)"

echo "== due: an aged marker brings the instance back =="
# 31 days ago: past monthly (30d), so doc-drift is due again. The last matching line wins,
# which is what keeps the stream append-only.
aged=$(( $(date +%s) - 31 * 86400 ))
printf '%s %s %s %s\n' "$aged" "2026-01-01T00:00:00Z" "doc-drift" "aged" >> "$KIT_LEDGER_DIR/audit-runs.log"
out="$(bash "$AUDIT" due)"
assert_true "doc-drift is DUE again at 31d" "$(echo "$out" | grep -E '^doc-drift .*31d +DUE' >/dev/null; echo $?)"

echo "== NC: an undeclared instance is refused and writes no marker =="
before="$(wc -l < "$KIT_LEDGER_DIR/audit-runs.log")"
bash "$AUDIT" ran not-an-instance >/dev/null 2>&1; rc=$?
after="$(wc -l < "$KIT_LEDGER_DIR/audit-runs.log")"
assert_true "audit ran refuses an undeclared instance" "$([ "$rc" != "0" ]; echo $?)"
assert_true "no marker was appended" "$([ "$before" = "$after" ]; echo $?)"

echo "== pass state: old logs (ran lines only) read exactly as before =="
# Snapshot of a ran-only log: the DUE column must stay DUE or "-", never running/abandoned.
out="$(bash "$AUDIT" due)"
assert_true "ran-only log shows no running state" "$(echo "$out" | grep -E 'running|abandoned' >/dev/null; [ $? -ne 0 ]; echo $?)"

echo "== pass state: start records a started line, ran lines stay byte-identical =="
ran_before="$(grep -v ' started$' "$KIT_LEDGER_DIR/audit-runs.log")"
bash "$AUDIT" start web-drift >/dev/null
last="$(tail -n 1 "$KIT_LEDGER_DIR/audit-runs.log")"
assert_true "start appended '<epoch> <iso> web-drift started'" "$(echo "$last" | grep -E '^[0-9]+ [0-9TZ:-]+ web-drift started$' >/dev/null; echo $?)"
ran_after="$(grep -v ' started$' "$KIT_LEDGER_DIR/audit-runs.log")"
assert_true "ran lines unchanged by start" "$([ "$ran_before" = "$ran_after" ]; echo $?)"

echo "== pass state: a fresh started with no ran reads running =="
out="$(bash "$AUDIT" due)"
assert_true "web-drift is running" "$(echo "$out" | grep -E '^web-drift .*never .*running$' >/dev/null; echo $?)"

echo "== pass state: a started older than the timeout reads abandoned =="
old=$(( $(date +%s) - 7 * 3600 ))
printf '%s %s %s %s\n' "$old" "2026-01-01T00:00:00Z" "ci-drift" "started" >> "$KIT_LEDGER_DIR/audit-runs.log"
out="$(bash "$AUDIT" due)"
assert_true "ci-drift is abandoned at 7h" "$(echo "$out" | grep -E '^ci-drift .*abandoned$' >/dev/null; echo $?)"
inside=$(( $(date +%s) - 5 * 3600 ))
printf '%s %s %s %s\n' "$inside" "2026-01-01T00:00:00Z" "backlog-reconcile" "started" >> "$KIT_LEDGER_DIR/audit-runs.log"
out="$(bash "$AUDIT" due)"
assert_true "backlog-reconcile is still running at 5h" "$(echo "$out" | grep -E '^backlog-reconcile .*running$' >/dev/null; echo $?)"

echo "== pass state: a ran after the started clears it =="
sleep 1
bash "$AUDIT" ran web-drift "finished" >/dev/null
bash "$AUDIT" ran ci-drift "finished" >/dev/null
out="$(bash "$AUDIT" due)"
assert_true "web-drift no longer running" "$(echo "$out" | grep -E '^web-drift .*running' >/dev/null; [ $? -ne 0 ]; echo $?)"
assert_true "ci-drift no longer abandoned" "$(echo "$out" | grep -E '^ci-drift .*abandoned' >/dev/null; [ $? -ne 0 ]; echo $?)"
assert_true "ci-drift reads as a normal fresh run" "$(echo "$out" | grep -E '^ci-drift .*0d +-$' >/dev/null; echo $?)"

echo "== pass state: a started older than the last ran does not matter =="
assert_true "doc-drift (ran, no start) unaffected" "$(echo "$out" | grep -E '^doc-drift .*DUE$' >/dev/null; echo $?)"

echo "== NC: start refuses an undeclared instance and writes nothing =="
before="$(wc -l < "$KIT_LEDGER_DIR/audit-runs.log")"
bash "$AUDIT" start not-an-instance >/dev/null 2>&1; rc=$?
after="$(wc -l < "$KIT_LEDGER_DIR/audit-runs.log")"
assert_true "audit start refuses an undeclared instance" "$([ "$rc" != "0" ]; echo $?)"
assert_true "no started line appended" "$([ "$before" = "$after" ]; echo $?)"

echo "== NC: ran refuses the bare note 'started' (it would read as a start) =="
before="$(wc -l < "$KIT_LEDGER_DIR/audit-runs.log")"
msg="$(bash "$AUDIT" ran doc-drift started 2>&1 >/dev/null)"; rc=$?
after="$(wc -l < "$KIT_LEDGER_DIR/audit-runs.log")"
assert_true "ran with note 'started' exits 64" "$([ "$rc" = "64" ]; echo $?)"
assert_true "message is one line naming bin/audit start" "$([ "$(printf '%s\n' "$msg" | wc -l | tr -d ' ')" = "1" ] && echo "$msg" | grep -F 'bin/audit start' >/dev/null; echo $?)"
assert_true "no line appended" "$([ "$before" = "$after" ]; echo $?)"
bash "$AUDIT" ran doc-drift "started the pass, finished" >/dev/null 2>&1; rc=$?
assert_true "a longer note that begins with started is still accepted" "$([ "$rc" = "0" ]; echo $?)"

echo "== NC: an unknown verb refuses =="
bash "$AUDIT" sweep >/dev/null 2>&1; rc=$?
assert_true "audit sweep exits non-zero" "$([ "$rc" != "0" ]; echo $?)"

echo
echo "test-audit-cadence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
