# SPEC-040: Reduce execute-worker shell/hook friction

Status: VALIDATED
Lane: normal
Backlog: ID-021
Branch: (dispatched worktree)

## Problem

The `commands/execute.md` worker template does not pre-warn the recurring shell/hook gotchas, so dispatched workers keep tripping on the same traps cycle after cycle:
- fish `noclobber` makes a bare `>` redirect fail; the worker must use the clobber-forcing redirect form.
- A multi-line commit body passed via `git commit -m` with a heredoc gets mis-parsed (one cycle read a 459-character body as the subject line); `git commit -F` (a file or `-`) is correct.
- `rm` is blocked by the safety hook; the worker must use `mv` to an out-of-the-way path instead.

These are knowable in advance, so the worker template should warn them up front rather than letting each worker rediscover them.

## Solution

Add a short "Shell gotchas (pre-warn)" block to the worker prompt template in `commands/execute.md`, listing the three recurring traps and their correct form. Concise, scannable, placed where the worker reads its operating rules. No behavior change to the command; a prompt addition only.

## Scope

In: the worker-template section of `commands/execute.md`.
Out: no change to the execute control flow, the verifier loop, or any hook. The pinning meta-test is lead-owned (added at convergence). The deeper commit-mis-parse investigation is folded in only as far as documenting the `git commit -F` workaround; root-causing the parser is out of scope.

## Tasks

- [ ] `commands/execute.md`: add a "Shell gotchas (pre-warn)" block to the worker prompt template covering (1) fish `noclobber` needs the clobber-forcing redirect, (2) multi-line commit via `git commit -F`, not a `-m` heredoc, (3) `mv`, not `rm` (safety hook blocks `rm`).

## Verification

`bash tests/test-meta.sh` and `bash tests/test-hooks.sh` still pass. A read of `commands/execute.md` shows the worker template now carries the three gotcha pre-warnings.

## After state

- `commands/execute.md`'s worker template contains a "Shell gotchas" block naming the three traps and their correct forms.
- (lead, at convergence) a `tests/test-meta.sh` guard pins that the worker template carries the gotcha block. Hands-off for the worker.

## Touches

- `commands/**`

(Worker edits only `commands/execute.md`; the glob is `commands/**` because the disjointness gate proves directory subtrees, not individual files.)

(`tests/test-meta.sh` and `_meta/BACKLOG.md` are hands-off shared surfaces per WORKFLOW.md; the lead writes them at convergence.)
