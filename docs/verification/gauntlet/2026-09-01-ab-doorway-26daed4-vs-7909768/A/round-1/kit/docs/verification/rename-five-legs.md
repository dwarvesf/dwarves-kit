# Verification: rename the five legs to Shape/Build/Watch/Check/Learn

Slug: `rename-five-legs` (branch `docs/rename-five-legs`). Backlog row: `_meta/BACKLOG.md` ID-292.

## What changed

A docs-first vocabulary sweep of ADR-0034's loop taxonomy per the Plain Words rule
(`CONTRIBUTING.md`, `docs/research/2026-07-16-plain-words-inventory.md`): Specify -> Shape,
Execute -> Build, Observe -> Watch, Govern -> Check (Learn kept), and the container word
leg -> stage. Amends `docs/decisions/0034-harness-loop-taxonomy.md` per the ADR's own lock
(a new `## Amendment` section; decision 3's as-decided table is left unrewritten, matching
the precedent in `docs/decisions/0029-review-function-naming-and-form.md`). No module
renames, no code-identifier renames; the registry-lint assertions in `tests/test-meta.sh`
and `tests/test-config-registry.sh` were updated to match the renamed section headers
(`## The five stages`, `## Module stages`).

## 2026-07-18 0000 -- green run

Command: `bash tests/test-meta.sh && bash tests/test-config-registry.sh && bash tests/test-hooks.sh && bash tests/test-kit-contract.sh`
Exit: 0 (each suite)
Output (excerpt):
```
tests/test-meta.sh:            Passed: 698 / 698   All meta tests passed.
tests/test-config-registry.sh: 19/19 passed
tests/test-hooks.sh:           Passed: 480 / 480   All tests passed.
tests/test-kit-contract.sh:    kit-contract: 25 passed, 0 failed
```
Verdict: PASS

## Negative control (before vs after, throwaway worktree off HEAD~1)

The rename is a mechanical vocabulary sweep with matching doc + test-assertion pairs on
both sides of the diff, so `tests/test-meta.sh`'s own five-stage/five-leg check is
structurally satisfied either way (empty-block short-circuit: if a header search on
either the README or the registry side comes up empty, the completeness loop simply never
runs rather than failing -- a pre-existing leniency in that assertion, not introduced by
this change). The meaningful negative control here is therefore content presence, not a
test-suite red/green flip: does the new vocabulary actually NOT exist before the commit and
DOES exist after.

Command (pre-rename baseline, `git worktree add <tmp> HEAD~1`):
```
grep -c "The five stages\|Shape (Specify)\|Watch (Observe)\|Check (Govern)" README.md lib/config/module-registry.md
  -> README.md:0  lib/config/module-registry.md:0
grep -c "^## The five legs\|^## Module legs" README.md lib/config/module-registry.md
  -> README.md:1  lib/config/module-registry.md:1
bash tests/test-meta.sh
  -> Passed: 698 / 698 (pre-rename baseline also green, as expected for a same-release
     vocabulary sweep with no behavior change)
```
Exit: 0
Verdict: RED for the new vocabulary (absent), confirming the pre-rename state; suite green
as the honest baseline (not a suite failure, since none was expected here).

Command (post-rename, same worktree checked out to the branch tip):
```
grep -c "The five stages\|Shape (Specify)\|Watch (Observe)\|Check (Govern)" README.md lib/config/module-registry.md
  -> README.md:4  lib/config/module-registry.md:11
grep -c "^## The five legs\|^## Module legs" README.md lib/config/module-registry.md
  -> README.md:0  lib/config/module-registry.md:0
```
Exit: 0
Verdict: GREEN for the new vocabulary (present, old headers gone), proving the diff is
real content, not a no-op.

## Reproducible

```
git -C <repo> worktree add /tmp/kit-negctl HEAD~1
grep -c "The five stages\|Shape (Specify)\|Watch (Observe)\|Check (Govern)" \
  /tmp/kit-negctl/README.md /tmp/kit-negctl/lib/config/module-registry.md
git -C /tmp/kit-negctl worktree remove /tmp/kit-negctl --force   # run from the main checkout
bash tests/test-meta.sh
bash tests/test-config-registry.sh
```

[PROOF OF DONE: docs-first vocabulary rename, class=behavioral per proof-ledger.sh's
diff classifier (test-assertion .sh files touched alongside docs), inert per
`lib/gate/proof-gate.sh contract` (a spec-feature/inert task type) -- both suites and this
record capture the honest evidence either way.]
