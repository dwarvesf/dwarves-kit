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

| Round | Host | K | Max severity | Checker | Wall clock | Cost | Turns | Outcome |
|---|---|---|---|---|---|---|---|---|
| 1 | Air (local) | 3 | MAJOR | RED in-room (harness F2); adoption independently green | 8m15s | $2.86 | 67 | Card COMPLETED unaided; 1 surface + 2 harness findings |
| 2 | Mini (remote) | 1 | MINOR | **GREEN, 6/6** | 5m00s | $2.39 | 69 | Card COMPLETED unaided, checker fully green; F1 fix verified live; 1 minor surface finding (F4) |

[[QL-VERDICT round=1 clean=false findings=3]]
[[QL-VERDICT round=2 clean=false findings=1]]

Severity trajectory: MAJOR -> MINOR (falling). Round 2 is the first fully
clean pass; rule 9 wants that repeated once on the SAME surface before SOLID,
so the doorway sits at REVISE with one replication round outstanding.

## The remote runner's own shakedown (harness findings H1-H5)

Round 2 ran on the Mini, and getting there exposed five remote-only defects
invisible to any local round. Recorded because the remote runner is itself
part of the contributor surface for anyone running rounds off-laptop:

| # | Defect | Class | Fix |
|---|---|---|---|
| H1 | ssh export shattered on the prompt's apostrophe | shell transport | base64 the probe command across ssh |
| H2 | the Keychain cache cannot store in a non-interactive ssh session and leaves a 6h suppression marker returning empty | secret plumbing | one direct vault read per ROUND as fallback (zero quota on a Connect host) |
| H3 | `git archive HEAD` fails on the shipped copy (a tarball extraction, not a repo) | state transport | ship the source tarball too; `GAUNTLET_SRC_TAR` |
| H4 | `bash -c "...${PROBE_CMD}"` broke on mixed quotes | shell transport | the probe command runs from a file |
| H5 | colima shares only `$HOME`, so a `/var/folders` stage bind-mounts EMPTY | runtime topology | `GAUNTLET_STAGE_DIR` under `$HOME` |

H1/H4 recurred until the CLASS was removed: the prompt is data, so it now
lives in `/work/PROMPT.txt` and is never quoted at any layer.

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

Round 3: replication of round 2's clean pass on the same surface (rule 9),
runner host `mini-tieubao`. A second GREEN makes the doorway SOLID and clears
the campaign to climb to J3 (full lane).
