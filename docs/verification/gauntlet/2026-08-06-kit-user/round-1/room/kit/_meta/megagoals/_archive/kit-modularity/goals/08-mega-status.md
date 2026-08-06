# Sub-goal 08: mega-status

**Merge policy:** auto
**Time budget:** 3-5 hours of loop work
**Proof:** run-table, `mega status <slug>` over the REAL megagoals corpus renders a per-sub-goal rollup that RECONCILES the ROADMAP claim against git truth (merged-PR verify, worktree commit-count, open-PR), with drift flags. Rung 2 (named NCs, load-bearing): (NC-1) a fixture mega whose ROADMAP says `[x] ... PR #999 merged deadbeef` but PR #999 is not merged MUST flag `CLAIM-UNVERIFIED`, never green-wash; (NC-2) a fixture whose box is `[ ]` but a worktree exists with 0 commits MUST flag `STALLED` (the SG-02-this-session case, the whole point); (NC-3) a fixture whose box is `[ ]` but its PR is merged MUST flag `MERGED-UNCHECKED`. COVERAGE-DELTA. Satisfies the F bar (usage doc + firing point).
**Design:** bearing (which drift classes earn a flag vs stay quiet; whether `mega` earns a grouped standalone entry per SG-03's 2+-verb rule, or `status` rides under `board`; the board-render rollup column format)
**Depends on:** 01 (collapsed modules), 03 (the standalone `<subsystem> <verb>` surface this adds a verb to). Parallel to 04/05/06. 07 reconciles the new verb into the final surface.
Model: sonnet
**Branch:** feat/kitmod-08-mega-status
**PR base:** master (rebased after 03)

## Outcome

A `mega status <slug>` reader that answers "what is the real progress of this mega-goal" WITHOUT trusting the roadmap's own prose. It reads `_meta/megagoals/<slug>/ROADMAP.md` (claim: the `- [x]/[ ]/[~]` sub-goal lines + any `PR #N merged <sha>` tail) and cross-checks each against git truth:

- `[x] ... PR #N merged <sha>` -> verify PR N is actually merged (`gh pr view`) and the sha is real. Consistent -> `✓`.
- `[ ]` + a branch/worktree carrying commits, or an open PR -> real WIP (`~`).
- `[ ]` + a worktree that exists but has **0 commits** vs base -> `STALLED` (a dispatched-but-empty run; catches the exact HANDOFF-vs-reality lie this session hit).
- `[ ]` + its PR merged -> `MERGED-UNCHECKED` (roadmap lagging reality).
- `[x]` claim whose PR is NOT merged -> `CLAIM-UNVERIFIED` (roadmap ahead of reality / green-wash).
- `[~]` rehomed/superseded -> informational, no flag.

Plus a one-line rollup (`N/M ✓  ⚠ DRIFT`) suitable for `board render` to show against each `megagoals:` origin row, so the mega's status sits on the kanban next to backlog items ("do them together").

## Quality bar

A DUMB reader that only echoes `[x]/[ ]` is worthless here: it would have repeated this session's "SG-02 running" lie verbatim. The value IS the reconciliation. Truth beats the roadmap's prose every time; when they disagree, the flag names which side is stale. Bash + `gh` only (a keyed diff over a handful of sub-goals, not analytics) -- no DuckDB, per the kit's bash-first rule; DuckDB stays the `stats` exception. NOT a live-process monitor: whether a `claude` session is running RIGHT NOW is the runner's `RUNNER_DONE`/journal job; `mega status` points at the journal, it does not poll processes.

## How to close the loop

- Add the reader as a `mega`-module verb (`status`), ~80-120 lines bash. Parse the ROADMAP sub-goal block; per line extract box-state + PR#/sha; gather git truth (`gh pr view N --json state,mergeCommit`, `git worktree list --porcelain`, per-worktree `git rev-list --count base..HEAD`, `gh pr list --state open`); classify per the drift table above; render.
- Read the megagoals dir from CONSUMER config (`_meta/megagoals/` in ops-toolkit) via `REPO_ROOT`/env, exactly like `board`/`queue`; NO personal path committed to the kit.
- Emit the rollup line in a `board`-consumable form; wire it into `board render` as a column for `megagoals:` origin rows (the SG-03 standalone-verb surface makes `mega status` callable; board composes it).
- Firing point (F-bar): the `board render` rollup column + a `board status`/SessionStart composition line so mega drift is SURFACED, not pull-only (adopts runner-fastpath NOTES proposal #3).
- NCs: the three fixture megas above (CLAIM-UNVERIFIED / STALLED / MERGED-UNCHECKED), each a mktemp roadmap + stub `gh`/`git` (stub-injected binaries, no real API calls, per the suite convention).
- Usage doc co-located: `docs/proof/kitmod-mega-status.md` + a usage blurb in the module.

Kit-adopted: record build + review via `bash lib/gate-ledger.sh`.

**Done =** `mega status <slug>` reconciles roadmap-vs-git and flags the three drift classes (proven by NC-1/2/3), `board render` shows the mega rollup against `megagoals:` rows, and mega drift has a passive firing point, captured in `docs/proof/kitmod-mega-status.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: only 07-reconcile remains (it must now also cover the `mega status` verb in the never-diverge mirror check).
3. DECISIONS.md: record the drift-class taxonomy + the `mega`-grouped-entry-vs-`board`-verb call.
4. Report in records, EXIT.

## Scope edges

**In:** the `mega status <slug>` reconciler; its drift-class taxonomy; the `board render` rollup column for mega rows; a passive firing point; the three NCs; the usage doc.
**Out:** live-process monitoring (runner journal owns it); Hermes mirror of the rollup (rides SG-07 board-bridge / a later mega); mutating the roadmap (read-only; conductor still transcribes box flips).
**Not:** parsing roadmap PROSE for status (only the structured `- [ ]` block + PR tail); trusting HANDOFF.md as a source of truth (it is a claim to be checked, never the answer); adding DuckDB; touching `/kit:*` slash commands.

## Where to look

the existing `lib/board/board.sh` + `parse-board.sh` (the render + parse shape to mirror), `board-mirror.sh` (how a `megagoals:<repo>/<slug>` origin is already recognized), a real ROADMAP.md sub-goal block (the `- [x] ... PR #N merged <sha>` grammar to parse), the runner-fastpath NOTES `## Proposed additions` (proposal #3 passive-surface, #4 drift mode).

## PR body

`mega status <slug>`: reconcile a mega-goal's ROADMAP sub-goal claims against git truth (merged-PR verify, worktree commit-count, open-PR) and flag drift (STALLED / MERGED-UNCHECKED / CLAIM-UNVERIFIED), plus a `board render` rollup column so mega status sits on the kanban beside backlog items. Bash + `gh`, no DuckDB.

Verify: run-table over the real corpus; NC-1 CLAIM-UNVERIFIED, NC-2 STALLED, NC-3 MERGED-UNCHECKED (stub-injected `gh`/`git`). Proof: `docs/proof/kitmod-mega-status.md`. Stacked on #<SG-03>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes

Provenance: added 2026-07-05 (Han) after a live session where the SG-02 HANDOFF claimed "running" while the `kitmod-02` worktree sat at 0 commits, empty. The manual reconciliation to catch that (grep ROADMAP, walk worktrees, verify PRs) is precisely this verb's job. Folded into ID-277 rather than a parallel tool because `mega` becoming a standalone `<subsystem> <verb>` IS SG-03's remit and modularity is the right home (avoids the ID-240 pre-scaffold anti-pattern).
