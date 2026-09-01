# Implementation notes -- verify-by-execution

Execution-backed verification + the verification log. Driven by a `/goal` run, not a
`/kit:spec`, so this is the `<feature-slug>` form.

## 2026-06-06 23:00 Branch base = master, not the codebase-memory branch
- Context: the working tree sat on `feat/codebase-memory-index` with 2 unrelated uncommitted maintainer edits (marketplace `source` path tweak, BACKLOG ID-042 intake).
- Decision/Change: stashed those 2 files (`git stash` entry "maintainer-wip-marketplace-backlog-id042"), branched `feat/verify-by-execution` off `master`.
- Why: master already has every dependency (implementation-notes precedent, verify.md, test-meta.sh; only the codebase-memory hook is unmerged), so an independent PR off master is cleaner than stacking on an unmerged feature and entangling someone else's WIP.
- Alternatives considered: branch off `feat/codebase-memory-index` (rejected: mixes two unmerged features in one PR lineage); commit the maintainer WIP along (rejected: not mine to commit).
- Impact: maintainer WIP is preserved in the stash and must be popped onto their branch; not lost.

## 2026-06-06 23:00 Scoped to the recording dimension, NOT ID-020
- Context: ID-020 ("verifiers are presence-only") looked like the home for this work.
- Decision/Change: framed the feature as the *recording/execution* dimension of verify-arm hardening and explicitly did NOT claim to close ID-020.
- Why: ID-020 is narrowly the removal-class absence check (assert deleted content is gone), and `agents/task-verifier.md` Section 1b already implements that. Conflating them would be an overclaim. Caught + corrected an initial "closes ID-020" line in PHILOSOPHY + the convention doc + the test header.
- Alternatives considered: mark ID-020 shipped (rejected: false); edit the ID-020 BACKLOG row (skipped: avoids scope creep + collision with the stashed ID-042 edit; the Section-1b-vs-BACKLOG drift is flagged to the maintainer instead).
- Impact: honest CHANGELOG; ID-020 stays open as its own concern; a real drift (Section 1b exists but BACKLOG says "presence only") is surfaced for the maintainer.

## 2026-06-06 23:00 Command/agent text + convention doc, no new hook
- Context: PHILOSOPHY's "Guardrails over guidance" tempts a hook to enforce logging.
- Decision/Change: shipped as command/agent text + `docs/verification/README.md` pinned by 8 `tests/test-meta.sh` guards; documented a ship-gate-blocks-on-missing-entry as the deferred enforcement escalation.
- Why: the verification log is produced *structurally* by the verify flow (execute/verify write it), so it does not rely on the LLM remembering , already stronger than advice. Minimum-infra-first: don't add a hook until a real miss proves advice insufficient.
- Alternatives considered: a SessionStart/Stop hook or a ship-gate check now (rejected as premature per the goal's "hook optional" + minimum-infra default).
- Impact: reversible, auditable, dogfoodable; the meta-test suite is itself the executable check (337 -> 345).

## 2026-06-06 23:00 Demonstrated both paths live
- Context: Done requires a live run + the no-check degradation shown for real.
- Decision/Change: `docs/verification/verify-by-execution.md` carries a real `bash tests/test-meta.sh` PASS entry (exit 0, 345/345) AND an honest `[NO EXECUTABLE CHECK]` entry for the subjective PHILOSOPHY-voice aspect; re-ran the logged command and reproduced the verdict (regression check).
- Why: a fabricated no-check would defeat the point; the subjective prose-voice item is a genuine no-mechanical-check case.
- Alternatives considered: manufacture a throwaway no-check task (rejected: dishonest).
- Impact: both the PASS path and the graceful-degradation path are proven on a real artifact in-repo.
