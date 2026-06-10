# Retro: the closed-loop README arc + the CI portability bug lane

Date: 2026-06-10
Cycle: PR #49 (doc lane: README closed-loop reframe) + PR #51 (bug lane: master CI fix), one session, ~1h05 from first commit to both merged.
Scope: this session's arc only; the quality wave (SPEC-054..069) has its own retro (`RETRO-2026-06-10-quality-wave.md`) and its misfires are not re-dispositioned here.

## Metrics

- 2 PRs merged, 8 commits, 6 files touched, 3 backlog rows queued (ID-060/061/062).
- Doc lane: 1 doc-verifier pass, FAIL:fixable with 4 findings, all fixed pre-merge.
- Bug lane: 2 root causes, 2 one-line fixes, 0 guess-fix iterations, CI green on first post-fix run.
- Master went red -> green inside the same session that found it.
- Suites at close: 316 hooks + 426 meta, green on both platforms.

## What worked

- **The verifier/worker separation earned its keep, on its author.** The README draft
  preaching "never the agent grading its own homework" contained 4 enforcement overclaims;
  a dispatched read-only doc-verifier caught all 4 (most phase gates are advisory; only the
  four hard stops block). Structural tests (426 meta) could never have seen these; only a
  claims-vs-code reader could. The irony is the lesson: the author agent passed its own
  re-read, the separate verifier did not.
- **Debug-loop Phase 0 (feedback loop first) made the bug lane boring, in the good way.**
  A 1-second deterministic repro per cause (`/bin/bash` 3.2 for stack-merge, ubuntu:24.04
  container for the script(1) flavor) meant root cause landed before any edit, both fixes
  were one-liners, and CI confirmed on the first run. The negative control was executed for
  real (revert -> RED -> restore -> GREEN, both bugs) and recorded in
  `docs/verification/ci-env-tests.md`.
- **Worktree isolation across three live strands.** The main checkout (wave), the doc PR,
  and the fix PR never touched each other's state; the only cross-branch friction was data
  (one backlog ID), not git.

## What hurt

- **The operator self-skipped verification artifacts twice, and only the human caught it.**
  (1) The doc lane initially skipped the doc-verifier dispatch ("claims are just re-words");
  (2) the bug lane initially left the acceptance evidence in the gitignored
  `.claude/debug/` ledger with no committable record. Root pattern: both tasks entered
  through conversation, so phase 0 ran through an external skill (content-spec) or the
  debug skill directly, and `proof-gate.sh contract` was never invoked at intake; nothing
  mechanical reminds at PR time. ID-062 queues the warn.
- **Single-counter backlog IDs collide under concurrent branches.** The wave took ID-059 on
  master while PR #49 held ID-059 on its branch; git merged cleanly (different table rows),
  so the duplicate was a semantic conflict only a human or a uniqueness check would see.
  Renumbered by hand this time.
- **`gh` GraphQL intermittently 401s on this machine** (pr create, pr merge, pr checks)
  while REST calls on the same token succeed. Cost several mid-flow retries; every
  GraphQL-backed step ended up on a REST fallback. Environment quirk, not kit scope, but it
  will bite any scripted ship step that shells out to `gh pr ...`.
- **Tests written against the dev environment, and a red-CI merge let them land.** Both CI
  failures were dev-vs-runner divergence (brew bash 5 vs /bin/bash 3.2; BSD vs util-linux
  script). The wave merged while CI was red, so the breakage sat on master for ~50 minutes
  and showed up as inherited red on an unrelated PR. Nothing in the repo requires green
  checks to merge.

## Action items

- [x] ID-062 queued: /kit:ship warns when a behavioral/stateful run opens a PR without a
  `docs/verification/<slug>.md` record (warn-not-block).
- [x] ID-060/061 queued: doc-loop standalone-revision entry path; proof-gate "behavior"
  keyword false positive (+ regression test).
- [ ] Enable required status checks on master (branch protection) so a red CI cannot merge;
  the wave's red merge becomes impossible rather than impolite. Owner: Han (repo settings;
  one-time, ~2 minutes).
- [ ] Backlog ID uniqueness guard: a one-line check in `tests/test-meta.sh` (duplicate
  `ID-NNN` in BACKLOG.md fails) so the next concurrent-branch collision is caught by CI,
  not by eyeballs. Owner: next kit session; candidate to ride ID-059 (rid standardization).
- [ ] Investigate the `gh` GraphQL 401 (keyring token retrieval under the sandboxed shell
  is the prime suspect). Owner: Han's ops backlog, outside the kit.

## Telemetry dispositions (Step 1d contract)

- `LANE-CHECK downgrade chosen=tiny suggested=normal` (README rewrite): **accepted noise.**
  Deliberate: the task is type=doc and ran the doc loop (content brief -> rewrite ->
  doc-verifier); the floor check compares against code lanes by design and warned correctly.
- `readme-loop-reframe` + `ci-env-tests` untracked (no START): **accepted noise with a
  pointer.** Both entered via conversation, not `/kit:assign`, so no START record exists;
  the structural half (rid = branch slug everywhere, START derived at intake) is already
  queued as ID-059 and this retro adds no second row.
- Wave misfires (spec-061/062/063 boardless, shipped-incomplete): out of scope here,
  owned by `RETRO-2026-06-10-quality-wave.md`.

## Kit feedback

- `commit-format` hook counts a multi-line single `-m` as one subject; correct behavior,
  but the error message could hint "use a second -m for the body" to save the retry.
- The doc-type loop has no described entry for standalone revisions (ID-060) and nothing
  invokes `proof-gate.sh contract` when phase 0 runs through a non-kit skill; the two
  together are exactly how the self-skip pattern above slipped through.
- Decision-capture check (Step 1c): no unrecorded ADR-bar decision this cycle; the renumber
  rule (IDs are never reused; renumber the unmerged side) is already the board's documented
  convention, and the REST fallback is tactical.
