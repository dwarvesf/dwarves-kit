#!/usr/bin/env bash
# run-case.sh <hook-cmd...> -- run ONE parity case (JSON on stdin) through a hook command
# and print the observed result as one JSON line: {name, rc, stdout, log, stray}. Shared by
# gen-expected.sh (the Python hook behind its shim) and tests/test-money-gate-parity.sh (the
# bash port), so both sides run a case the same way.
#
# Case fields: name; env (MONEY_GATE_LOG present overrides the harness log path, null means
# unset); payload (a string fed verbatim, or {"gen":"large","bytes":N} for a generated Write
# of N bytes whose content ends in " usd"). Each case gets its own HOME and its own empty
# cwd; `stray` lists every file the hook left in either, other than the log it was told to
# write, so a port that writes a log the Python never wrote shows up.
set -uo pipefail
c=$(cat)
name=$(jq -r .name <<<"$c")
T="$(mktemp -d)"; mkdir -p "$T/home" "$T/cwd"
default_log="$T/case.log"
envs=(); unset_log=0
if [ "$(jq -r '.env | has("MONEY_GATE_LOG")' <<<"$c")" = "true" ]; then
  [ "$(jq -r '.env.MONEY_GATE_LOG == null' <<<"$c")" = "true" ] && unset_log=1
else
  envs+=("MONEY_GATE_LOG=$default_log")
fi
while IFS= read -r kv; do envs+=("$kv"); done < <(jq -r '.env | to_entries[] | select(.value != null) | "\(.key)=\(.value)"' <<<"$c")
if [ "$(jq -r '.payload | type' <<<"$c")" = "object" ]; then
  bytes=$(jq -r .payload.bytes <<<"$c")
  head -c "$bytes" /dev/zero | tr '\0' 'a' > "$T/filler"
  printf '{"tool_input":{"file_path":"/w/fin/big.csv","content":"%s usd"},"cwd":"/w/fin"}' "$(cat "$T/filler")" > "$T/payload"
else
  jq -j .payload <<<"$c" > "$T/payload"
fi
rc=0
out=$(cd "$T/cwd" && env -i PATH="$PATH" HOME="$T/home" "${envs[@]}" "$@" < "$T/payload" 2>/dev/null) || rc=$?
norm=$( [ -n "$out" ] && jq -S -c . <<<"$out" 2>/dev/null || printf '%s' "$out" )
# the log the hook was told to write: the harness default, the case's absolute path, or
# the documented default under HOME when the case unsets it
if [ "$unset_log" = 1 ]; then eff="$T/home/.claude/logs/money-gate.log"
else eff=$(printf '%s\n' "${envs[@]}" | grep '^MONEY_GATE_LOG=' | tail -1 | cut -d= -f2-); fi
logn=""
case "$eff" in /*) [ -f "$eff" ] && logn=$(cut -f2- "$eff") ;; esac
stray=$(cd "$T" && find home cwd -type f 2>/dev/null | while IFS= read -r f; do [ "$T/$f" = "$eff" ] || printf '%s\n' "$f"; done | LC_ALL=C sort | paste -sd, -)
jq -c -n --arg name "$name" --argjson rc "$rc" --arg stdout "$norm" --arg log "$logn" --arg stray "$stray" \
  '{name:$name, rc:$rc, stdout:$stdout, log:$log, stray:$stray}'
