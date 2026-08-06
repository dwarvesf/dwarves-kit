#!/bin/bash
# Run a gauntlet round on the configured runner host (kit.toml [gauntlet]).
#
#   bash tests/gauntlet/cleanroom/run-remote.sh <user|contributor> [ROW] [RUN_OUT]
#
# runner_host = "local"  -> exec run.sh here (interactive unless PROBE_CMD set).
# runner_host = <ssh alias> -> ship COMMITTED state to the host, run the round
# headlessly there, pull the record back to RUN_OUT. The probe key is resolved
# ON the runner host from its own secret store (gauntlet.probe_key_ref); it
# never travels over ssh and never lands in a shell history.
set -euo pipefail

PERSONA="${1:?usage: run-remote.sh <user|contributor> [ROW] [RUN_OUT]}"
ROW="${2:-doorway}"
KIT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${KIT_ROOT}"
OUT="${3:-${KIT_ROOT}/docs/verification/gauntlet/$(date +%Y-%m-%d)-${PERSONA}-${ROW}/room}"

# shellcheck source=lib/config/kit-config.sh
source lib/config/kit-config.sh
HOST="${GAUNTLET_RUNNER_HOST:-$(kit_config_get gauntlet.runner_host local)}"
KEY_REF="$(kit_config_get gauntlet.probe_key_ref "op://Toolkit/anthropic-api-key/credential")"

PROMPT="You are a new contributor. Read /work/CARD.md and follow the repo's own docs. Complete the card. Submit per the docs. Work autonomously; when done or blocked, stop."
PROBE_DEFAULT="timeout 1800 bash -c 'echo \"${PROMPT}\" | claude -p --dangerously-skip-permissions --model claude-sonnet-5 --output-format stream-json --verbose > /work/transcript.jsonl 2>/work/probe-stderr.log'; echo probe-exit=\$?"

if [ "${HOST}" = "local" ]; then
  RUN_OUT="${OUT}" PROBE_CMD="${PROBE_CMD:-${PROBE_DEFAULT}}" \
    exec bash tests/gauntlet/cleanroom/run.sh "${PERSONA}" "${ROW}"
fi

TS="$(date +%s)"
RDIR=".cache/kit-gauntlet/run-${TS}"

echo "== shipping committed state to ${HOST}:${RDIR}"
# shellcheck disable=SC2029  # client-side expansion of RDIR is intentional
git archive HEAD | ssh "${HOST}" "mkdir -p '${RDIR}' && tar -x -C '${RDIR}'"

echo "== running round on ${HOST} (persona=${PERSONA} row=${ROW})"
# The remote driver: bring docker up if needed, resolve the key locally on the
# host, run the round, leave the record in ${RDIR}/out.
DRIVER="$(mktemp)"
trap 'rm -f "${DRIVER}"' EXIT
# The probe command crosses ssh base64-encoded: it nests quotes three deep
# (round-2 finding: a single-quoted export shattered on the prompt's own
# apostrophe and ran the redirect on the HOST instead of in the room).
PROBE_B64="$(printf '%s' "${PROBE_CMD:-${PROBE_DEFAULT}}" | base64 | tr -d '\n')"
cat > "${DRIVER}" <<EOF
set -euo pipefail
cd "${RDIR}"
docker info >/dev/null 2>&1 || colima start --cpu 2 --memory 4
# Cache first (zero 1P calls on a hit). A non-interactive Keychain session
# cannot cache and leaves a 6h suppression marker (round-2 finding), so fall
# back to one direct read per ROUND, never per tick. On a host running 1P
# Connect this costs no service-account quota.
ANTHROPIC_API_KEY="\$(secret-cache-read --ttl 3600 ANTHROPIC_API_KEY ${KEY_REF} 2>/dev/null || true)"
[ -n "\${ANTHROPIC_API_KEY}" ] || ANTHROPIC_API_KEY="\$(op read '${KEY_REF}' 2>/dev/null || true)"
[ -n "\${ANTHROPIC_API_KEY}" ] || { echo "probe key resolved EMPTY on the runner host (cache suppressed AND op read failed; check the host's 1P session)" >&2; exit 65; }
export ANTHROPIC_API_KEY
export RUN_OUT="\$PWD/out"
PROBE_CMD="\$(printf '%s' '${PROBE_B64}' | base64 -d)"
export PROBE_CMD
bash tests/gauntlet/cleanroom/run.sh "${PERSONA}" "${ROW}"
EOF
ssh "${HOST}" bash -s < "${DRIVER}"

echo "== pulling the round record"
mkdir -p "${OUT}"
rsync -a "${HOST}:${RDIR}/out/" "${OUT}/"
echo "record at ${OUT}; remote workdir ${HOST}:${RDIR} left for inspection (sweep old run-* dirs periodically)"
