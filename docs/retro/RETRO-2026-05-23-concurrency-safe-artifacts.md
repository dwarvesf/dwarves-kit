# Retro: concurrency-safe per-work artifacts (remove .planning/, review into the spec)
Date: 2026-05-23
Sprint: single session, 2026-05-23 (goal-loop continuation: map -> two threads -> verify -> retro)

## Why
The concurrency model (worktree-per-spec via `/kit:dispatch`, multi-session via the
goal-registry) wants no fixed-name shared file or folder that two goals/sessions could
clobber. Two leftovers still violated that: the legacy `.planning/` spec-location fallback,
and the per-work review artifacts (`REVIEW.md`, the per-lens `REVIEW-*.md`, `TODOS.md`)
written to fixed root paths. The maintainer's instruction: stop using these shared
folders/files; re-point the workflow and commands.

## Decisions (maintainer-chosen)
- **Per-work output -> into the active spec.** Review output now lives in the spec as a
  `## Review` section (replace-not-stack), matching the kit's existing "output that binds
  to a spec lives in the spec" rule for the critique/plan lanes. Fallback when no spec
  exists (reviewing an arbitrary diff/PR): inline in chat, never a new fixed-name file.
- **`.planning/` removed entirely** from every live surface (not just deprecated). `docs/specs/`
  is the sole spec location (ADR-0010); the deprecation window is closed.

## Thread A: remove `.planning/`
- Hooks: dropped the `.planning/SPEC.md` / `find .planning` fallback in context-readiness,
  spec-drift-guard, session-state-save, pre-compact-backup, post-compact-reinject. (`.gsd`
  is a separate GSD-upstream fallback, out of scope, left intact.)
- Commands/agents: stripped the legacy-fallback prose from next, start, task-verifier,
  responding-to-review.
- Docs: CLAUDE.md, MANUAL.md, README.md, PHILOSOPHY.md, architecture.md re-pointed to
  `docs/specs/` (historical/credit mentions reworded to "planning-dir" so no live `.planning`
  token survives; dated ledgers keep it as history).
- Guards tightened: the test-meta STRAY_PLANNING checks now forbid `.planning` ENTIRELY in
  commands/ AND hooks/ and in agents/ (the `grep -vi legacy` exception is gone). The stale
  comment claiming the fallback was "behavior-tested in test-hooks.sh" was wrong; test-hooks
  had zero `.planning` cases, so removing the fallback broke nothing there.

## Thread B: review output -> the spec's `## Review` section
- Writers: `/kit:review` and `/kit:review-team` write a `## Review` section into the active
  spec (replace-not-stack; review-team keeps per-lens `### Security/### Architecture/###
  Test coverage` subsections + `### TODOs`). Inline-in-chat fallback when no spec exists.
- Reader: `/kit:ship`'s review gate reads the verdict from the spec's `## Review` (Step 1,
  Step 1b/4a wording, Step 8 PR body, Source note).
- Detector: `context-readiness` checks the spec for a `## Review` section instead of a root
  `REVIEW.md`; `/kit:start` states 5-7 read the spec's `## Review`.
- Home: spec.md template documents the on-demand `## Review` section (like `## Amendments`).
- Docs: WORKFLOW artifact-placement table + flow-reference (side-flow, DO-NOT-SHIP gate,
  quick-ref) + the critique-lane enumeration; architecture data-flow + state model (review
  is no longer a separate "transient store"); MANUAL review/review-team/ship cards.
- `.gitignore` (kit + hello-spec): dropped the `REVIEW.md`/`TODOS.md` ignore lines (the
  files are no longer produced).
- New guard: `## Review` is pinned across spec.md (home) + review/review-team (writers) +
  ship (reader), same drift-guard shape as `## Test plan`; plus an assertion that no
  command reintroduces a fixed-name `REVIEW*`/`TODOS` root file.

## The one exception (named, not forced)
The pre-spec `docs/specs/DECISION-BRIEF.md` exists before any SPEC-NNN, so it cannot live
in a spec. It stays worktree-isolated, named as the exception in WORKFLOW's artifact-placement
section. The critique lanes (devs-team/visual-team/ui-design) were already spec-first; no change.

## What was NOT touched (scope fence held)
The deliberately lead-owned convergence surfaces stay shared on purpose (the merge boundary):
CHANGELOG, VERSION, BACKLOG, plugin/marketplace manifests, retro release files, test suite.
The worktree/goal-registry/dispatch machinery was not redesigned. No migration tool, no new
command. Ledgers (specs/decisions/retro/research/handoff/absorption, _meta/BACKLOG) keep their
historical `.planning`/`TODOS.md` mentions as point-in-time record.

## Verification
- `tests/test-meta.sh` 311 -> 316 (+5: four `## Review` contract checks + one no-root-file
  assertion), exit 0. `tests/test-hooks.sh` 120/120, exit 0.
- Sweep: zero `.planning` in any live surface (only dated ledgers + the guard file that names
  it); zero fixed-name `REVIEW*`/`TODOS` root file in commands/hooks/agents/live-docs.
- All five hooks pass `bash -n` syntax check after the fallback removal.

## What worked / what to watch
- Two independent threads (path-removal vs artifact-relocation) kept the diff legible; tests
  green after each.
- The new `## Review` guard immediately caught its own edge case: the "NEVER write REVIEW.md"
  prohibition prose tripped the no-token assertion. Reworded the instruction to drop the literal
  filename (the guidance is just as clear without it). A guard that names the thing it forbids
  has to live in tests/ only, which it now does.
- Not committed: multi-feature branch `docs/backlog-reeval` (the doc-consolidation + SPEC-036
  work are also uncommitted); ship structuring is a maintainer call.
