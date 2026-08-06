# Round 1 findings (doorway, 2026-08-06)

## F1 MAJOR, surface: install crashes mid-run without jq

Transcript evidence (probe's own summary): "install.sh needed jq, which wasn't
on the system and couldn't be apt-get installed (no root), fetched a static jq
binary from the official GitHub release into ~/bin instead, then the installer
completed cleanly". README line ~134 names the prereq; install.sh's
settings-merge jq call was unguarded, so the failure lands mid-install instead
of at the door. Revision: fail-fast prereq loop at install.sh top.

## F2 MINOR, harness: checker KIT_ROOT arithmetic breaks in-room

Probe's own diagnosis: "it computes KIT_ROOT=$(cd $(dirname $0)/../.. && pwd).
Since the script lives at /work/checks/, that always resolves to /". Verified:
`bash lib/adopt.sh --check <fixture>` from the real kit root exits 0
("adopted"). Revision: env-first, installed-kit-second resolution.

## F3 MINOR, harness: rule-7 exclusion too narrow

The probe read docs/verification/kit-gauntlet-prep.md from the tarball, which
names the checker's source location. Harmless here, an answer-key channel in
principle. Revision: strip every *gauntlet* artifact under docs/verification
at staging.

## Conduct notes

Interventions: none. Key echoes in transcript: 0 (grep count). Tool errors: 1
(an ls of /, part of the probe's own F2 diagnosis). The probe chose the bash
install path unprompted because the room has no plugin marketplace, exactly
the day-one reality the round was built to exercise.
