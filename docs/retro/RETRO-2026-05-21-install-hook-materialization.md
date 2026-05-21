# Retro: installer hook-materialization fix (SPEC-025)
Date: 2026-05-21
Sprint: 2026-05-21 (single session)
Spec: docs/specs/SPEC-025-install-hook-materialization.md
PR: #5 (fix/install-hook-links)

## Metrics
- Tasks planned: 3, completed: 3, deferred: 0
- Acceptance criteria: 5/5 met
- Commits: 2 (atomic) -- `68a8ec0` link hooks into the referenced path; `bce5608` in-place handling + SDD docs
- Files changed: 5 (+269 / -7): `install.sh`, `tests/test-meta.sh`, `docs/specs/SPEC-025`, `CHANGELOG.md`, `RUNBOOK.md`
- Tests: meta 213 -> 216, hooks 92/92
- Trigger: a live `SessionStart` hook error ("No such file or directory") on a dev checkout
- Notable: the SDD pass caught a CRITICAL regression that the first commit had already shipped

## What worked
- **Retroactive SDD pass.** Applying `/spec` + a fresh-context review to already-shipped code is what caught the in-place self-referential-symlink regression BEFORE merge. Writing the spec forced a re-read of the README, which revealed the canonical clone-to-`~/.claude/dwarves-kit` layout the first fix would have destroyed. Highest-value move of the cycle.
- **Regression-test-first.** Each guard was proven to FAIL on the buggy installer before being trusted: the original test ran against the pre-fix `install.sh` (all 14 hooks unresolved), and the in-place test reproduced the broken self-symlink. Tests that were never seen red are not trusted.
- **Fast root-cause.** The readiness-hook output plus targeted filesystem checks (`ls ~/.claude/dwarves-kit/hooks`, comparing `KIT_DIR` vs the settings path) pinpointed the missing dir and the `install.sh` gap quickly, no flailing.

## What hurt
- **Fix shipped before the spec.** The first commit (PR #5) carried a critical in-place bug. Spec-first (which here meant re-reading the README) would have surfaced the canonical layout pre-ship instead of post-ship. The fix "looked one-line," which is exactly when the spec gets skipped.
- **Test blind spot.** The original regression test only exercised the out-of-place layout, so it passed green while the documented in-place install was broken. A green test on one layout masked a broken second.
- **Hidden installer coupling.** `install.sh` silently assumed the repo is cloned to `~/.claude/dwarves-kit`; the coupling between `settings.json`'s hard-coded paths and the clone location was undocumented and load-bearing.
- **SSH agent broke the push.** The SSH agent failed mid-cycle ("communication with agent failed"), forcing a fallback to `gh` HTTPS auth. Environment friction, unrelated to the code, but it cost a diagnosis detour.

## Action items
- [ ] **Test all install layouts.** Any `install.sh` change must exercise BOTH in-place and out-of-place layouts. Now pinned by the 3-assertion meta-test; treat as the standing rule for installer work. -- owner: Han
- [ ] **Promote the "new SPEC -> BACKLOG status row" check to a hook (or kit-health line).** This doc-impact step keeps getting missed (missed again this cycle). Evaluate against the PHILOSOPHY section 5 bar (a check earns a hook only when the gap recurs); this is now a recurrence. -- owner: Han
- [ ] **Document dev-checkout install in README.** Add a one-line note to Install Option 2 that `install.sh` now works from any checkout, not only an in-place clone. -- owner: Han

## Kit feedback
- The `safety-gate` hook (once it was actually installed) correctly blocked three `rm -rf $TMP` cleanups in verification commands. Working as designed; the friction is real but the block is right. Worth noting that verification scripts wanting throwaway cleanup must avoid `rm -rf` in the OUTER command (the hook only sees the agent's direct Bash call, not a test script's internal cleanup).
- Retro-file naming is inconsistent across sources: the `retro` skill body says `RETRO-[date].md`, its description says `docs/retro/RETRO.md`, and CLAUDE.md / WORKFLOW say `docs/retro/v<version>.md`. The repo's actual convention is `RETRO-YYYY-MM-DD-<slug>.md`. The three should be reconciled to the actual convention (candidate ID for the backlog).
- The doc-impact map in WORKFLOW is genuinely useful as a retro checklist; it caught the BACKLOG-row gap that prose review would have missed.

## Feed forward
- The "test all install layouts" rule is encoded in `tests/test-meta.sh`; no CLAUDE.md change needed.
- Two candidates for `_meta/BACKLOG.md` (deferred: that file holds uncommitted SPEC-024 WIP, so not edited here): (1) promote the new-SPEC-BACKLOG-row check to a guard; (2) reconcile the retro-file-naming inconsistency across the skill / CLAUDE.md / WORKFLOW.
- SPEC-025 `Status:` flips VALIDATED -> SHIPPED on PR #5 merge (DEC-005).
- No new ADR (the symlink mechanism is an instance of the existing `commands/` link pattern, not a new decision).
