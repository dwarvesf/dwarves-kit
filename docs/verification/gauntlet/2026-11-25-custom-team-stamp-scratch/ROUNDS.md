# Team stamp: a clean-room agent with no kit opens a PR that passes the generated CI

State of this record: Tier 1 ran and is green. Tier 2 (the paid clean-room probe) did NOT run. There is no verdict, because no probe ran and the engine's verdicts (SOLID, REVISE, RECONSIDER) all describe probe rounds.

## Inputs

| Input | Value |
|---|---|
| preset | custom |
| Artifact under convergence | `templates/team-stamp/**` and `lib/stamp.sh`, rendered into a scratch repo each round |
| Outcome contract | `card.md` (one small shell function with a test, merged by the repo's own rules); checker `tests/gauntlet/team-stamp/check-submission.sh` |
| Tier 1 | `bash tests/gauntlet/team-stamp/tier1.sh` |
| Probe framing | "You are a teammate's coding agent. Read only this repository's files. Complete the card and submit per the repository's own rules." |
| Clean room | `tests/gauntlet/team-stamp/run.sh` and `Dockerfile`: `git archive HEAD` of a stamped scratch repo, a `gh` stand-in that records the PR calls, one credential slot (the probe key) |
| Probe model | mid-tier, not frontier, per the engine |
| Round cap | 3 |

## Rounds

| Round | Tier 1 | Tier 2 | K | Max severity | Checker |
|---|---|---|---|---|---|
| 1 | GREEN (47 checks, 2026-11-25) | NOT RUN | n/a | n/a | not run on a probe's work |

Tier 2: NOT RUN. Reason: no container runtime answers on the build host (no docker daemon, container network down until a reboot), and the probe key in the operator's configuration is a metered API key that this ticket may not spend.

## What Tier 1 showed

- The stamped `scripts/agent-guard.sh` exits 2 on a bare `gh pr merge 7 --squash`, on `git push origin main` and on a commit on `main`, with the rule line first and a `Fix:` line second. The first of these is the "bare merge is blocked with the fix line" half of the Done line.
- The card's PR, built by script (a function, its test, a proof from the stamped `negctl.sh`, a tagged changelog line, `Closes #1`), passes `scripts/check.sh` with its own title and body, merges through `scripts/pr-merge.sh --wait 1` against the `gh` stand-in, and the checker passes it.
- The checker fails each planted break: no proof file (check 3), an untagged changelog line (check 4), a recorded bare merge (check 7).
- The room stages from committed state with no kit path in the repo, the card or the shim, and passes one credential (the probe key).
- Every generated `scripts/test-*.sh` passes with the kit absent from `PATH` and `HOME`.
- The probe's work is data. Given a hostile repository (a `core.fsmonitor`, a `core.hooksPath` with an executable hook, a `diff.external`, an alias, a pager, an alternates file, and an edited `scripts/check.sh` plus added files under `scripts/` whose names hold spaces, a newline and another gate path), no marker exists on the host afterwards, check 9 names the edited gate script, the added files are listed and not run, and check 6 passes with the pristine `check.sh`. A symlinked `.git`, objects dir or ref fails closed. `copy-out.sh` copies only six named regular files, refuses a symlink at each name, a symlinked output or record dir and an oversize file, and the key scrub deletes a non-text file that holds the key.

## Not shown

The other half of the Done line: a clean-room agent with no kit opening a PR that passes the generated CI. Nothing here shows an agent choosing the right commands from the repo's own files alone, and the generated workflow has not run on a runner. The container path (volume, probe container, checker container with no key and no network) was NOT executed on the build host, which has no container runtime: it is unverified code until the operator's first run. Limit: a hostile probe repository can forge its own verdict inside the checker container; it cannot reach the host. To run it, on a host with a container runtime and a spend-capped probe key:

```bash
ANTHROPIC_API_KEY=<capped probe key> RUN_OUT=docs/verification/gauntlet/<date>-custom-team-stamp-scratch/round-N bash tests/gauntlet/team-stamp/run.sh
```

Then run the engine over the result (`/kit:gauntlet`, preset custom, with the inputs above) and record the verdict here.

## Key

No probe key was used. After a campaign the operator rotates or revokes the probe key.

## Evidence

`round-1/submission/tier1-output.txt` holds the Tier 1 output.
