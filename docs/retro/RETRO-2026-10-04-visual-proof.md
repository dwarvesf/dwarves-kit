# Retro: visual proof upgrade and flick clef backend

Date: 2026-10-04
Sprint: 2026-10-03 to 2026-10-04 (one session)
Answers: drafted by the lead from the session record at `/kit:wrap`; the operator asked for a short retro and did not answer the three questions live.

## Metrics

- Cycles shipped: 4 (#890 battery size gate, #892 proof captured output, #894 visual proof upgrade, #895 flick clef backend). Deferred: 0.
- SPEC-385: 25 test-plan cases, 25 covered. Built as a DAG: four Devin workers (T1 to T4) in parallel worktrees, one Devin fix round, one lead patch.
- Battery on #894: 4 Opus legs, 3 returned FIX THEN SHIP, 1 HIGH security finding (a committed manifest could upload any local file to a public bucket), 3 HIGH correctness findings.
- Battery on #895: 3 Opus legs, verifier PASS, 3 small security fixes, 5 advisor findings.

## What worked

- Frozen interfaces in the spec let four workers build in parallel with zero merge conflicts on integration.
- The spec validation round before dispatch caught 13 interface gaps (wrong flush point, a bypassable gate, the wrong `.kit.toml` read) that would have produced incompatible worker builds.
- The battery earned its cost on #894: no worker test and no self-check caught the upload-any-file exploit or the dirty-tree flush.
- The lead's own end-to-end run on the real bucket found a defect no reviewer saw: Cloudflare caches a pre-upload 404 for 4 hours.

## What hurt

- Sonnet hit its weekly limit mid-session, so one worker died after committing and the rest of the build moved to Devin and Opus.
- Every Devin launch stopped at a directory-trust prompt, and the lead answered it by hand six times.
- Hooks misread text: a heredoc containing `git push` was blocked by branch-guard, a curl piped to `shasum` was blocked as pipe-to-shell, and a 64-zero fixture was blocked as a secret. Each cost a rewrite through the Write tool.
- A memory note ("battery for any normal-lane change") made a small change run the full battery; the operator caught it.

## Action items

- [ ] worker-launch answers the Devin trust prompt for kit worktree paths (being built at this wrap in ops-toolkit `feat/worker-launch-trust`) -- owner: @tieubao -- deadline: 2026-10-06
- [ ] A Cloudflare cache rule that never caches 404 on `proof.*`, so a PR image fetched before its upload does not stay broken for 4 hours -- owner: @tieubao -- deadline: 2026-10-10
- [ ] An R2-scoped token in 1Password for proof-asset, so the Mini can upload -- owner: @tieubao -- deadline: 2026-10-10

## Kit feedback

- The lane classifier returns `normal` for every non-cosmetic change; the battery size gate (#890) now carries the size signal the lane lacks.
- `wrap land` printed the new `PROOF OF DONE` block on its own landing of #894, which made the feature self-verifying.
