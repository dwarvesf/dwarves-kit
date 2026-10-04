#!/usr/bin/env bash
# stub-precedent.sh: the annotator's bin/precedent stand-in for tests. It never
# reads a real inventory. Driven by env:
#   STUB_PRECEDENT_RECORD     dir: argv (one element per line) is written to <dir>/argv
#   STUB_PRECEDENT_HITS_FILE  file holding a JSON array of hit strings; its contents
#                             are embedded verbatim under one "inventory" section
#   STUB_PRECEDENT_MODE       hits (default): use the file; none: report no hits
if [ -n "${STUB_PRECEDENT_RECORD:-}" ]; then
  mkdir -p "$STUB_PRECEDENT_RECORD"
  printf '%s\n' "$@" >| "$STUB_PRECEDENT_RECORD/argv"
fi
hits='[]'
[ "${STUB_PRECEDENT_MODE:-hits}" = "none" ] || \
  hits="$(cat "${STUB_PRECEDENT_HITS_FILE:-/dev/null}" 2>/dev/null || printf '[]')"
[ -n "$hits" ] || hits='[]'
printf '{"data_marker":"stub","inventory":{"hits":%s},"total_hits":0,"sections_with_hits":0,"nothing_matched":false}\n' "$hits"
