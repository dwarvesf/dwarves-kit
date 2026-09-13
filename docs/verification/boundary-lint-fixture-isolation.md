# Proof of done: isolate boundary-lint fixtures per acceptance case

Change: `tests/test-boundary-lint.sh` AC2 and AC3 shared one `mktemp -d` fixture (`$FX`).
AC2 plants a hardcoded-path violation and asserts `boundary-lint.sh` catches it. AC3 then
reused the SAME `$FX` (still holding AC2's planted violation) to plant a hardcoded-name
violation and assert `boundary-lint.sh` catches that too. Neutering `name_re` alone left
AC3's "exits non-zero" assertion (line 46, pre-fix) PASSING, because the path check still
caught AC2's leftover violation in the shared dir; only AC3's message-content assertion
(line 47, pre-fix) actually exercised `name_re`. AC3 now resets to a fresh `mktemp -d`
before planting its own fixture, so a broken `name_re` has nothing else in the dir to hide
behind.

## Premise check (reproduced the mask before fixing)

Ran the pre-fix test with `name_re` neutered (`perl -pi -e 's/^name_re=.*/name_re="zzz-neutered-zzz"/' lib/gate/boundary-lint.sh`):

```
=== AC3: negative control -- a planted retired-skill name in a NEW commands/*.md is caught ===
  PASS planted name violation (new commands/*.md file) exits non-zero
  FAIL planted name violation names itself in the message boundary-lint: consumer path hardcoded: ...lib/evil-path.sh:2:SRC="$HOME/workspace/<owner>/dotfiles/home/dot_claude/skills/whatever"

=== 4/5 passed ===
```

Confirms the report: the exit-code assertion (line 46) passed on AC2's leftover path
violation, not on the name check; only the message assertion (line 47) failed.

## Recorded run (2026-09-12)

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-boundary-lint.sh` (fixed) | 0 | PASS 5/5 |
| `bash tests/test-meta.sh` | 0 | PASS 852/852 |

## Negative control (`lib/gate/negctl.sh`)

```
Command: bash tests/test-boundary-lint.sh
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/^name_re=.*/name_re="zzz-neutered-zzz"/' lib/gate/boundary-lint.sh
Changed: lib/gate/boundary-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/boundary-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Manually confirmed the stronger claim (both AC3 assertions now fail under the same
mutation, proving the mask is closed): with `name_re` neutered against the fixed test,
AC3 printed `FAIL planted name violation (new commands/*.md file) exits non-zero` AND
`FAIL planted name violation names itself in the message boundary-lint: PASS` (its own
fresh fixture dir has no leftover path violation to hide behind).

## Docs touched

`docs/CHANGELOG.md` `[Unreleased] / Fixed` gains one entry. `_meta/BACKLOG.md` ID-872
flipped to `shipped`.

## Rollback

Revert the commit; AC2 and AC3 go back to sharing one fixture dir.
