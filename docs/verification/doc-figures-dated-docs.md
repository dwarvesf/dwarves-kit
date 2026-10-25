# Proof of done: doc-figures-dated-docs

`doc-figures check` scanned every `docs/**/*.md` for `figures/<id>.png` references. On master that failed, because `docs/verification/doc-figures.md` quotes the `figures/nope.png` its own negative test used. The scan now prunes the dated-record folders (verification, specs, implementation-notes, retro, research, audits) and reads only README.md and the living docs.

## Green run

```
Command: bash tests/test-doc-figures.sh && bash lib/system-design/doc-figures check
Exit: 0
Output:
doc-figures: 25 passed, 0 failed (25 checks)
doc-figures: ok (12 figures)
Verdict: PASS
```

## Negative control

Mutation: `git show origin/master:lib/system-design/doc-figures > lib/system-design/doc-figures` (the unpruned scan), run by `lib/gate/negctl.sh` after the fix was committed.

- With the old scan: `doc-figures: 23 passed, 2 failed (25 checks)`; the new case "a dated record quoting an unknown id is not scanned" goes red.
- Restore: `git checkout HEAD -- lib/system-design/doc-figures`, then green again. Exit: 0 (green after restore).

## Rollback

Revert the squash commit. `doc-figures check` then fails on master again through the quoted id in the doc-figures proof, which is a false alarm and not a data loss.

Verdict: PASS
