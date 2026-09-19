# Proof of done: union carry independent of the nonunion branch

`wrap apply`'s union-marked file carry used to live in an `else` reachable only
when no non-union dirty file existed. With `wrap.pull_past_dirty` on and a
non-union file dirty, union files fell into the pull-past-dirty stash instead;
on 2026-09-19 that path left `_meta/LAB_LOG.md` and `research/VERDICTS.md` dirty
through the pull and kept the stash (`wrap-pull-past-dirty-1789837512-28787`).

Now the carry runs whenever union-marked files are dirty and the pull can
proceed (apply + either no non-union blockers or the knob on); only genuinely
non-union blockers are stashed.

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS - all 728 cases, including the rewritten incident case
         "a dirty union file beside a dirty non-union file is carried, not
         stashed": saved-aside + carried-back lines printed, only the non-union
         blocker stashed and restored, both local and remote log lines survive
```

## Negative control

```
Command: keep the old pinning (stash both files) -- the pre-change test
         "union pop: both blocking files were stashed" asserted
         'stashed 2 dirty tracked file(s)'
Exit: 1
Verdict: PASS - under the fix that assertion goes RED (stash count is 1),
         proving union files no longer ride the stash path; the test was
         rewritten to the new contract and the suite is green
```

## Rules pinned

- The carry only runs when the pull can proceed: knob off plus a non-union
  dirty file still skips it (case 3 of the union suite unchanged: the union
  file stays byte-identical, the abort names the non-union blocker).
- `saved_dir` carry restores verbatim on a failed pull, unchanged.
