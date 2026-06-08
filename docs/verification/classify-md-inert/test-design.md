# Test design -- classify-md-inert
Profile: feature
Proof class: behavioral

> Written BEFORE the change (spec-first), then verified by a recorded LIVE run on real repo
> state (the ops-toolkit branch whose markdown-only "migrate" commit the classifier misreads
> as stateful). This is the dogfood: the verification framework finishing itself by fixing a
> real bug it surfaced, proven on real state, not a synthetic /tmp fixture.

## Hypothesis / assumptions
- Hypothesis: a diff that touches ONLY markdown/txt files is inert (docs), regardless of what
  the commit subject says. The classifier currently checks stateful keywords (incl. "migrate")
  against the commit SUBJECT before the markdown-only check, so a docs-only commit with
  "migrate" in its subject is misread as stateful and the gate demands a rollback note it does
  not need.
- Real instance: the ops-toolkit branch `worktree-verification-framework` , its commit
  140a147 "migrate eval + tool dialects" is markdown-only but classifies `stateful`.
- Assumption: moving the inert (markdown-only) check BEFORE the stateful keyword check fixes
  it without breaking real stateful changes (a code+doc migration still has non-md files, so
  it is not inert, and still hits the stateful keyword check).

## Test design
- AC1 (the fix, on REAL state): with the patched classifier, classify on the real ops-toolkit
  branch returns `inert` (was `stateful`).
- AC2 (negative control, on REAL state): the pre-fix classifier (read from the merge-base)
  returns `stateful` on the SAME real branch , the bug reproduces, proving the fix is
  load-bearing.
- AC3 (the fix ships its own proof): the patched classifier still classifies a code+migrate
  diff as `stateful` and a code-only diff as `behavioral` (no regression of real signals).
- AC4 (real gate): the installed ship-gate hook ALLOWS a push command on the ops-toolkit
  branch with NO rollback-note workaround needed (it is now honestly inert).
- AC5: `tests/test-meta.sh` stays 390/390; a regression unit test pins the md-only-inert rule.
- Expected negative control: revert the reorder -> the real ops-toolkit branch reclassifies
  `stateful` (RED), and the regression unit test fails.

## How to re-run
- `bash tests/test-classify-md-inert.sh` (regression unit test, self-contained).
- Live run, real state: see `runs/` , classify the real ops-toolkit worktree branch with the
  patched lib (inert) and with the merge-base lib (stateful), then drive the installed
  ship-gate hook on that branch.
