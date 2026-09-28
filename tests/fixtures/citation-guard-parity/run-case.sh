#!/usr/bin/env bash
# run-case.sh <hook-cmd...> -- run ONE parity case (JSON on stdin) through a hook command
# and print the observed result as one JSON line: {name, rc, stderr, log}. Shared by
# gen-expected.sh (Python hook) and tests/test-citation-guard-parity.sh (bash hook), so
# both sides run the case the same way. "ROOT" in the case expands to the fixture root.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/root"
c=$(cat)
name=$(jq -r .name <<<"$c")
TMP="$(mktemp -d)"; mkdir -p "$TMP/home"
log="$TMP/cg.log"
envs=(); unset_log=0
if [ "$(jq -r '.env | has("CITATION_GUARD_LOG")' <<<"$c")" = "true" ]; then
  [ "$(jq -r '.env.CITATION_GUARD_LOG == null' <<<"$c")" = "true" ] && unset_log=1
else
  envs+=("CITATION_GUARD_LOG=$log")
fi
# ROOT expands in the VALUE only: substituting across the whole KEY=VALUE also rewrote
# CITATION_GUARD_ROOT's own name, and the mangled variable never reached the hook
while IFS= read -r kv; do k=${kv%%=*}; v=${kv#*=}; envs+=("$k=${v//ROOT/$ROOT}"); done < <(jq -r '.env | to_entries[] | select(.value != null) | "\(.key)=\(.value)"' <<<"$c")
if [ "$(jq -r '.payload | type' <<<"$c")" = "string" ]; then
  payload=$(jq -r '.payload' <<<"$c"); payload=${payload#RAW:}
else
  payload=$(jq -c --arg root "$ROOT" --arg here "$HERE" '.payload
    | (if .cwd == "ROOT" then .cwd = $root else . end)
    | (if .transcript_path then .transcript_path = ($here + "/" + .transcript_path) else . end)' <<<"$c")
fi
before=$(cd "$ROOT" && find . -type f | LC_ALL=C sort)
rc=0
# a UTF-8 locale, as Claude Code passes the user's: a hook whose awk or tr is locale-
# sensitive must pin LC_ALL=C itself (macOS awk dies on a non-ASCII byte under UTF-8)
err=$(cd "$ROOT" && printf '%s' "$payload" | env -i PATH="$PATH" HOME="$TMP/home" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 ${envs[@]+"${envs[@]}"} "$@" 2>&1 >"$TMP/stdout") || rc=$?
out=$(cat "$TMP/stdout")
# the log the hook was told to write: the harness default, the case's absolute path, or
# the documented default under HOME when the case unsets it
if [ "$unset_log" = 1 ]; then eff="$TMP/home/.claude/dwarves-kit/logs/citation-guard.log"
else eff=$(printf '%s\n' "${envs[@]}" | grep '^CITATION_GUARD_LOG=' | tail -1 | cut -d= -f2-); fi
logn=""
case "$eff" in /*) if [ -f "$eff" ]; then
  logn=$(cut -f2- "$eff")
  cut -f1 "$eff" | grep -qv '^[0-9][0-9]*$' && logn="BAD-EPOCH $logn"
fi ;; esac
after=$(cd "$ROOT" && find . -type f | LC_ALL=C sort)
stray=$( { comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's|^\./|root/|'
           (cd "$TMP" && find home -type f) | while IFS= read -r f; do [ "$TMP/$f" = "$eff" ] || printf '%s\n' "$f"; done
         } | grep -v '^$' | LC_ALL=C sort | paste -sd, - )
# absolute fixture paths vary by checkout: fold them back to ROOT/HERE
err=${err//$ROOT/ROOT}; logn=${logn//$ROOT/ROOT}
jq -c -n --arg name "$name" --argjson rc "$rc" --arg stdout "$out" --arg stderr "$err" --arg log "$logn" --arg stray "$stray" \
  '{name:$name, rc:$rc, stdout:$stdout, stderr:$stderr, log:$log, stray:$stray}'
