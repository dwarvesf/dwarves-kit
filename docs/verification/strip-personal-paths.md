# Proof of done: strip personal workspace example paths (ID-296)

**Change class:** behavioral (the diff touches `lib/stats/src/stats/config.py`, a
`.py` docstring, so the proof gate classes the branch behavioral; the change itself
is path-string neutralization only, no runtime behavior changes).

**Claim:** no personal `~/workspace/tieubao/...` example paths remain in the
publicly-shipped `lib/stats/`, `skills/`, and `docs/` trees. Personal example paths
are replaced with the neutral placeholder `~/workspace/<owner>/<repo>`; the
leak-guard *pattern* strings (`grep ... 'workspace/tieubao'`) that document the
absence checks are deliberately preserved, and the functional sibling-repo paths in
`tests/` (which resolve real on-disk repos) are out of scope and left intact.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | No `~/workspace/tieubao/<repo>` example path in `lib/stats/`, `skills/`, `docs/` | PASS |
| 2 | Leak-guard grep-pattern docs (`'workspace/tieubao'` with no trailing slash) preserved | PASS |
| 3 | Full meta suite green (no regression from the docstring edit) | PASS |
| 4 | Functional `tests/` sibling-repo paths untouched | PASS |

## Confirmation run

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Leak absent in scope | `grep -rn 'workspace/tieubao/' lib/stats/ skills/ docs/` | 1 (no match) | PASS |
| Meta suite | `bash tests/test-meta.sh` | 0 | PASS (698/698) |

## Run detail

```
$ grep -rn 'workspace/tieubao/' lib/stats/ skills/ docs/
grep exit: 1        # no matches -> no personal example paths remain

$ bash tests/test-meta.sh
Passed: 698 / 698
All meta tests passed.
```

## NEGATIVE CONTROL

Reintroduce one personal path, confirm the check catches it (RED), then restore
(GREEN):

```
$ perl -pi -e 's{workspace/<owner>/ops-toolkit}{workspace/tieubao/ops-toolkit}g' \
    lib/stats/docs/verification/schema.md
$ grep -rn 'workspace/tieubao/' lib/stats/docs/verification/schema.md
lib/stats/docs/verification/schema.md:78:cd ~/workspace/tieubao/ops-toolkit
grep exit: 0        # leak present -> RED (check would fail), as expected

# restore the neutralized form
$ perl -pi -e 's{workspace/tieubao/}{workspace/<owner>/}g' \
    lib/stats/docs/verification/schema.md
$ grep -rn 'workspace/tieubao/' lib/stats/ skills/ docs/
grep exit: 1        # clean again -> GREEN
```

**Verdict: PASS.** The scope is free of personal example paths, the leak reappears
the moment one is reintroduced, and the meta suite is unaffected.

**Rollback:** `git revert` this commit (or `git checkout master -- <file>`) restores
the prior paths; the change is text-only across docs plus one `.py` docstring, no
schema/data/state migration, so rollback is a plain revert with no data step.

## Reproduce

```
grep -rn 'workspace/tieubao/' lib/stats/ skills/ docs/   # expect: no output, exit 1
bash tests/test-meta.sh                                    # expect: 698/698
```
