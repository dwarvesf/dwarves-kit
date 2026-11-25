#!/usr/bin/env bash
# Run one round of the team-stamp gauntlet, or stage it.
#
#   ANTHROPIC_API_KEY=<capped key> RUN_OUT=<new dir> bash tests/gauntlet/team-stamp/run.sh
#   GAUNTLET_STAGE_ONLY=1 bash tests/gauntlet/team-stamp/run.sh        stage everything, print the paths, stop
#
# NOT EXECUTED ON THE BUILD HOST. No container runtime ran on the machine this was written on, so
# everything from `docker build` down is unverified code until the operator's first run. Tier 1
# (tier1.sh) covers the staging, the checker and copy-out.sh on the host; nothing else here does.
#
# The rule: nothing a probe wrote is ever read, written, listed or executed by a host process, except
# the fixed list of result files copy-out.sh copies out of the checker's output directory.
# The host does only this:
#   1. makes its own directories with mktemp -d, and stages a stamped scratch repo, a pristine stamp
#      and the checker script on the host (all host-written);
#   2. builds the image and creates a named volume (never a bind mount) for the probe's work area;
#   3. seeds the volume from the host-written seed, then runs the probe container: the volume, the
#      one key, nothing else;
#   4. runs a SECOND throwaway container, the checker, from the same image with NO key and no
#      network: the probe's volume read-only, the checker and the pristine stamp read-only from the
#      host-written directories, and one fresh host-made output directory, writable;
#   5. copies the six named result files out of the output directory (copy-out.sh), scrubs the key
#      from the copies without -I, and removes the volume.
# A hostile probe repository can at worst forge its own verdict inside the checker container, which
# the run record states as a limit. Exit 69 when no container runtime answers, 64 when the key or the
# record dir is missing, 70 when the key scrub fails.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=tests/gauntlet/team-stamp/copy-out.sh
source "$HERE/copy-out.sh"
IMAGE="team-stamp-gauntlet-room"

STAGE="$(mktemp -d "${GAUNTLET_STAGE_DIR:-${TMPDIR:-/tmp}}/team-stamp-room.XXXXXX")"
SEED="$STAGE/seed"
CHECKER="$STAGE/checker"
PRISTINE="$STAGE/pristine"
OUT="$STAGE/out"
mkdir -p "$SEED/bin" "$SEED/submission" "$CHECKER" "$PRISTINE" "$OUT"

# the probe's starting repository: stamped, committed, exported, given a fresh history
SCRATCH="$STAGE/scratch"
mkdir -p "$SCRATCH"
git -C "$SCRATCH" init -q -b main
git -C "$SCRATCH" config user.name stamp
git -C "$SCRATCH" config user.email stamp@example.invalid
bash "$KIT_ROOT/lib/stamp.sh" --default-branch main --owner probe "$SCRATCH" >/dev/null
git -C "$SCRATCH" add -A
git -C "$SCRATCH" commit -q -m "chore: stamp the harness"
mkdir -p "$SEED/repo"
git -C "$SCRATCH" archive HEAD | tar -x -C "$SEED/repo"
git -C "$SEED/repo" init -q -b main
git -C "$SEED/repo" config user.name probe
git -C "$SEED/repo" config user.email probe@example.invalid
git -C "$SEED/repo" add -A
git -C "$SEED/repo" commit -q -m "chore: stamp the harness"
git -C "$SEED/repo" update-ref refs/remotes/origin/main HEAD
git -C "$SEED/repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# the base is known here, before the probe runs, and passed to the checker; it is never read back
BASE_SHA="$(git -C "$SEED/repo" rev-parse HEAD)"

cp "$HERE/gh-shim.sh" "$SEED/bin/gh"
chmod +x "$SEED/bin/gh"
cp "$HERE/card.md" "$SEED/CARD.md"
cat >"$SEED/PROMPT.md" <<'EOP'
You are a teammate's coding agent. Read only this repository's files. Complete the card in
/work/CARD.md and submit per the repository's own rules. The repository is /work/repo. Do not ask
questions.
EOP

# the checker's own files and the pristine stamp, written by the host
cp "$HERE/check-submission.sh" "$CHECKER/check-submission.sh"
git -C "$PRISTINE" init -q -b main
bash "$KIT_ROOT/lib/stamp.sh" --default-branch main --owner probe "$PRISTINE" >/dev/null
git -C "$PRISTINE" add -A

if [ "${GAUNTLET_STAGE_ONLY:-0}" = 1 ]; then
  echo "STAGE=$STAGE"
  echo "BASE=$BASE_SHA"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "run.sh: no container runtime answers (docker info failed); the paid probe cannot run here" >&2
  exit 69
fi
[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "run.sh: set ANTHROPIC_API_KEY to a spend-capped probe key" >&2; exit 64; }
[ -n "${RUN_OUT:-}" ] && [ ! -L "$RUN_OUT" ] || { echo "run.sh: set RUN_OUT to a new directory (not a symlink) for the run record" >&2; exit 64; }
mkdir -p "$RUN_OUT"
[ -d "$RUN_OUT" ] && [ ! -L "$RUN_OUT" ] || { echo "run.sh: RUN_OUT is not a plain directory" >&2; exit 64; }

VOL="team-stamp-room-$(basename "$STAGE" | tr -c 'A-Za-z0-9' '-')"
cleanup() { docker volume rm -f "$VOL" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker build -q -t "$IMAGE" -f "$HERE/Dockerfile" "$HERE" >/dev/null
docker volume create "$VOL" >/dev/null
# seed the volume from the host-written seed (read-only mount)
docker run --rm -v "$VOL:/work" -v "$SEED:/seed:ro" "$IMAGE" bash -c 'cp -a /seed/. /work/'

# the probe: the volume and the one key
rc=0
docker run --rm \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e GH_SHIM_DIR=/work/submission -e GH_SHIM_REPO=/work/repo \
  -e PATH=/work/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$VOL:/work" -w /work/repo \
  "$IMAGE" \
  bash -c 'claude -p "$(cat /work/PROMPT.md)" --output-format stream-json --verbose --permission-mode bypassPermissions >/work/transcript.jsonl 2>/work/probe-stderr' \
  || rc=$?

# the checker: no key, no network, the probe's volume read-only, one writable output dir
crc=0
docker run --rm --network none \
  -v "$VOL:/probe:ro" \
  -v "$CHECKER:/checker:ro" \
  -v "$PRISTINE:/pristine:ro" \
  -v "$OUT:/out" \
  -e CHECKER_OUT=/out -e PRISTINE_DIR=/pristine \
  "$IMAGE" \
  bash -c 'bash /checker/check-submission.sh /probe/repo /probe/submission "$0" /probe/transcript.jsonl >/out/checker-output.txt 2>&1' "$BASE_SHA" \
  || crc=$?

copy_results "$OUT" "$RUN_OUT" || true
if ! scrub_dir "$RUN_OUT" "$ANTHROPIC_API_KEY"; then
  echo "SCRUB FAILED: the key is still in the run record; removing the copied files" >&2
  for n in $RESULT_NAMES; do rm -f -- "${RUN_OUT:?}/$n"; done
  exit 70
fi
verdict="$(head -c 16 "$RUN_OUT/verdict.txt" 2>/dev/null | head -n 1 || true)"
echo "verdict: ${verdict:-none} (the container's own word; a hostile repository can forge it, read the checker output)"
echo "run record persisted to $RUN_OUT; rotate or revoke the probe key now"
[ "$verdict" = PASS ] && [ "$rc" -eq 0 ] && [ "$crc" -eq 0 ]
