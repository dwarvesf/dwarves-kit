# Retro: spec-validate sustainability lens (SPEC-314)

Date: 2026-09-26
Sprint: 2026-09-26 (one session)

Answers below were drafted from session evidence, not from an operator interview.

## Metrics
- Tasks planned: 4 (T1 lens, T2 roster tests, T3 docs, T4 eval), completed: 4, deferred: 0
- Commits: 3 on the branch, squash-merged as `118485af` (#771)
- Files changed: 16 (+338/-28)
- Key commits: `4eff5aca` feat(spec-validate): add an advisory sustainability lens; `f02be115` proof and eval; the review-fix commit that became the squash subject

## What worked
- Running `/kit:spec-validate` on its own spec caught seven real gaps before any code. The sharpest one: `tests/test-design-record.sh` fails if the word `references` appears anywhere in the command, and the dependency-lifespan question would likely have used it.
- A behavioral eval gave prompt-only text a real proof. Two fixture specs and fresh Sonnet reviewers ran the old and new command side by side. The eval showed the lens fires on a launchd job with no heartbeat and stays quiet on a flag rename.
- `wrap start` and `wrap land` removed every hand git step in a foreign repo. They covered the worktree, PR, squash, tree verify, pull, and tidy.
- Writing the roster tests first showed four red assertions before the command changed.

## What hurt
- The ship gate was recorded as `ran "wrap land"` instead of `Ship ran "shipping pr=#771"`. Wrap step 8 greps for the PR number, so the retro would have been skipped silently. Wrap caught it only because the lead checked the ledger by hand.
- The mutate/test/restore control was hand-rolled while `lib/gate/negctl.sh` existed. The `proof-gate.sh contract` hint the session read says "revert -> RED -> restore" and does not name the tool.
- The negative-control criterion was absolute: "no finding names cost". The second control run named cost under Reviewer 5 as a minor note, so the control partly failed. A per-dimension criterion with a stated run count would have predicted that.
- The squash merge took the last commit's subject (`fix(...): drop the stale advisory count`) as the PR title, so `git log` undersells the feature.
- `tests/test-meta.sh` runs past the 120s Bash limit, so two mutation runs went to the background mid-step.

## Action items
- [ ] `wrap land` records `Ship ran "shipping pr=#<N>"` for the branch rid when that rid has a run log, so a land-shipped spec cycle triggers the wrap retro -- owner: @tieubao -- deadline: 2026-10-03
- [ ] The `proof-gate.sh contract` behavioral hint names `bash lib/gate/negctl.sh <root> "<test-cmd>" "<mutate-cmd>"` -- owner: @tieubao -- deadline: 2026-10-03
- [ ] A fixture-based eval harness for prompt-only commands: run the branch and master command text on fixture specs in fresh subagents and diff the findings -- owner: @tieubao -- deadline: 2026-10-10
- [ ] A negative control judged on LLM output states its criterion per dimension and names a run count -- owner: @tieubao -- deadline: 2026-10-03

## Kit feedback
- Doc impact: every companion doc for the diff changed in-branch. The review still found one live stale count in `commands/spec.md`, which no pin covered. A new test-meta guard now covers it.
- Lane telemetry: no misfire line names `sustainability-lens`.
- Decision capture: no undocumented decision. The placement, advisory status, trigger scope, and rejected template section are in the spec's Decision Log and `docs/implementation-notes/sustainability-lens.md`.
- `wrap land` squash-merges under the last commit's subject. When a branch ends on a fix commit, the feature title is lost.
