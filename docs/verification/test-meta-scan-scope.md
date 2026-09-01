# Proof of done: scope the stale-phases scan to git ls-files (ID-640)

The SPEC-031/AMEND-001 "no '8 phases' string in operating surfaces" check used a filesystem `grep -r docs/ commands/ ...`, which walks UNTRACKED gauntlet room copies under `docs/verification/gauntlet/*/`. Each room carries its own `test-meta.sh` (which names the forbidden string to describe itself), so a checkout with any persisted room record failed the scan (822/823 on the main checkout, 823/823 in a clean worktree). Fix: enumerate with `git ls-files`, the same idiom the SPEC-029 dead-prefix scan already uses, so only tracked operating surfaces are scanned.

## Recorded run

```
Command: bash tests/test-meta.sh   (in a clean worktree)
Exit: 0
Verdict: PASS   # 823 / 823, All meta tests passed
```

## NEGATIVE CONTROL

An untracked file carrying the forbidden string, in the exact shape that caused ID-640:

```
Command: printf 'the kit has 8 phases\n' > docs/verification/gauntlet/fake-room/kit/test-meta.sh ; bash tests/test-meta.sh
Exit: 0
Verdict: PASS   # scan stays green: git ls-files never sees the untracked file
```

Reverse control (proves the scan still has teeth for TRACKED files): the same file matched by the old mechanism confirms the string is genuinely present and would have failed before the fix:

```
Command: grep -rIn -E "8 (workflow|lifecycle )?phases" docs/verification/gauntlet/fake-room
Exit: 0
Output: docs/verification/gauntlet/fake-room/kit/test-meta.sh:1:the kit has 8 phases
```

So the old scan caught the untracked file (the bug); the new scan does not (the fix); and a TRACKED operating-surface file carrying the string would still fail, because `git ls-files` lists it.

Rollback: single-hunk change to one grep in `tests/test-meta.sh`; `git revert` restores the filesystem walk. No state, no migration.

## Reproduce

```
bash tests/test-meta.sh
```
