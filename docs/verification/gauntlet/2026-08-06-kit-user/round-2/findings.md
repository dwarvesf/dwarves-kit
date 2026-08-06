# Round 2 findings (doorway, remote on the Mini, 2026-08-06)

Checker: SUBMISSION GREEN, all 6 assertions pass (round 1's F2 fix verified
live: the adoption check now resolves the probe's installed kit correctly).
Probe: 69 turns, 5m00s, $2.39, is_error=false. Credential scan: 0 hits.
Interventions: none.

## F1 verified fixed (surface, from round 1)

The room still genuinely lacks jq, so the probe still had to obtain it, but
the failure mode changed exactly as intended: install.sh now REFUSES at the
door with a named prerequisite instead of crashing mid-install. The probe read
the refusal, fetched a static binary (apt needs root it does not have), and
proceeded cleanly.

## F4 MINOR, surface: the prereq message assumes a package manager

The fail-fast message says "Install it first (brew/apt, or a static binary on
PATH)". Both probe runs independently discovered that apt requires root in a
container and fell back to a static binary download. A rootless-friendly hint
(the static-binary path) would save that detour for a contributor working in a
container or a locked-down machine. Not blocking: both probes recovered.

## Harness findings (the remote runner's own shakedown, H1-H5)

Recorded in ROUNDS.md. All five were remote-only defects invisible to a local
round; all fixed and verified by this round completing end to end.
