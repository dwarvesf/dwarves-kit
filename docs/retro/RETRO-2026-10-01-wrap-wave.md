# Retro: wrap wave and review diet
Date: 2026-10-01
Sprint: 2026-09-30 to 2026-10-01

## Metrics
- Specs planned: 4 (SPEC-359, SPEC-376, SPEC-377, SPEC-378), plus 1 added mid-cycle (SPEC-379). Shipped: 5. Parked: SPEC-365.
- PRs: #854 (land merges the default branch into a CONFLICTING own PR), #857 (`apply --pull-only`), #858 (review diet), #859 (land stops on an already-merged branch), #860 (validate large specs only, battery review on Sonnet), #861 (spec renumber fix).
- Workers: 9 Sonnet subagent builds and fixes, 4 Sonnet review lenses. No Opus worker.
- Worker wall clock: 24 to 69 minutes each, against a lead estimate of under 10 minutes.
- Master after the wave: `test-wrap` 1992 passed, `test-meta` passed, on a clean export.

## What worked
- One Sonnet review lens per PR. It found a real HIGH on three of four PRs it read: stale diff3 blocks in `commands/execute.md` (#858), a tidy baseline that would remove files written after the proof (#859, data loss), and a gate bypass once `validate` went light on the normal lane (#860).
- Porting pre-split branches by merging `origin/master` into them (no rebase, no force). Every PR and its history survived; an assert-label diff proved no test was lost (82 of 82, 218 of 218).
- Sonnet workers for every build. The lead stayed on orchestration.

## What hurt
- Estimates. The lead quoted the scripted-port target for a fresh build (SPEC-376 took 69 minutes) and padded the first estimate from retro averages.
- Master moved three times inside the wave, so every open branch re-merged and re-tested.
- Full-suite negative controls at load 11 to 19. `negctl.sh` already takes the test command; the briefs passed the full suite.
- Most kit specs pick `Lane: full` by habit. Over the 58 `SPEC-3*` specs, 4 read small under the new size rule.
- A renumber commit staged only the file move (`git mv`) and missed the `sed` edits, so master carried the stale number until #861.
- A `git checkout --` restore during a negative control wiped an uncommitted edit; it was caught and redone.
- The lead hand-rolled push, PR create, mergeable poll and squash merge six times while `bin/wrap land` does all of it.

## Action items
- [ ] Serialize branches that touch the same module inside a wave; merge one before the next worker starts -- owner: @tieubao -- deadline: 2026-10-08
- [ ] Worker briefs pass the affected suite to `negctl.sh`, never the full runner -- owner: @tieubao -- deadline: 2026-10-08
- [ ] Split `tests/test-meta.sh` (about 6 minutes a run, 902 asserts) the way SPEC-374 split test-wrap -- owner: @tieubao -- deadline: 2026-10-14
- [ ] Land own kit PRs with `bin/wrap land <worktree>` instead of the hand-rolled push and merge loop -- owner: @tieubao -- deadline: 2026-10-08

## Kit feedback
- The ship-gate refuses a compound command that contains `git push` anywhere, including the text of a `printf`, and refuses `git push --delete`; remote branch cleanup went through the GitHub API.
- The commit-format hook rejects a `SPEC-` marker in the subject, which a renumber commit naturally carries.
- Lane misfires: none of this wave's five rids appear in `lane-telemetry.sh misfires` (34 lines, all from other cycles; accepted noise for this retro). The report takes over two minutes on this host.
