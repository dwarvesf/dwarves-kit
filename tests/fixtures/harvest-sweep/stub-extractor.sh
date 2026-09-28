#!/bin/bash
# stub-extractor.sh: the sweep extractor stand-in for tests. It never calls a model.
# Reads the prompt on stdin. Driven by env:
#   STUB_MODE    ok (default): print STUB_OUT
#                prose: print STUB_OUT inside a fence with prose around it
#                nonjson: print prose with no JSON object, exit 0
#                fail: print to stderr, exit 1
#                sleep: become `sleep STUB_SLEEP` (exec, so a timeout kill ends it)
#   STUB_OUT     the JSON printed (default {"learnings": [], "sightings": []})
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
OUT="$STUB_OUT"
[ -n "$OUT" ] || OUT='{"learnings": [], "sightings": []}'
case "${STUB_MODE:-ok}" in
  ok) printf '%s\n' "$OUT" ;;
  prose) printf 'Here is the result.\n```json\n%s\n```\nDone {not json}.\n' "$OUT" ;;
  nonjson) echo "I could not find anything worth keeping." ;;
  fail) echo "stub extractor failure" >&2; exit 1 ;;
  sleep) exec sleep "${STUB_SLEEP:-5}" ;;
esac
