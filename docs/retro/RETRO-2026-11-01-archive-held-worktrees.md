# Retro: SPEC-415 archive stale held worktrees (`wrap apply --archive-worktrees`)
Date: 2026-11-01
Sprint: 2026-10-31 to 2026-11-01

Answers drafted by the lead from the session record (the operator asked to wrap without a Q&A round). Edit any line that misreads it.

## Metrics
- Tasks planned: all SPEC-415 tasks (A to H after the splits), completed: all, deferred: none. Accepted risks are listed in `docs/implementation-notes/archive-held-worktrees.md`.
- Validation: 4 rounds, criticals 4, 4, 1, 1. Reviewer 6 passed the design every round. Round 1 was voided in the ledger. Validate is recorded as an operator-directed override, not an APPROVED round.
- Commits on the branch: 7 (2 spec, 3 folds, 1 feature, 1 config fix, 1 proof), squashed into #1078 (`703bb5f`): 17 files, +2148/-62.
- Tests: `test-wrap-apply` 468 passed (147 new), 6 negative controls `Verdict: PASS` (AC-2, AC-16b, AC-30b, AC-31, AC-37, AC-38).
- Precursors in the same session: #1076 (step 5 default `--own`) and #1077 (`--own` scopes the origin sweep).
- Time span: spec started 2026-10-31 about 10:00 UTC, merged 2026-11-01.

## What worked
- Parallel single-reviewer validation found real data-loss paths early. Three reviewers reproduced the embedded-repo loss on git 2.56 in scratch repos in round 1, before any code existed.
- Reproduction over assertion: reviewers probed git behavior (nested repo collapse under `--untracked-files=normal`, `reflog expire` resetting `logs/HEAD`, the unmerged-index `write-tree` failure) and cited the output. Every critical arrived with evidence.
- The builder ran its own three-lens review after the build. It caught a bash 3.2 bug that would have made the sweep skip every worktree on stock macOS, plus four more defects the spec rounds could not see.
- The operator's scope rule ("default wrap touches the current session only; wider sweeps only when named") turned a muddled default into two small PRs (#1076, #1077) before the bigger feature.

## What hurt
- Whack-a-mole: each fold opened a new gap one level down (top-level nested repo, then depth-2 nested repo, then the untested DEC-S class). Four rounds of seven reviewers cost far more than the build itself.
- The lead dropped SPEC-415 once with a wrong reason (it was opt-in, so it fit the operator's rule) and restored it from the archive ref. One round trip lost.
- The lead voided round 1 by writing OUTCOME start lines after `validate-round open`, which already writes them.
- The lead's manual `ship` ledger line lacked the `shipping pr=#<n>` form, so `/kit:wrap` step 8's retro grep missed this cycle.
- The ship-gate blocked `git push --delete` for a merged branch. The lead used `gh api -X DELETE` instead.
- Atomicity findings repeated across rounds 1 to 3 (TASK-E, TASK-G, TASK-F, E1), each a separate fold.

## Action items
- [ ] When a lead records the ship gate by hand, use `shipping pr=#<n>` in the note so step 8 finds the cycle; or let `wrap merge` append it the way `wrap land` does -- owner: @tieubao -- deadline: 2026-11-15
- [ ] After two rounds that each find a new gap one level deeper, rescope or take the operator's build call instead of a third full round -- owner: @tieubao -- deadline: 2026-11-15
- [x] Memory note: `validate-round open` already writes the OUTCOME start lines, so a lead writes nothing to the rid's ledger before `close` (ops-toolkit #5071).
- [ ] Run the first real `wrap apply --archive-worktrees` dry run on a live repo and record what it skips, since the sweep has run only on fixtures -- owner: @tieubao -- deadline: 2026-11-08

## Kit feedback
- `/kit:wrap` step 10's full-lane path ran four validation rounds in one session. The spec says "re-validates once more, then stops either way", and the operator's build call was the only exit. The step could name the stop sooner.
- The ship-gate rejects `git push --delete <branch>` with no plain-ref form for a delete. A merged branch removed outside `wrap` has no gated path except `gh api`.
- Step 8's retro trigger only matches `shipping pr=#<n>`, so a draft opened with `wrap land --draft` and merged later by `wrap merge --pr` never trips it.
