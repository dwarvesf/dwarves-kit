#!/bin/bash
# Build and enter the kit gauntlet clean room.
#
#   bash tests/gauntlet/cleanroom/run.sh user          # stage persona A, drop to a shell
#   bash tests/gauntlet/cleanroom/run.sh contributor   # stage persona B, drop to a shell
#
# The probe key is passed at run time, never baked:
#   ANTHROPIC_API_KEY=<capped key> bash tests/gauntlet/cleanroom/run.sh user
set -euo pipefail

PERSONA="${1:?usage: run.sh <user|contributor>}"
KIT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${KIT_ROOT}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/work/checks"

# The kit as a tarball of COMMITTED state, minus the answer key (rule 7):
# the gauntlet dir and any prior run records never enter the room.
mkdir -p "${STAGE}/kit-src"
git archive HEAD | tar -x -C "${STAGE}/kit-src"
rm -rf "${STAGE}/kit-src/tests/gauntlet" "${STAGE}/kit-src/docs/verification/gauntlet"
tar -czf "${STAGE}/work/kit.tar.gz" -C "${STAGE}/kit-src" .

# Persona staging.
case "${PERSONA}" in
  user)
    # Fixture: a tiny Node CLI whose README example uses the wrong flag.
    FIX="${STAGE}/work/fixture-repo"
    mkdir -p "${FIX}"
    cat > "${FIX}/cli.js" <<'EOF'
#!/usr/bin/env node
const arg = process.argv[2];
if (arg === "--upper") console.log((process.argv[3] || "").toUpperCase());
else { console.error("usage: cli.js --upper <text>"); process.exit(1); }
EOF
    cat > "${FIX}/README.md" <<'EOF'
# shout

Tiny demo CLI.

## Usage

    node cli.js --uppercase hello   # prints HELLO
EOF
    cat > "${FIX}/package.json" <<'EOF'
{ "name": "shout", "version": "1.0.0", "bin": { "shout": "./cli.js" } }
EOF
    git -C "${FIX}" init -q && git -C "${FIX}" add -A && git -C "${FIX}" commit -qm "chore: fixture seed"
    cp tests/gauntlet/seed-card-user.md "${STAGE}/work/CARD.md"
    cp tests/gauntlet/check-submission-user.sh "${STAGE}/work/checks/"
    ;;
  contributor)
    git clone -q --no-hardlinks . "${STAGE}/work/kit"
    rm -rf "${STAGE}/work/kit/tests/gauntlet" "${STAGE}/work/kit/docs/verification/gauntlet"
    git -C "${STAGE}/work/kit" add -A && git -C "${STAGE}/work/kit" commit -qm "chore: gauntlet room staging (answer key removed)"
    cp tests/gauntlet/seed-card-contributor.md "${STAGE}/work/CARD.md"
    cp tests/gauntlet/check-submission-contributor.sh "${STAGE}/work/checks/"
    ;;
  *)
    echo "unknown persona: ${PERSONA}" >&2; exit 64;;
esac

docker build -q -f tests/gauntlet/cleanroom/Dockerfile -t kit-gauntlet-room tests/gauntlet/cleanroom
echo "Room ready. The probe's instruction is: read /work/CARD.md and follow the kit's own docs."
docker run --rm -it \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  -v "${STAGE}/work:/work" \
  kit-gauntlet-room
