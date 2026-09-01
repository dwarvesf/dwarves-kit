# SPEC-039: Verification-pipeline absence-checks

Status: VALIDATED
Lane: normal
Backlog: ID-020
Branch: (dispatched worktree)

## Problem

`task-verifier` and `integration-checker` assert that the new artifact EXISTS. Neither asserts that removed or replaced content is GONE. So a task whose spec says "replace X", "remove X", or "no duplication / single-source" can leave BOTH the old and the new copy in place and still pass both verifiers. This is not hypothetical: in the SPEC-024 cycle a replace-task left two copies and passed both verifiers; only the independent review caught it. The right arm of the V-model (`/kit:verify`, ID-038) shipped without closing this blind spot.

## Solution

Teach both verifier prompts an explicit absence assertion. When a task's acceptance criteria use replace / remove / delete / de-duplicate / single-source language, the verifier must confirm the OLD content no longer exists (grep for the old marker or path and require zero live hits), not merely that the new content is present. Presence-only verification is the default; the absence assertion is added on top for removal-class tasks.

## Scope

In: the prompt text of `agents/task-verifier.md` and `agents/integration-checker.md`.
Out: no new agent, no command change, no hook change. The pinning meta-test is lead-owned (added at convergence), not a worker edit.

## Tasks

- [ ] `agents/task-verifier.md`: add an absence-check clause. When the task AC says replace/remove/delete/de-dup/single-source, verify the removed content is actually gone (the old marker/path returns zero live hits), and FAIL if both old and new coexist.
- [ ] `agents/integration-checker.md`: add the integration-level twin. Across the task's touched files, assert no duplicate copies of a block that was meant to be single-sourced or relocated.

## Verification

`bash tests/test-meta.sh` and `bash tests/test-hooks.sh` still pass. A read of each agent prompt shows the absence-check clause with the removal-class trigger and the fail-on-coexistence rule.

## After state

- `agents/task-verifier.md` contains an explicit absence/removal assertion that fires on replace/remove/de-dup tasks.
- `agents/integration-checker.md` contains the integration-level absence assertion.
- (lead, at convergence) a `tests/test-meta.sh` guard pins that both prompts carry the absence-check clause. Hands-off for the worker.

## Touches

- `agents/**`

(Worker edits only `agents/task-verifier.md` + `agents/integration-checker.md`; the glob is `agents/**` because the disjointness gate proves directory subtrees, not individual files.)

(`tests/test-meta.sh` and `_meta/BACKLOG.md` are hands-off shared surfaces per WORKFLOW.md; the lead writes them at convergence.)
