#!/usr/bin/env bash
# stub-lane-classify.sh: the annotator's lane-classify.sh stand-in for tests.
# Driven by env:
#   STUB_LANE_RECORD  dir: argv (one element per line) is written to <dir>/argv
#   STUB_LANE         the lane word printed (default normal)
if [ -n "${STUB_LANE_RECORD:-}" ]; then
  mkdir -p "$STUB_LANE_RECORD"
  printf '%s\n' "$@" >| "$STUB_LANE_RECORD/argv"
fi
printf '%s\n' "${STUB_LANE:-normal}"
