# Step 7b builds through the lane, and the Built line says which one

`/kit:wrap` step 7b builds the candidates a session produced rather than proposing them. It
told the session to edit the home tool and commit, inline, at session close. That is a real
change entering a real repo with no lane, no verification command, and no record beyond one
report line. The same change on any other path owes a lane, a check, and a proof.

The report line hid it too. `<label> ENHANCE <home>: <file> (<commit>)` reads identically
whether the build passed a check or nobody ran one.

## The change

Three parts, one cause.

1. The precedent check keeps its job unchanged: it decides the HOME and the `ENHANCE` /
   `NEW` token, and nothing else.
2. `lib/classify/lane-classify.sh classify` decides where the build happens. `tiny` builds in
   the home repo on its own branch, behind one verification command whose output the report
   quotes, then commits. `normal`, `full`, `bug`, and `backfill` do not build inside wrap: the
   row is staged with `bin/wrap stage` and a six-section goal draft is written to
   `.claude/goals/<slug>.md` in the home repo, which is also the goal pointer the drain fence
   needs. Worker model tiers are named: Sonnet default, Opus for verification and for
   security, money, or data-model work, Haiku for mechanical fan-out.
3. The `**Built:**` line carries the lane and the closure:
   `(lane=tiny, verified: <check>, <commit>)`, `(lane=<lane>, staged + goal drafted: <path>)`, or
   `(lane=<lane>, staged: build_candidates off)`. The knob still governs building only; it now
   classifies too, so a row staged under it names the lane it owes.

`lib/wrap/report-lint.sh` needs no change: its `ENHANCE` / `NEW` token check already survives
a suffix, and a line carrying only a lane suffix still fails. That claim is what the new tests
pin, because an unpinned claim about a lint is the same shape of trust this step removed.

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 326 passed`
- Verdict: PASS

The four new cases inside that run:

| Case | Fixture `**Built:**` value | Expected | Got |
|---|---|---|---|
| tiny build | `wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=tiny, verified: bash tests/test-alert.sh, a1b2c3d)` | exit 0 | exit 0 |
| routed on | `cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged + goal drafted: .claude/goals/cron-fire.md)` | exit 0 | exit 0 |
| knob off | `cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged: build_candidates off)` | exit 0 | exit 0 |
| suffix alone | `lib/wrap/report-lint.sh (lane=tiny, verified: bash tests/test-wrap.sh, abc1234)` | exit 1, names the missing token | exit 1, `no ENHANCE <home> or NEW (precedent: ...) token` |

The third case is the one that matters: the lane suffix must never let a session's own
deliverable pass as a 7b candidate.

- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output: `Passed: 851 / 851`
- Verdict: PASS

## Negative control

Produced with `lib/gate/negctl.sh` after the change was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: replace the report-lint ENHANCE/NEW token arm with a catch-all `*) : ;;`
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation removes the token requirement, which is exactly what the lane suffix could have
quietly replaced. The suite goes red, so the new cases constrain the thing they name.

## What this does not cover

The lint reads a report; it cannot see whether the lane classifier ran, whether the tiny-lane
check was real, or whether the goal draft exists at the path the line names. Closing that
would mean the lint reading the home repo's git log and file tree from inside a report check,
a much bigger surface than the hole justifies. The line makes the lane and the check explicit
and attributable, which is the step that was missing.

<!-- provenance: ID-827 -->

## Re-verified after merging master

Master moved 32 commits under this branch before the PR landed, and two of them touched the
same step. It gained the LIST form for `**Built:**` (a bare header plus one bullet per
candidate) and a rewritten per-item rule in `lib/wrap/report-lint.sh` that checks each bullet
rather than each line. The lane suffix composes with both: the token check reads the item, the
suffix trails it, and neither rule reads the other's slot.

`commands/wrap.md` was resolved by taking master's text and re-applying the lane delta on top,
because master's `b. Candidates` gained material the branch never had (the OUTPUT-versus-METHOD
hole, and repetition a session delegated to subagents). A mechanical keep-both would have
shipped that paragraph twice. `_meta/BACKLOG.md` and `tests/test-wrap.sh` were additive on both
sides and kept both.

| Check | Command | Before the merge | After |
|---|---|---|---|
| wrap suite | `bash tests/test-wrap.sh` | 259 passed | 326 passed |
| meta suite | `bash tests/test-meta.sh` | 843 passed | 851 passed |
| conflict markers | `grep -rlE '^<<<<<<<\|^>>>>>>>' .` | n/a | none |

The four lane cases still pass unchanged against master's rewritten lint, which is the claim
that mattered: the suffix never stands in for the `ENHANCE` or `NEW` token, and a line carrying
only a suffix still fails and still names the missing token.
