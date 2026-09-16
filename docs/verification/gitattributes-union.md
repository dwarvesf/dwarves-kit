# Proof of done: the repo declares its append-only files `merge=union`

2026-09-16. Acceptance: `git check-attr merge` answers `union` for `_meta/BACKLOG.md`,
`_meta/backlog-staging.md` and `docs/implementation-notes/*.md` and `unspecified` for source
files; a sibling session's uncommitted board row survives `bin/wrap apply --apply` with
`wrap.pull_past_dirty` true, lands inside the table rather than above the title, stays
unstaged, and leaves no stash; two branches each adding a row merge with no conflict. Lane:
normal. Files: `.gitattributes`, `lib/wrap/wrap.sh`, `tests/test-gitattributes-union.sh`,
`commands/wrap.md`.

## The failure this replaces

The kit shipped every union mechanism and no `.gitattributes` of its own, so the board was
never declared union HERE while the sibling repo ops-toolkit declared the same file and never
collided. Two sessions adding a row hit a stash-pop conflict; one sitting resolved it four
times by hand, each time with a stash push, an ff-only merge, a conflicted pop, a throwaway
script over the hunks, and a reset to leave the row unstaged.

The brief proposed a hunk resolver on wrap's POP CONFLICT path instead. A measured repro
refuted the premise: `git stash pop` resolves a union-declared text file with no markers.
Evidence and the rejected alternative: `docs/implementation-notes/gitattributes-union.md`.

## Green run

Command: `bash tests/test-gitattributes-union.sh`
Exit: 0
Output: `27/27 passed`
Verdict: PASS. Four cases against real git repos built on disk, two of them the
no-declaration controls that reproduce the hand-resolved conflict and the refused merge.

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 508 passed`
Verdict: PASS. The carry-across-pull contract is unchanged for anchored files; the new
union-driver path is reached only by a file with no `---` anchor.

## Negative control

Command: `bash lib/gate/negctl.sh . "bash tests/test-gitattributes-union.sh" "git rm -q --cached .gitattributes >/dev/null 2>&1; rm -f .gitattributes"`
Exit: 0
Output:

```
Exit: 0 (green before mutation)
Mutation: git rm -q --cached .gitattributes >/dev/null 2>&1; rm -f .gitattributes
Changed: .gitattributes
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- .gitattributes
Exit: 0 (green after restore)
Verdict: PASS
```

Verdict: PASS. Deleting the declaration turns the suite red and restoring it turns it green,
so the suite measures the declaration and not the fixtures around it.

## Reproduce

```
git -C <repo> checkout feat/wrap-pop-union
bash tests/test-gitattributes-union.sh
bash tests/run-all.sh
```
