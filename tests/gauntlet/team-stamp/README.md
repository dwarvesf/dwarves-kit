# Team stamp gauntlet

The preset that checks the team stamp: a clean-room agent with no kit opens a pull request that passes the generated checks. Engine: `commands/gauntlet.md`. Preset: custom.

| Slot | Value |
|---|---|
| Artifact under convergence | `templates/team-stamp/**` and `lib/stamp.sh` |
| Outcome contract | `card.md`; checker `check-submission.sh <repo.bundle> <submission-dir> <base-sha> [transcript]` |
| Tier 1 | `bash tests/gauntlet/team-stamp/tier1.sh` (deterministic, no network, no container, no model) |
| Clean room | `run.sh` and `Dockerfile`: a stamped scratch repo exported with `git archive HEAD`, a `gh` stand-in (`gh-shim.sh`), one credential (the probe key) |
| Probe | mid-tier model, a spend-capped key, nothing else |

Run the paid round on a host with a container runtime:

```bash
ANTHROPIC_API_KEY=<capped probe key> RUN_OUT=docs/verification/gauntlet/<date>-custom-team-stamp-scratch/round-N bash tests/gauntlet/team-stamp/run.sh
```

## The probe's repository is untrusted

A model wrote into it, its `.git/config` and its `scripts/` included.

- `run.sh` makes a git bundle INSIDE the container. The host never opens the probe's repository.
- `check-submission.sh` verifies the bundle, clones it into a directory it creates, and runs every git call with the system and user config off and fsmonitor and hooks disabled, from `env -i` with a minimal `PATH` and an empty `HOME`.
- Every gate script it runs comes from a pristine stamp it makes itself. A gate file the probe edited fails check 9. The probe's own test runs only inside the room.
- Only named text outputs are persisted (`run.sh` copies a fixed list), never the probe's `.git`. The key scrub scans every file including binaries, deletes a binary that holds the key, scans again, and fails the run when the key is still found.
- Tier 1 runs on the host because every file in it is written by the script itself; it sends its scripted work through the same hardened checker and plants hostile repositories to show the hardening holds.

## After a campaign

The operator rotates or revokes the probe key. Put this line in the run record's `ROUNDS.md`.
