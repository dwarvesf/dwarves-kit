#!/bin/bash
# stub-codex.sh: the `codex` stand-in for the sweep's fallback extractor. It never calls a
# model. Installed as `codex` on PATH. Reads the prompt on stdin. Driven by env:
#   CODEX_STUB_MODE   fail (default, so no test reaches a fallback success by accident):
#                     print an error to stderr, exit 1
#                     ok: write CODEX_STUB_OUT to the -o file and stdout
#                     limit: print a usage-limit error to stderr, exit 1
#   CODEX_STUB_OUT    the reply (default {"learnings": [], "sightings": []})
#   CODEX_STUB_CALLS  file: one line appended per call
#   CODEX_STUB_RECORD dir: argv (one element per line), cwd, cwd listing, and prompt
[ -n "$CODEX_STUB_CALLS" ] && echo call >> "$CODEX_STUB_CALLS"
PROMPT="$(cat)"
LAST=""
prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && LAST="$a"
  prev="$a"
done
if [ -n "$CODEX_STUB_RECORD" ]; then
  mkdir -p "$CODEX_STUB_RECORD"
  printf '%s\n' "$@" >| "$CODEX_STUB_RECORD/argv"
  pwd -P >| "$CODEX_STUB_RECORD/cwd"
  ls -A >| "$CODEX_STUB_RECORD/cwd-listing"
  stat -f '%Lp' . 2>/dev/null >| "$CODEX_STUB_RECORD/cwd-mode" || stat -c '%a' . >| "$CODEX_STUB_RECORD/cwd-mode"
  printf '%s' "$PROMPT" >| "$CODEX_STUB_RECORD/prompt"
fi
OUT="${CODEX_STUB_OUT:-}"
[ -n "$OUT" ] || OUT='{"learnings": [], "sightings": []}'
case "${CODEX_STUB_MODE:-fail}" in
  ok) [ -n "$LAST" ] && printf '%s\n' "$OUT" >| "$LAST"; printf 'codex\n%s\n' "$OUT" ;;
  limit) echo "ERROR: You've hit your usage limit." >&2; exit 1 ;;
  *) echo "stub codex failure" >&2; exit 1 ;;
esac
