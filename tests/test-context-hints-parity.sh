#!/usr/bin/env bash
# test-context-hints-parity.sh -- hooks/context-hints.sh reproduces the Python context-hints
# on every case in tests/fixtures/context-hints-parity/cases.jsonl. The expected results
# were generated from the Python hook behind its shim (gen-expected.sh) before the bash
# port replaced it: exit code, stdout, stderr, the files left behind, and the state file's
# content after the run. A last check holds the hook to its latency budget.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/context-hints-parity"
HOOK="$KIT_DIR/hooks/context-hints.sh"
# shellcheck source=lib/hook-parity.sh
source "$KIT_DIR/tests/lib/hook-parity.sh"

out=$(hp_check "$FIX/cases.jsonl" "$FIX/expected.jsonl" bash "$HOOK")
rc=$?
printf '%s\n' "$out" | sed 's/^\([0-9]* passed, [0-9]* failed\)$/context-hints parity: \1/'
fail=0; [ "$rc" -eq 0 ] || fail=1

# Latency: the hook timeout is 5 s and a timed-out hook does not fire. A 1 MB prompt against
# a 50-keyword map must stay far inside it (about 0.3 s of CPU on an idle machine).
T="$(mktemp -d)"
jq -n '[range(50) | {key: "keyword\(.)", value: "skill\(.)"}] | from_entries' > "$T/map.json"
head -c 1048576 /dev/zero | tr '\0' 'a' > "$T/filler"
printf '{"prompt":"%s keyword7 here","session_id":"s1"}' "$(cat "$T/filler")" > "$T/payload"
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || date +%s000; }
# CPU time (user plus system), not wall time: the wall clock of a hook on a machine at load average
# 60 is a number about the machine. A quadratic scan costs seconds of CPU on any host.
start=$(now_ms)
cpu=$( { TIMEFORMAT='%U+%S'; time env -i PATH="$PATH" HOME="$T" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 CONTEXT_HINTS_STATE="$T/st" \
  CONTEXT_HINTS_SKILLMAP="$T/map.json" CONTEXT_HINTS_NOW=1 bash "$HOOK" < "$T/payload" > "$T/res" 2>/dev/null; } 2>&1 )
wall=$(( $(now_ms) - start ))
cpu_ms=$(printf '%s' "$cpu" | awk -F+ '{printf "%d", ($1 + $2) * 1000}')
res=$(cat "$T/res")
if [ "$cpu_ms" -lt 3000 ] && [ "$res" = "Maybe-relevant skills: skill7 (keyword: keyword7)" ]; then
  echo "  PASS 1 MB prompt, 50 keywords: ${cpu_ms} ms of CPU (${wall} ms wall)"
else
  fail=1; echo "  FAIL 1 MB prompt: ${cpu_ms} ms of CPU (${wall} ms wall), output: $res"
fi

# jq missing: the hints are off, visibly. A PATH with bash and a few basics but no jq (macOS
# ships /usr/bin/jq, so /usr/bin itself cannot be on it).
B="$(mktemp -d)"
for t in bash env cat dirname readlink mkdir; do p=$(command -v "$t") && ln -s "$p" "$B/$t"; done
err=$(printf '{"prompt":"hi"}' | env -i PATH="$B" HOME="$T" "$B/bash" "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" = 0 ] && [ "$(printf '%s\n' "$err" | grep -c 'jq')" = 1 ]; then
  echo "  PASS jq missing: exit 0, one stderr line"
else
  fail=1; echo "  FAIL jq missing: rc=$rc stderr=$err"
fi

# An unset HOME (launchd, cron) falls back to the password database, as Python's expanduser does,
# and never stops the hook under `set -u`.
H="$(mktemp -d)"
err=$(printf '{"prompt":"hi","session_id":"homeless"}' | env -i PATH="$PATH" CONTEXT_HINTS_TEMPORAL=0 bash "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" = 0 ] && [ -z "$err" ]; then
  echo "  PASS unset HOME: exit 0, no error"
else
  fail=1; echo "  FAIL unset HOME: rc=$rc stderr=$err"
fi

# No interpreter beyond bash and jq: the hook never names python.
if [ "$(grep -c 'python' "$HOOK")" = 0 ]; then
  echo "  PASS hook names no python"
else
  fail=1; echo "  FAIL hook mentions python"
fi

# A symlinked hook still finds the map that sits beside the real file.
K="$(mktemp -d)"; L="$(mktemp -d)"
cp "$HOOK" "$K/context-hints.sh"; printf '{"keyword":"linked-skill"}' > "$K/context-hints-skills-map.json"
ln -s "$K/context-hints.sh" "$L/context-hints.sh"
res=$(printf '{"prompt":"hi keyword","session_id":"s1"}' | env -i PATH="$PATH" HOME="$T" CONTEXT_HINTS_STATE="$T/st2" CONTEXT_HINTS_TEMPORAL=0 bash "$L/context-hints.sh")
if [ "$res" = "Maybe-relevant skills: linked-skill (keyword: keyword)" ]; then
  echo "  PASS symlinked hook reads the map beside the real file"
else
  fail=1; echo "  FAIL symlinked hook output: $res"
fi
[ "$fail" -eq 0 ]
