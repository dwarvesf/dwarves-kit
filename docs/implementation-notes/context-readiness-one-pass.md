# Implementation notes: SPEC-354 context-readiness one pass

Delta from `docs/specs/SPEC-354-context-readiness-one-pass.md` only.

- **Devin draft discarded.** A Devin session started this work and left an uncommitted 144-line rewrite. It was stopped mid-edit and replaced with a smaller diff aimed at the one hot loop. The draft was not reviewed further.
- **The first cut broke equivalence.** The first commit handed the raw `ls` list to awk. The review lens found that BSD awk aborts the whole pass on a path it cannot open, and `2>/dev/null || true` hid it: one dangling link turned `spec:ambiguous(...)` into `no spec found`. The readable-file filter (spec Change 1a) fixes it. The 11-case baseline missed this because no case had an unopenable path. The edge fixture now has one.
- **Root guard on the mode-000 assertion.** `[ -r ]` is true for root, so that case does not exist under a root CI container and the assertion is skipped there.
- **Whitespace class.** `[[:space:]]` became `[ \t\r\f\v]` for mawk 1.3.3. That covers the same characters as the old `grep -E` class in the C locale.
- **Timing depends on load.** Best of three was 0.36s idle and 0.87s at load average 25, against 2.15s and 4.8s for the old hook. AC5 holds on an idle machine, not under load.
- **Open question.** Running `tests/test-hooks.sh` inside this worktree appended rows to the worktree's `_meta/BACKLOG.md` twice. The validator's `git archive` copy did not reproduce it, so the trigger is probably something worktree-specific. The negative control command restores the file. It is out of scope here and worth one look later.
