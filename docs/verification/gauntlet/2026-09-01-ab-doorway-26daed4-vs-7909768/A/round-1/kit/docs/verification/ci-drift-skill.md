# Verification: ci-drift skill + mega.md deploy-policy paragraph + devops-triage sha step

Behavioral proof per `proof-gate.sh contract`'s bar for this task type
(`class=behavioral`, no deploy/migration/schema keyword in the diff): the real primary flow
(`tests/test-meta.sh`) run end to end, with a negative control on the one test-file assertion
this branch touches.

## Baseline (origin/master, before this branch)

```
$ bash tests/test-meta.sh
Passed: 806 / 813
Failed: 7
```

Pre-existing failures (unrelated to this branch, confirmed present before any edit):
`agent devops-triage NOT listed in MANUAL.md`, `V-model lens missing cycle phase 'Design
critique...'`, `architecture.md inventory table rows == live file count`, `README agents table
rows == live agents`, `AGENTS.md/WORKFLOW.md lost the intake story (SPEC-057)`, `review agent
'devops-triage' is OFF the ADR-0029 naming axis`, `docs/FEATURES.md is fresh (SPEC-219)`.

## Green run (this branch, HEAD)

```
$ bash tests/test-meta.sh
Passed: 808 / 814
Failed: 6
Verdict: PASS
```

Six of the seven baseline failures remain (untouched by this branch, listed above minus the
FEATURES.md one). The seventh (`docs/FEATURES.md is fresh`) now passes as a side effect of
running `lib/registry/feature-registry.sh generate` to register the new `ci-drift` skill --
this branch fixes it, does not hide it. No new failure appears anywhere in the 814-row run.

## Negative control on the one test-file edit (`tests/test-meta.sh`)

This branch widens one assertion (`audit-scanner dispatched-by names ...`) because a fourth
skill (`ci-drift`) now dispatches `audit-scanner`, and the generated `docs/FEATURES.md` row's
`cap_list` shows only the first 3 dispatchers alphabetically + an overflow count, pushing
`topology-drift (skill)` out of the literal string the old assertion checked for.

**RED (assertion reverted to its pre-branch narrow form, everything else on HEAD unchanged):**

```
$ bash tests/test-meta.sh
[FAIL] audit-scanner dispatched-by names both skill dispatchers (doc-drift + topology-drift) (expected '0', got '1')
```

**GREEN (assertion restored to the branch's widened form, `git status` clean against HEAD):**

```
$ bash tests/test-meta.sh
[PASS] audit-scanner dispatched-by names doc-drift + ci-drift, overflow count covers the rest
Passed: 808 / 814
Failed: 6
```

RED -> GREEN confirms the test-file edit is load-bearing (it fails without the fix, passes with
it), not a drive-by loosening of an unrelated check. Exit: 0 on the restored run; no other file
differs from the committed tree.

## Scope note (rollback / reversibility)

Every change in this branch is prompt/markdown content (`skills/ci-drift/SKILL.md`,
`commands/mega.md`, `agents/devops-triage.md`, `README.md`, `docs/FEATURES.md`) plus the one
test assertion above. Nothing here adds a new executable code path, daemon, or migration:
reverting the branch (`git revert` the three commits, or dropping the PR) fully restores prior
behavior with no data or deploy side effects. `[UNAVAILABLE: no live-agent-behavior harness
exists in this repo to dynamically exercise a SKILL.md's prose against a real dispatch]` --
matching the doc-drift / backlog-reconcile precedent (`docs/verification/backlog-reconcile.md`
"Scope note"), a SKILL.md's Process section is re-derived by an agent per invocation, not run by
a committed script; `tests/test-meta.sh`'s mechanical + naming-convention pins are the full
proof surface this repo has for that class of file.
