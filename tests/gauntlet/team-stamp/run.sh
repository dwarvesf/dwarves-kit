#!/usr/bin/env bash
# Build and enter the team-stamp gauntlet clean room.
#
#   ANTHROPIC_API_KEY=<capped key> bash tests/gauntlet/team-stamp/run.sh        run one probe round
#   GAUNTLET_STAGE_ONLY=1 bash tests/gauntlet/team-stamp/run.sh                 stage the room, print its path, stop
#
# Stage: a scratch repo is stamped from the working tree (lib/stamp.sh), committed, and exported with
# `git archive HEAD`; the archive is extracted into /work/repo and given a fresh history. Nothing
# else of the kit enters the room: no lib/, no tests/gauntlet/, no install, no run records (rule 7).
# The probe key is the ONLY credential, passed at run time and never baked. RUN_OUT=<dir> persists
# the room's contents after the round; the key is redacted from them first.
# Exit 69 when no container runtime answers, 64 when the key is missing.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
STAGE="$(mktemp -d "${GAUNTLET_STAGE_DIR:-${TMPDIR:-/tmp}}/team-stamp-room.XXXXXX")"
WORK="$STAGE/work"
mkdir -p "$WORK/bin" "$WORK/submission" "$WORK/checks"

# the scratch repo: stamped, committed, exported
SCRATCH="$STAGE/scratch"
mkdir -p "$SCRATCH"
git -C "$SCRATCH" init -q -b main
git -C "$SCRATCH" config user.name stamp
git -C "$SCRATCH" config user.email stamp@gauntlet.invalid
bash "$KIT_ROOT/lib/stamp.sh" --default-branch main --owner probe "$SCRATCH" >/dev/null
git -C "$SCRATCH" add -A
git -C "$SCRATCH" commit -q -m "chore: stamp the harness"
mkdir -p "$WORK/repo"
git -C "$SCRATCH" archive HEAD | tar -x -C "$WORK/repo"
git -C "$WORK/repo" init -q -b main
git -C "$WORK/repo" config user.name probe
git -C "$WORK/repo" config user.email probe@gauntlet.invalid
git -C "$WORK/repo" add -A
git -C "$WORK/repo" commit -q -m "chore: stamp the harness"
git -C "$WORK/repo" update-ref refs/remotes/origin/main HEAD
git -C "$WORK/repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

cp "$HERE/gh-shim.sh" "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
cp "$HERE/card.md" "$WORK/CARD.md"
cp "$HERE/check-submission.sh" "$WORK/checks/check-submission.sh"
cat >"$WORK/PROMPT.md" <<'EOP'
You are a teammate's coding agent. Read only this repository's files. Complete the card in
/work/CARD.md and submit per the repository's own rules. The repository is /work/repo. Do not ask
questions.
EOP

if [ "${GAUNTLET_STAGE_ONLY:-0}" = 1 ]; then
  echo "STAGE=$STAGE"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "run.sh: no container runtime answers (docker info failed); the paid probe cannot run here" >&2
  exit 69
fi
[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "run.sh: set ANTHROPIC_API_KEY to a spend-capped probe key" >&2; exit 64; }

docker build -q -t team-stamp-gauntlet-room -f "$HERE/Dockerfile" "$HERE" >/dev/null
rc=0
docker run --rm \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e GH_SHIM_DIR=/work/submission -e GH_SHIM_REPO=/work/repo \
  -e PATH=/work/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$WORK:/work" -w /work/repo \
  team-stamp-gauntlet-room \
  claude -p "$(cat "$WORK/PROMPT.md")" --output-format stream-json --verbose --permission-mode bypassPermissions \
  >"$WORK/transcript.jsonl" 2>"$WORK/probe-stderr" || rc=$?

# the key never leaves the stage: redact any literal copy before anything is persisted
while IFS= read -r f; do
  c="$(cat "$f")"
  printf '%s\n' "${c//"$ANTHROPIC_API_KEY"/<REDACTED-KEY>}" >"$f"
done < <(grep -rlIF "$ANTHROPIC_API_KEY" "$WORK" 2>/dev/null || true)
if grep -rqIF "$ANTHROPIC_API_KEY" "$WORK" 2>/dev/null; then
  echo "SCRUB FAILED: the key is still present; refusing to persist the room" >&2
  exit 70
fi

echo "== checker"
checker_rc=0
bash "$HERE/check-submission.sh" "$WORK/repo" "$WORK/submission" "$WORK/transcript.jsonl" || checker_rc=$?
if [ -n "${RUN_OUT:-}" ]; then
  mkdir -p "$RUN_OUT"
  cp -R "$WORK/." "$RUN_OUT/"
  find "$RUN_OUT" -type l -delete 2>/dev/null || true
  echo "room contents persisted to $RUN_OUT"
fi
echo "stage kept at $STAGE"
[ "$checker_rc" -eq 0 ] && exit "$rc"
exit "$checker_rc"
