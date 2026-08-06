# Gauntlet campaign: kit-user persona, doorway row (J1/J2)

Engine: `/kit:gauntlet` per `commands/gauntlet.md`. Surface: the kit's
contributor surface (README, MANUAL, onboard/adopt docs, guides). Probe:
`claude-sonnet-5`, headless, `--dangerously-skip-permissions`, 30-min cap.
Runner: round 1 local (Air); round 2 planned remote (`mini-tieubao`) via
`run-remote.sh`, dogfooding the runner-host knob.

**Key caveat (recorded per B7):** rounds run on the shared
`op://Toolkit/anthropic-api-key` item, not a dedicated spend-capped probe key;
mint the capped item before unattended campaign scheduling.

## Inputs

Frozen card: `round-1/room/CARD.md` (doorway: install + adopt + tiny-lane
README-flag fix). Checker: `check-submission-user.sh`. Tier 1 GREEN before the
round (master state, `tests/gauntlet/tier1.sh`).

## Rounds

| Round | K | Max severity | Checker | Wall clock | Cost | Turns | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | 3 | MAJOR | RED in-room (harness defect F2); adoption independently verified green (`lib/adopt.sh --check` exit 0) | 8m15s probe | $2.86 | 67 | Card COMPLETED unaided; 1 surface + 2 harness findings; revise + respin |

[[QL-VERDICT round=1 clean=false findings=3]]

## Round 1 findings (evidence: `round-1/findings.md`)

| # | Severity | Against | Finding | Revision |
|---|---|---|---|---|
| F1 | MAJOR | surface | `install.sh` crashes MID-install on a jq-less machine (unguarded jq at the settings-merge step); README names the prereq but the front door does not enforce it. Probe recovered via a static binary, an above-median move | fail-fast prereq check (jq, git) at install.sh top, before any write |
| F2 | MINOR | harness | room-copied checker's `KIT_ROOT=../..` resolves to `/` at `/work/checks` depth; the probe diagnosed this itself and correctly declined BLOCKED.md | env-first, installed-kit-second root resolution in the checker |
| F3 | MINOR | harness | rule-7 leak: `docs/verification/kit-gauntlet-prep.md` rode the tarball and named the checker's source home | exclusion widened to every `*gauntlet*` under docs/verification |

Probe conduct: zero coaching, zero key echoes in the transcript (scan count
0), no answer-key read beyond F3's leaked proof file, PR.md well-formed,
conventional commit, gate records written in the fixture. The completed card
plus a harness-only checker failure scores the SURFACE nearly clean at the
doorway; F1 is the round's real catch.

## Next

Round 2: replication with revisions committed (rule 9: SOLID needs two
consecutive unaided passes), runner host `mini-tieubao`.
