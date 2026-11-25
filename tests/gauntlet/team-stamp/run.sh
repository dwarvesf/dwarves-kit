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
# Exit 69 when no container runtime answers, 64 when the key is missing, 70 when the key scrub fails.
#
# The probe's repository is UNTRUSTED (a model wrote into it, .git/config included). It is never
# opened on this host: a git bundle is made INSIDE the container, and check-submission.sh clones the
# bundle into a directory it creates itself. Only named text outputs are persisted, never the
# probe's .git. After a campaign the operator rotates or revokes the probe key.
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
git -C "$SCRATCH" config user.email stamp@example.invalid
bash "$KIT_ROOT/lib/stamp.sh" --default-branch main --owner probe "$SCRATCH" >/dev/null
git -C "$SCRATCH" add -A
git -C "$SCRATCH" commit -q -m "chore: stamp the harness"
mkdir -p "$WORK/repo"
git -C "$SCRATCH" archive HEAD | tar -x -C "$WORK/repo"
git -C "$WORK/repo" init -q -b main
git -C "$WORK/repo" config user.name probe
git -C "$WORK/repo" config user.email probe@example.invalid
git -C "$WORK/repo" add -A
git -C "$WORK/repo" commit -q -m "chore: stamp the harness"
git -C "$WORK/repo" update-ref refs/remotes/origin/main HEAD
git -C "$WORK/repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# the base is known here, before the probe runs, and passed to the checker; it is never read back
BASE_SHA="$(git -C "$WORK/repo" rev-parse HEAD)"

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
  echo "BASE=$BASE_SHA"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "run.sh: no container runtime answers (docker info failed); the paid probe cannot run here" >&2
  exit 69
fi
[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "run.sh: set ANTHROPIC_API_KEY to a spend-capped probe key" >&2; exit 64; }

docker build -q -t team-stamp-gauntlet-room -f "$HERE/Dockerfile" "$HERE" >/dev/null
rc=0
# One container: the probe runs, then the bundle is made there, so any hook or config the probe
# planted in /work/repo/.git runs inside the room and nowhere else.
docker run --rm \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e GH_SHIM_DIR=/work/submission -e GH_SHIM_REPO=/work/repo \
  -e PATH=/work/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$WORK:/work" -w /work/repo \
  team-stamp-gauntlet-room \
  bash -c 'claude -p "$(cat /work/PROMPT.md)" --output-format stream-json --verbose --permission-mode bypassPermissions >/work/transcript.jsonl 2>/work/probe-stderr; rc=$?; git -C /work/repo bundle create /work/submission/repo.bundle --all >/dev/null 2>&1; exit $rc' \
  || rc=$?

# The scrub. The room's output is untrusted text and may be binary; scan every file (no -I), redact
# a text file, delete a binary one that holds the key, then scan again and refuse to go on if the key
# is still anywhere in the staged outputs.
scrub() {
  local f c
  while IFS= read -r f; do
    if grep -qI . "$f" 2>/dev/null; then
      c="$(cat "$f")"
      printf '%s\n' "${c//"$ANTHROPIC_API_KEY"/<REDACTED-KEY>}" >"$f"
    else
      echo "scrub: deleted a binary file that held the key: ${f#"$WORK"/}" >&2
      rm -f -- "$f"
    fi
  done < <(grep -rlF -- "$ANTHROPIC_API_KEY" "$WORK" 2>/dev/null || true)
}
scrub
if grep -rqF -- "$ANTHROPIC_API_KEY" "$WORK" 2>/dev/null; then
  echo "SCRUB FAILED: the key is still present after redaction; refusing to go on" >&2
  exit 70
fi

echo "== checker"
set +e
bash "$HERE/check-submission.sh" "$WORK/submission/repo.bundle" "$WORK/submission" "$BASE_SHA" "$WORK/transcript.jsonl" | tee "$WORK/submission/checker-output.txt"
checker_rc="${PIPESTATUS[0]}"
set -e
if [ -n "${RUN_OUT:-}" ]; then
  # only named text outputs: never the probe's .git, never the bundle
  mkdir -p "$RUN_OUT/submission"
  for f in CARD.md PROMPT.md transcript.jsonl probe-stderr submission/pr.json submission/calls.jsonl submission/clean-diff.patch submission/checker-output.txt; do
    [ -f "$WORK/$f" ] && cp "$WORK/$f" "$RUN_OUT/$f"
  done
  if grep -rqF -- "$ANTHROPIC_API_KEY" "$RUN_OUT" 2>/dev/null; then
    echo "SCRUB FAILED: the key is in the persisted record; removing it" >&2
    rm -rf "${RUN_OUT:?}/submission" "${RUN_OUT:?}/transcript.jsonl" "${RUN_OUT:?}/probe-stderr"
    exit 70
  fi
  echo "run record persisted to $RUN_OUT (rotate or revoke the probe key now)"
fi
echo "stage kept at $STAGE (it holds the probe's repository: never open it, never run anything in it)"
[ "$checker_rc" -eq 0 ] && exit "$rc"
exit "$checker_rc"
