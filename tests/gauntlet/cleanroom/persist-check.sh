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

# Leg C: the automated key scrub. A probe that echoes the room key into /work
# must persist as <REDACTED-KEY>, never the literal value.
leg_c() {
  local stage_dir out_dir log rc ok=1
  stage_dir="$(mktemp -d "${HOME}/.cache/gauntlet-persist-check/stage.XXXXXX")"
  out_dir="$(mktemp -d "${HOME}/.cache/gauntlet-persist-check/out.XXXXXX")"
  log="$(mktemp "${HOME}/.cache/gauntlet-persist-check/log.XXXXXX")"
  rc=0
  ANTHROPIC_API_KEY="dummy-scrub-canary-0451" \
    GAUNTLET_STAGE_DIR="${stage_dir}" RUN_OUT="${out_dir}/room" \
    PROBE_CMD='echo "$ANTHROPIC_API_KEY" > /work/leak.txt; exit 0' \
    bash tests/gauntlet/cleanroom/run.sh user > "${log}" 2>&1 || rc=$?
  [ "${rc}" -eq 0 ] || { echo "  leg C: exit ${rc}, expected 0 (see ${log})"; ok=0; }
  if grep -rqF "dummy-scrub-canary-0451" "${out_dir}" 2>/dev/null; then
    echo "  leg C: literal key survived into the persisted room"; ok=0
  fi
  grep -qF "<REDACTED-KEY>" "${out_dir}/room/leak.txt" 2>/dev/null \
    || { echo "  leg C: redaction marker missing from leak.txt"; ok=0; }
  if [ "${ok}" -eq 1 ]; then echo "PASS  leg C (key scrubbed to <REDACTED-KEY>)"; rm -f "${log}"; else echo "FAIL  leg C (log kept at ${log})"; fail=1; fi
  rm -rf "${stage_dir}" "${out_dir}"
}
leg_c

# Leg D: key SET but the room is CLEAN (no occurrence anywhere). The scrub's
# no-match path must not kill the persist (the 2026-09-01 campaign regression:
# grep|while under pipefail exited 1 and run.sh died before RUN_OUT).
leg_d() {
  local stage_dir out_dir log rc ok=1
  stage_dir="$(mktemp -d "${HOME}/.cache/gauntlet-persist-check/stage.XXXXXX")"
  out_dir="$(mktemp -d "${HOME}/.cache/gauntlet-persist-check/out.XXXXXX")"
  log="$(mktemp "${HOME}/.cache/gauntlet-persist-check/log.XXXXXX")"
  rc=0
  ANTHROPIC_API_KEY="dummy-clean-room-canary" \
    GAUNTLET_STAGE_DIR="${stage_dir}" RUN_OUT="${out_dir}/room" \
    PROBE_CMD='exit 0' \
    bash tests/gauntlet/cleanroom/run.sh user > "${log}" 2>&1 || rc=$?
  [ "${rc}" -eq 0 ] || { echo "  leg D: exit ${rc}, expected 0 (see ${log})"; ok=0; }
  [ -f "${out_dir}/room/CARD.md" ] || { echo "  leg D: CARD.md missing, clean-room scrub killed the persist"; ok=0; }
  if [ "${ok}" -eq 1 ]; then echo "PASS  leg D (clean room persists with key set)"; rm -f "${log}"; else echo "FAIL  leg D (log kept at ${log})"; fail=1; fi
  rm -rf "${stage_dir}" "${out_dir}"
}
leg_d

echo
if [ "${fail}" -eq 0 ]; then echo "PERSIST-CHECK: GREEN"; else echo "PERSIST-CHECK: RED"; fi
exit "${fail}"
