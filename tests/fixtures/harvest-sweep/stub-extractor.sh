#!/bin/bash
# stub-extractor.sh: the sweep extractor stand-in for tests. It never calls a model.
# Reads the prompt on stdin. Driven by env:
#   STUB_MODE    ok (default): print STUB_OUT
#                prose: print STUB_OUT inside a fence with prose around it
#                nonjson: print prose with no JSON object, exit 0
#                fail: print STUB_ERR to stderr, exit 1
#                limit: print STUB_ERR (default a limit message) to stderr, exit 1
#                sleep: become `sleep STUB_SLEEP` (exec, so a timeout kill ends it)
#   STUB_OUT     the JSON printed (default {"learnings": [], "sightings": []})
#   STUB_ERR     the stderr text for fail and limit (defaults per mode)
#   STUB_FAIL_MATCH  when set, a prompt containing this string fails instead
#   STUB_CALLS   file: one line appended per call
#   STUB_RECORD  dir: argv (one element per line), cwd, the HARVEST_SWEEP_CHILD value,
#                and the prompt are written there
# Installed as `claude` on PATH, it also stands in for the default command.
[ -n "$STUB_CALLS" ] && echo call >> "$STUB_CALLS"
PROMPT="$(cat)"
if [ -n "$STUB_RECORD" ]; then
  mkdir -p "$STUB_RECORD"
  printf '%s\n' "$@" >| "$STUB_RECORD/argv"
  pwd -P >| "$STUB_RECORD/cwd"
  printf '%s\n' "${HARVEST_SWEEP_CHILD-unset}" >| "$STUB_RECORD/child"
  printf '%s' "$PROMPT" >| "$STUB_RECORD/prompt"
fi
if [ -n "${STUB_FAIL_MATCH:-}" ]; then
  case "$PROMPT" in *"$STUB_FAIL_MATCH"*) echo "${STUB_ERR:-stub extractor failure}" >&2; exit 1 ;; esac
fi
OUT="$STUB_OUT"
[ -n "$OUT" ] || OUT='{"learnings": [], "sightings": []}'
case "${STUB_MODE:-ok}" in
  ok) printf '%s\n' "$OUT" ;;
  prose) printf 'Here is the result.\n```json\n%s\n```\nDone {not json}.\n' "$OUT" ;;
  nonjson) echo "I could not find anything worth keeping." ;;
  fail) echo "${STUB_ERR:-stub extractor failure}" >&2; exit 1 ;;
  limit) echo "${STUB_ERR:-usage limit reached}" >&2; exit 1 ;;
  sleep) exec sleep "${STUB_SLEEP:-5}" ;;
esac
