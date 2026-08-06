#!/bin/bash
# Build and enter the kit gauntlet clean room.
#
#   bash tests/gauntlet/cleanroom/run.sh user               # doorway card (J1/J2), drop to a shell
#   bash tests/gauntlet/cleanroom/run.sh user J4             # row J4's card + checker + fixture plant
#   bash tests/gauntlet/cleanroom/run.sh contributor         # stage persona B, drop to a shell
#
# The probe key is passed at run time, never baked:
#   ANTHROPIC_API_KEY=<capped key> bash tests/gauntlet/cleanroom/run.sh user J4
set -euo pipefail

PERSONA="${1:?usage: run.sh <user|contributor> [ROW]}"
ROW="${2:-doorway}"
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

# row_checker <row> -- the check-submission-user*.sh filename for a matrix row
# (SPEC-227 P3: J1/J2 share the doorway checker, J3+ each have their own).
row_checker() {
  case "$1" in
    doorway|J1|J2) echo "check-submission-user.sh" ;;
    J3|J4|J5|J6|J7|J8|J9|J10|J11) echo "check-submission-user-$1.sh" ;;
    *) echo "run.sh: unknown row '$1'" >&2; exit 64 ;;
  esac
}

# Persona staging.
case "${PERSONA}" in
  user)
    # Fixture: a tiny Node CLI whose README example uses the wrong flag.
    # Baseline shape (J1/J2/J3/J5/J7/J9/J10/J11 build on this unmodified;
    # J4/J6/J8 overlay row-specific plants below, inert for every other row).
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

    case "${ROW}" in
      J4)
        # Bug-lane plant: an off-by-one regression in the argv index breaks
        # EVERY --upper invocation (reads the script path, not the flag), and
        # the README now claims a green test suite. A committed test.js pins
        # down the previously-working behavior so the regression fails it.
        cat > "${FIX}/cli.js" <<'EOF'
#!/usr/bin/env node
const arg = process.argv[1]; // BUG: off-by-one, should be process.argv[2]
if (arg === "--upper") console.log((process.argv[3] || "").toUpperCase());
else { console.error("usage: cli.js --upper <text>"); process.exit(1); }
EOF
        cat > "${FIX}/README.md" <<'EOF'
# shout

Tiny demo CLI.

## Usage

    node cli.js --upper hello   # prints HELLO

## Tests

`npm test` (currently green).
EOF
        cat > "${FIX}/test.js" <<'EOF'
const { execSync } = require("child_process");
const assert = require("assert");

const out = execSync("node cli.js --upper hi").toString().trim();
assert.strictEqual(out, "HI", `expected HI, got ${JSON.stringify(out)}`);
console.log("PASS: --upper hi");
EOF
        cat > "${FIX}/package.json" <<'EOF'
{ "name": "shout", "version": "1.0.0", "bin": { "shout": "./cli.js" }, "scripts": { "test": "node test.js" } }
EOF
        ;;
      J6)
        # Mid-flight drift plant: the amendment lives OUTSIDE /work (the
        # orchestrator copies it in mid-round, per J6's own card); it is
        # never mounted into the room by this script.
        mkdir -p "${STAGE}/drift"
        cat > "${STAGE}/drift/UPDATE-J6.md" <<'EOF'
# UPDATE (mid-flight, row J6)

From the team, after the spec hardened: also cover the empty-string case for
`--repeat`. Decide and document the behavior (e.g. `--repeat 0` and an empty
text argument), then amend the in-flight spec , do not restart it.
EOF
        cat > "${STAGE}/drift/README.md" <<'EOF'
Orchestrator note (row J6 only): once the probe's spec for this round has
hardened (validated, implementation under way), copy this file into the
running room as `/work/UPDATE-J6.md`, e.g.:

    docker cp UPDATE-J6.md <container>:/work/UPDATE-J6.md

Do this once, at a task checkpoint, never before the spec exists. This
directory is host-side staging; it is not mounted into the room by run.sh.
EOF
        ;;
      J8)
        # Review-response plant: --upper already silently mishandles empty
        # input (prints a blank line, exit 0); document a promise the code
        # does not keep so review has a concrete gap to catch before ship.
        cat >> "${FIX}/README.md" <<'EOF'

## Error handling

`--upper` with no text argument exits non-zero with a usage message.
EOF
        ;;
    esac

    git -C "${FIX}" init -q && git -C "${FIX}" add -A && git -C "${FIX}" commit -qm "chore: fixture seed"

    if [ "${ROW}" = "J9" ]; then
      # Concurrent-contributor plant: a second, already-in-flight branch
      # touching the same file, left checked out on its own branch so the
      # probe starts on master and must notice it before diving in.
      git -C "${FIX}" checkout -qb other/logging-tweak
      sed -i.bak 's/usage: cli.js --upper/usage: shout --upper/' "${FIX}/cli.js"
      rm -f "${FIX}/cli.js.bak"
      git -C "${FIX}" add -A && git -C "${FIX}" commit -qm "chore: tweak usage text (other contributor, in flight)"
      git -C "${FIX}" checkout -q master
    fi

    # make-card.sh knows matrix rows (J1..J11), not the "doorway" alias;
    # doorway IS J1 (install+adopt), J2 (tiny lane) shares the same card.
    CARD_ROW="${ROW}"; [ "${CARD_ROW}" = "doorway" ] && CARD_ROW="J1"
    bash tests/gauntlet/make-card.sh "${CARD_ROW}" --out "${STAGE}/work"
    cp "tests/gauntlet/$(row_checker "${ROW}")" "${STAGE}/work/checks/"
    cp tests/gauntlet/check-lib.sh "${STAGE}/work/checks/"
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
