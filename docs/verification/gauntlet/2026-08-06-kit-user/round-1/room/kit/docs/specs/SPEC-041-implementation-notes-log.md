# SPEC-041: Implementation-notes log during /kit:execute and /kit:next

Status: SHIPPED
Lane: tiny
Backlog: ID-041
Branch: main (shipped backfill; built directly on the maintainer's tree, then SDD-documented)

## Problem

When a worker subagent implements a task under `/kit:execute` (or a contractor drives a task picked by `/kit:next`), it routinely makes decisions the spec did not pin down: a storage shape, a library pick, an error contract, a naming choice. It also occasionally deviates from the spec, hits a tradeoff worth surfacing, or discovers a constraint the spec missed.

Today, those decisions land in the commit message body (if the worker is disciplined), in the orchestrator's final report (if the verifier surfaces them), or nowhere (most often). At PR-review time the reviewer cannot tell off-spec decisions from spec-mandated ones without re-reading every commit. At `/wrap-session` time the LAB_LOG entry has no anchor to point at. At retro time the cycle's actual decision surface is lost.

The kit ships specs as the source of truth for what gets built, but has no equivalent record for what the build chose where the spec was silent.

## Solution

During any implementation or trial work, the worker maintains `docs/implementation-notes/<spec-slug>.md` with one entry per off-spec moment. Five-bullet entry shape (Context, Decision/Change, Why, Alternatives considered, Impact). One file per spec, not a global running log, so the trail is scoped to the build it belongs to. Markdown only (no `.html`), consistent with the rest of the kit's doc surface.

Three insertion points, smallest-surface-first:

1. **`commands/execute.md` worker template**: a new bullet under `## Rules` instructs the worker to append entries as they go. The reporting requirement at `## When done` asks the worker to name the file path and entry count, so the orchestrator can surface it. The final execution-summary block at `### Step 4: Completion` carries the implementation-notes line, and the `/kit:ship` recommendation reminds the lead to include the path in the PR body.
2. **`commands/next.md` Step 4 hand-off**: a reminder to the contractor that the file is part of the deliverable, plus a one-time scaffold (create the file with a header pointer to the spec if it does not exist) so the implementor only has to append.
3. **The user's global `CLAUDE.md`** (out-of-repo, in the maintainer's dotfiles overlay): the same rule under `## When implementing from specs`, so ad-hoc "implement X" framings outside the kit also fire it. This pairs with the kit changes; the kit alone covers only `/kit:execute` + `/kit:next`, and the maintainer wanted the rule active in any implementation framing.

Empty-case clause: if a build runs end-to-end with zero off-spec moments, the worker still writes a single `No deviations from spec; matches <spec-path> verbatim` entry. This makes the absence intentional rather than forgotten, the same way the spec's `## Open questions` block names a "(none)" terminator instead of being silently omitted.

The file is for the human reviewer (PR body + `/wrap-session` LAB_LOG line), not the verifier. The worker's PASS verdict does not depend on the file's presence; the lead carries the contract at convergence.

## Scope

In:
- `commands/execute.md` worker template (Rules + When done + Completion summary block).
- `commands/next.md` Step 4 (hand-off message + one-time file scaffold).
- The pinning meta-tests in `tests/test-meta.sh`.
- This SPEC + the CHANGELOG entry + the BACKLOG row.

Out:
- No new agent, no new command, no behavior change to the verifier pipeline.
- The orchestrator does NOT auto-create the file (the worker or `/kit:next` does); the orchestrator only surfaces it in the summary.
- No machine-readable schema on the entries; markdown shape is the contract. A reviewer reads them, a tool does not parse them.
- No enforcement at the ship gate. The PR body recommendation is operator discipline, not a hook. (Future: if drift is observed, consider a soft check that the PR body mentions `docs/implementation-notes/`.)
- The out-of-repo dotfiles overlay change to `~/.claude/CLAUDE.md` lives with the maintainer's dotfiles repo (commit 3bc78eb), not here. The SPEC names the pairing for traceability; the kit cannot test or own the dotfiles surface.

## Tasks

- [x] `commands/execute.md`: add an "implementation-notes log" bullet under `## Rules` in the worker prompt; require the worker's `## When done` report to name the file path + entry count; carry an `Implementation notes:` line in the orchestrator's `### Step 4: Completion` execution-summary block; nudge the `/kit:ship` recommendation to include the path in the PR body. (commit 2dd80b9)
- [x] `commands/next.md`: add a hand-off reminder in `### Step 4: Hand off` so the dispatcher names the rule when handing the task to the implementor, and create the file (header only) before handing off so the implementor only appends. (commit 2dd80b9)
- [x] (lead, at convergence) `tests/test-meta.sh` guards: pin that (a) the worker template carries the implementation-notes rule, (b) the worker's "When done" reporting names the implementation-notes path, (c) the orchestrator's final summary block names the implementation-notes file, (d) the `/kit:next` hand-off carries the reminder. Hands-off for the worker.
- [x] CHANGELOG entry under `## [Unreleased]` `### Added`.
- [x] `_meta/BACKLOG.md` row for ID-041 with status `shipped`.

## Verification

`bash tests/test-meta.sh` and `bash tests/test-hooks.sh` still pass; the four new meta guards land green. A read of `commands/execute.md` shows the worker template's `## Rules` block carries the implementation-notes bullet, the `## When done` block names the path + entry count, and the orchestrator's `### Step 4: Completion` block surfaces the file. A read of `commands/next.md` shows the `### Step 4: Hand off` block carries the reminder + the scaffold step.

## After state

- `commands/execute.md` worker template: the implementation-notes rule is part of the worker's operating rules; the worker's completion report names the file; the orchestrator's execution summary carries the path; the ship recommendation nudges the lead.
- `commands/next.md` Step 4: the hand-off message names the rule; the scaffold step creates the file header before handing off.
- `tests/test-meta.sh`: four new guards pin the rule's presence on both `commands/execute.md` (three sites) and `commands/next.md` (one site), so the rule cannot regress silently.
- `_meta/BACKLOG.md` Active queue: ID-041 row with status `shipped` and the commit refs.
- `CHANGELOG.md` `[Unreleased]` `### Added`: a one-line entry naming the spec + the three insertion points + the dotfiles pairing.

## Touches

- `commands/**`
- `tests/test-meta.sh`
- `docs/specs/**`
- `_meta/BACKLOG.md`
- `CHANGELOG.md`

(All commands/* edits are scoped to the two named files; the lead-owned shared surfaces `tests/test-meta.sh`, `_meta/BACKLOG.md`, and `CHANGELOG.md` are written at convergence per the WORKFLOW.md hands-off list.)

## Decisions

(Decisions made while shipping that the spec was silent on. The SPEC-041 implementation-notes file would normally hold these; recording inline here because the SPEC itself is the backfill artifact.)

- **File per spec, not a global running log.** A `docs/implementation-notes/<spec-slug>.md` scope keeps the entries with the build they belong to; a single `implementation-notes.md` would mix unrelated decisions and force a reviewer to filter by date. The same shape as `docs/specs/` and `docs/decisions/`: one file per artifact, indexed by name.
- **Markdown only, no `.html`.** The original prompt allowed either; the kit's doc surface is pure markdown everywhere else, and `.html` would silently flow past `grep` / `rg` and would not render in GitHub the same way. One format, less drift surface.
- **Empty case writes a `No deviations` entry, not nothing.** A missing file is ambiguous (forgotten? no deviations? not yet started?); a one-line entry is unambiguous and costs nothing.
- **`/kit:next` scaffolds the file; the worker appends.** Splitting creation from appending means the worker's first entry is a real entry, not a header write; and the dispatcher already opens the spec in the hand-off message, so it is the cheapest point to also touch the notes file. The orchestrator under `/kit:execute` does NOT auto-create, because its workers are dispatched per task and each one would race the same file create; the worker handles the create-if-absent inside its own write.
- **The PR body + `/wrap-session` LAB_LOG line are operator surfaces, not hook-enforced.** Adding a ship hook that refuses without `docs/implementation-notes/` in the PR body would lock the rule in but inverts "orchestration first, hook as fallback" (the ID-036 layering principle). The SPEC names the surfacing as operator discipline; if drift recurs, revisit as a soft kit-health line, not a hard hook.
- **The dotfiles overlay carries the same rule, paired but not nested.** The kit's rule covers `/kit:execute` + `/kit:next`. The user's global `CLAUDE.md` (in the maintainer's dotfiles) covers ad-hoc "implement X" / "build out Y" framings outside the kit. The two surfaces are paired in commit messages and in this SPEC, but the dotfiles surface is not in the kit's repo and the kit cannot test it.

## Why a backfill SPEC

This work shipped before the SPEC was written, against the kit's standard `/kit:assign` -> `/kit:spec` -> `/kit:execute` flow. The maintainer requested SDD applied retroactively (`apply SDD back to make sure they are well documented and aware`). The SPEC therefore documents the after-state and the decisions, not a build plan; the tasks are listed as `[x]` with commit refs, the lane is `tiny` (single-edit, well-bounded), and the verification is the meta-test guards landing green. This matches the `tiny`-lane shape: small surface, no behavior risk, the discipline that matters most is the pinning meta-test so the rule cannot regress.
