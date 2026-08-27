# ID-475: derive the command-count check in the emit sweep

## Claim

`tests/test-command-emit-sweep.sh` pinned a literal roster size
(`assert_eq ... "$TOTAL_COMMANDS" "36"`, previously `"32"`) that a prior PR
(`c3c86b0`, #425) had already re-pinned once. The repo's own rule (CLAUDE.md,
"No hardcoded counts in docs") says a load-bearing count must be DERIVED, never
a literal, because a literal goes stale on the next addition. The count line
is now an informational echo with no assertion; AC1's no-orphan sweep (every
command either emits `gate-ledger` or is named in `WORKFLOW.md`'s exemption
table) is the real, self-maintaining invariant and is unchanged. This matches
the sibling wiring sweeps (`test-kri-wiring.sh`, `test-docs-wiring.sh`), which
never carried a count pin.

## Run table

| # | Action | Result |
|---|---|---|
| 1 | `bash tests/test-command-emit-sweep.sh` (before fix, real repo, 36 commands) | 19 / 19 passed (the literal pin currently matches reality) |
| 2 | `bash tests/test-command-emit-sweep.sh` (after fix, real repo) | 18 / 18 passed (one assertion removed, replaced by an info line) |
| 3 | current repo re-run after restore | 18 / 18 passed |

## Negative control

The current repo already has 36 commands, matching the pinned literal, so
there is no live RED to revert on the real tree today (a prior PR already
re-pinned it once). The failure mode this fix removes is the NEXT addition:
reproduced on a scratch copy of `commands/` with one legitimate new command
added (`review.md` duplicated as a 37th file, still `gate-ledger`-wired, so
AC1's real invariant would still be green):

```
$ TOTAL_COMMANDS=$(find fixture-repro/commands -maxdepth 1 -name '*.md' | wc -l)
Simulated roster growth: TOTAL_COMMANDS=37
--- OLD (pre-fix) behavior: hardcoded literal pin ---
FAIL (expected '36', got '37')
--- NEW (post-fix) behavior: derived, no literal ---
  (info) commands/ currently has 37 command files -- AC1 above is the real invariant; no hardcoded pin here
```

RED under the old literal on the very next legitimate addition, even though
nothing is actually wrong (AC1 stays green); the new version reports the count
without asserting on it, so it never goes red for this reason again. Restored
`tests/test-command-emit-sweep.sh` to the fixed version on the real repo
(`git checkout HEAD -- tests/test-command-emit-sweep.sh`) and re-ran: 18/18
passed.

## Review

- **Root cause, not another re-pin:** the row explicitly rejected "bump the
  number again" as the fix; the literal assertion is removed rather than
  updated a third time.
- **No loss of signal:** AC1's sweep (`sweep_check`) already fails loudly
  (with named orphans) the moment a real command lacks both a `gate-ledger`
  mention and an exemption-table entry; the count line never caught anything
  AC1 did not already catch; the row's own text ("gate-ledger orphan sweep
  flags the commands added since") was resolved on the real repo before this
  branch by `c3c86b0`, and this fix now prevents the count-pin symptom from
  recurring independent of that.
- **Per-new-command judgment:** the current roster (36 files) has zero
  orphans (`AC1` passes), so no command needs new classification right now;
  the judgment call the row asks for ("decide per new command whether it
  should emit or be exempted") is exercised at the moment a future command
  triggers AC1, not retroactively invented here.

No blockers.
