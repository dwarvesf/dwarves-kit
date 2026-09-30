# Retro: safety-gate splits segments the way bash does (SPEC-332)
Date: 2026-09-29
Sprint: 2026-09-27 to 2026-09-29, one long background session

Answers below were drafted by the lead from the session record, not collected one question at a time; the operator asked mid-run why it took so long, and can correct them.

## Metrics
- Revisions of the hook before ship: 7; validation rounds: 6, every one NEEDS REVISION, plus one break-it pass; `validate` closed by an audited override
- Tests: `test-hooks.sh` 513 to 605 (Q1 to Q91), 798 after merging master
- Master's hook fails 64 of the new rows; none of the pre-existing rows changed verdict
- Cost of a 28 KB command: 17 s to 0.4 s

## What worked
- Fresh Opus validators that had to probe every critical against the branch hook, master's hook, and real bash with an `echo PWN` stand-in. Rounds 3 to 6 reported nothing unconfirmed.
- Asking the validator to rate likelihood (common, plausible, contrived) from round 5 on. That turned "NEEDS REVISION" into a stop signal the lead could act on.
- Scratch clones for negative controls, so mutations never raced the validators probing the worktree.

## What hurt
- Scope grew from one hole (a quoted separator) into a bash parser in awk. Each revision's new rule (comment handling, the arithmetic frame, the rewind) brought its own edge cases, and three of the regressions against master were introduced by the fix itself.
- The "any unrecorded bypass is critical" rule has no floor for a parser with unbounded edge cases. The stop came from the operator's "why so long", not from the process.
- Seven negative controls in parallel failed on the unmutated suite: the `backlog.sh` rows share state across concurrent suites. The serial re-run cost an hour.
- NC3 went vacuous when a later revision made its target row pass without the mechanism it guarded. The control table was never re-derived after a revision.

## Action items
- [ ] Give the fresh validator a severity floor for parser-shaped gates: a critical must be a regression against master or a shape rated common or plausible; contrived shapes land as recorded holes -- owner: @tieubao -- deadline: 2026-10-06
- [ ] Make `tests/test-hooks.sh` safe to run twice at once (the `backlog.sh` section), so negctl can fan out -- owner: @tieubao -- deadline: 2026-10-06
- [ ] After any revision, re-run every negative control before claiming it; a control that passed on an earlier revision proves nothing about the current one -- owner: @tieubao -- deadline: 2026-10-06
