#!/bin/bash
# Read-only view of a gauntlet room: picks the newest room.* stage dir, shows
# the matching docker ps line if any, then renders transcript.jsonl.
#
#   GAUNTLET_STAGE_DIR=~/.gauntlet-stage bash tests/gauntlet/cleanroom/watch.sh          # follow
#   GAUNTLET_STAGE_DIR=~/.gauntlet-stage bash tests/gauntlet/cleanroom/watch.sh --last    # one-shot
set -euo pipefail

if [ -z "${GAUNTLET_STAGE_DIR:-}" ]; then
  echo "watch.sh: GAUNTLET_STAGE_DIR is not set (the mktemp default stage dir is undiscoverable)." >&2
  echo "Remote-leg rounds stage on the runner host, not here; watch.sh is local-rounds-only." >&2
  exit 64
fi

MODE="${1:---latest}"
KIT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PANE_TAIL_JQ="${KIT_ROOT}/lib/queue/pane-tail.jq"

# shellcheck disable=SC2012  # room.XXXXXX names are mktemp-safe; ls -dt is the mtime sort
ROOM="$(ls -dt "${GAUNTLET_STAGE_DIR%/}"/room.* 2>/dev/null | head -1 || true)"
[ -n "${ROOM}" ] || { echo "watch.sh: no room.* dir under ${GAUNTLET_STAGE_DIR}" >&2; exit 1; }
echo "watch.sh: using ${ROOM}"

docker ps --filter ancestor=kit-gauntlet-room \
  --format 'docker: {{.ID}}  {{.Image}}  {{.Status}}  {{.Names}}' 2>/dev/null || true

TRANSCRIPT="${ROOM}/work/transcript.jsonl"
[ -f "${TRANSCRIPT}" ] || { echo "watch.sh: no transcript yet at ${TRANSCRIPT}" >&2; exit 1; }

# --last renders the whole finished record and returns; anything else follows
# new lines as the round runs.
if [ "${MODE}" = "--last" ]; then
  TAIL_ARGS=(-- "${TRANSCRIPT}")
else
  TAIL_ARGS=(-n 200 -f -- "${TRANSCRIPT}")
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "watch.sh: jq not found, plain tail" >&2
  exec tail "${TAIL_ARGS[@]}"
fi

FIRST_LINE="$(head -n 1 "${TRANSCRIPT}")"

if printf '%s' "${FIRST_LINE}" | grep -qF '"type":"session"' \
  || printf '%s' "${FIRST_LINE}" | grep -qF 'message_start'; then
  # omp v3 session format: pane-tail.jq only understands claude stream-json,
  # so render with a small inline filter over the events that matter.
  tail "${TAIL_ARGS[@]}" | jq -rc --unbuffered '
    if .type == "message_end" then
      .message as $m |
      if ($m.role == "user" or $m.role == "assistant") then
        ($m.content // [])[]? | select(.type == "text") | ($m.role + ": " + .text)
      else empty end
    elif .type == "tool_execution_start" then "-> " + .toolName
    elif .type == "tool_execution_end" and (.isError // false) then "<- ERROR " + .toolName
    else empty end
  '
elif printf '%s' "${FIRST_LINE}" | grep -qF '"type":"assistant"'; then
  tail "${TAIL_ARGS[@]}" | jq -R -r --unbuffered -f "${PANE_TAIL_JQ}"
else
  echo "watch.sh: unrecognized transcript format, plain tail" >&2
  tail "${TAIL_ARGS[@]}"
fi
