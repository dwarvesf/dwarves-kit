#!/bin/bash
# Standalone proof for SPEC-236 TASK-001: a failing probe round must not
# destroy its own evidence. Runs run.sh twice (rc=7, rc=0) and asserts RUN_OUT
# persists CARD.md and run.sh's own exit code equals the probe's, for both.
# Not part of tier1.sh: needs a working docker/colima, so it SKIPs cleanly
# without one instead of failing tier1's zero-model-cost gate.
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${KIT_ROOT}" || exit 1

if ! docker info >/dev/null 2>&1; then
  echo "SKIP: docker unavailable"
  exit 0
fi

fail=0

run_leg() { # run_leg <name> <probe_cmd> <expected_rc>
  local name="$1" probe_cmd="$2" expected_rc="$3"
  local stage_dir out_dir log rc ok
  # GAUNTLET_STAGE_DIR must live under $HOME: a colima VM only shares $HOME
  # (and a couple of fixed paths), not the default mktemp temp dir, so a
  # /var/folders stage would bind-mount empty into the room (run.sh's own
  # comment on this).
  mkdir -p "${HOME}/.cache/gauntlet-persist-check"
  stage_dir="$(mktemp -d "${HOME}/.cache/gauntlet-persist-check/stage.XXXXXX")"
  out_dir="$(mktemp -d)"
  log="$(mktemp)"

  rc=0
  GAUNTLET_STAGE_DIR="${stage_dir}" RUN_OUT="${out_dir}/room" PROBE_CMD="${probe_cmd}" \
    bash tests/gauntlet/cleanroom/run.sh user >"${log}" 2>&1 || rc=$?

  ok=1
  [ "${rc}" -eq "${expected_rc}" ] || { echo "  ${name}: exit ${rc}, expected ${expected_rc} (see ${log})"; ok=0; }
  [ -f "${out_dir}/room/CARD.md" ] || { echo "  ${name}: CARD.md missing from ${out_dir}/room"; ok=0; }

  if [ "${ok}" -eq 1 ]; then
    echo "PASS  ${name} (exit=${rc}, CARD.md persisted)"
    rm -f "${log}"
  else
    echo "FAIL  ${name} (log kept at ${log})"
    fail=1
  fi
  rm -rf "${stage_dir}" "${out_dir}"
}

echo "== persist-check: RUN_OUT persists on every docker exit code, rc propagates"
run_leg "leg A (PROBE_CMD='exit 7')" "exit 7" 7
run_leg "leg B (PROBE_CMD='exit 0')" "exit 0" 0

echo
if [ "${fail}" -eq 0 ]; then echo "PERSIST-CHECK: GREEN"; else echo "PERSIST-CHECK: RED"; fi
exit "${fail}"
