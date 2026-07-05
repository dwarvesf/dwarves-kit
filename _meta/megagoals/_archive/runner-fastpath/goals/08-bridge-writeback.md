# Sub-goal 08: bridge-writeback

**Merge policy:** gate (an agent-driven channel writing into the git SoT is exactly what Han must eyeball once before it runs routinely)
**Time budget:** 2-3 hours after 07
**Proof:** OVER-TEST: test-plan + run-table + six named negative controls + ONE end-to-end round-trip capture against FIXTURES ONLY (a card move on a dev-home fixture board -> `board writeback` -> the status flip lands as a branch + commit diff in a THROWAWAY git repo fixture) + the rung-4 captured `VERDICT: SECURE` + COVERAGE-DELTA row. The worker NEVER moves real cards, NEVER writes the real `_meta/BACKLOG.md`, NEVER merges/closes anything: the first REAL round-trip is Han's own action after his gate review (advisor P5 CRITICAL).
**Design:** bearing (the conflict rule + changeset semantics are the heart; wrong = silent SoT corruption). The spec MUST carry a `## Design` block: the state diagram (mirror snapshot -> hermes delta -> changeset -> PR).
**Repo:** dwarves-kit (extends the kit `board` command; hand-made worktree; stacked on 07).
**Depends on:** 07 (stacked).
Model: sonnet
**Branch:** `feat/board-writeback` (dwarves-kit)
**PR base:** `feat/board-mirror`
**Config seam:** the opted-in board (`ops-toolkit` for v1) + the target BACKLOG.md path are CONSUMER config; the kit code stays generic.

## Outcome

the kit `board` tool gains a `writeback` subcommand (bash): changes Han makes on the Hermes board flow back into git as reviewable commits. It diffs the Hermes state against 07's mirror snapshot, builds a changeset, and applies it to `_meta/BACKLOG.md` via a `chore/board-sync` branch + PR. v1 scope: STATUS MOVES ONLY, ops-toolkit's board ONLY.

## Quality bar

BASH, no Python/DuckDB. The SoT stays git; one writer per direction. **Conflict rule (load-bearing): a Hermes-side edit applies ONLY if the row's `row_hash` still equals the mirror-snapshot value; otherwise the edit is SKIPPED, reported, and the card is refreshed from git on the next mirror. Git wins, always.** Commits are attributed (`actor=hermes` in the body), land on a `chore/board-sync` branch as ONE PR per sync run, NEVER a direct push to main. Status values must be legal `backlog.sh` states; anything else is rejected with a reason. **Missing/corrupt snapshot -> writeback REFUSES ALL edits, explicit error, exit nonzero; "no snapshot" must NEVER degrade to "no conflicts, apply everything".**

## How to close the loop

- `board writeback [--dry-run]`: read Hermes boards (`hermes kanban list --json`) + the 07 mirror snapshot; changeset = rows whose Hermes status differs; validate (legal state, opted-in repo, hash match); apply to `_meta/BACKLOG.md` (bash edit of the Status column of matched rows only); branch + commit + `gh pr create` (auto-merge NOT enabled); refresh the snapshot after merge.
- Wire the `writeback)` dispatch case into `_meta/board` + `_meta/board-all` (same thin-exec pattern as 04/07; existing behaviour unchanged).
- Tests run against fixture snapshots + a stubbed `HERMES_BIN` and a THROWAWAY git repo fixture; NO real PRs from the suite.

Named negative controls (each a test):
1. Hash mismatch (git row changed since mirror) -> edit SKIPPED + reported; file untouched.
2. Illegal target status (not a `backlog.sh` state) -> rejected with reason; file untouched.
3. Empty changeset -> zero commits, zero branches, "0 changes" line (honest-empty).
4. A card from a non-opted-in repo appearing in the Hermes delta -> refused with reason (defense in depth on top of 07's mirror filter).
5. Mirror snapshot MISSING or corrupt -> writeback refuses ALL edits, explicit error, exit nonzero (the silent-SoT-corruption path this design exists to close).
6. TWO-WRITER coexistence (cc-backlog `add-backlog` also writes BACKLOG.md): a row APPENDED to BACKLOG.md AFTER 07's snapshot (not in the snapshot) is left UNTOUCHED by writeback -- it only rewrites the Status column of rows it matched by `row_hash`; a fixture with a post-snapshot appended row proves the append survives byte-for-byte. Plus: the `chore/board-sync` branch bases on current `main` (not a stale checkout) so a concurrent `add-backlog` append is preserved, never clobbered.

Round-trip leg, FIXTURES ONLY (recorded in proof-of-done): move one card on a dev-home fixture board, run writeback against a THROWAWAY git repo fixture carrying a copy of the kanban shape, capture the branch + commit diff (a single status flip). No real board, no real BACKLOG.md, no PR opened by the suite, nothing merged/closed by the worker. Document the exact one-command sequence Han will run for the FIRST real round-trip in the PR body.

**Done =** tests green with the six NCs AND the fixture round-trip diff captured in proof-of-done AND the rung-4 `VERDICT: SECURE` AND this PR opened and HELD (gate banner: NEEDS APPROVAL; do not merge).

Kit-adopted repo: record gate-ledger phases before push.

**Rung 4 (SoT MUTATION):** writeback writes the git source of truth, so the Done proof includes a captured `VERDICT: SECURE` from an in-harness `kit:security-reviewer` told to BREAK the conflict rule (force a stale-hash edit through), the snapshot-missing guard (make "no snapshot" apply-everything), the opted-in filter, and the argv-safety of the BACKLOG.md edit + `gh pr create` (no card text through a shell). Frozen diff `git diff feat/bridge-mirror...HEAD` (the stacked parent, NOT main); fail-closed; cap 3 rounds; record `redteam` gate-ledger rows.

## Handoff on completion

1. Flip the ROADMAP box + PR # (open + CI green; the GATE hold governs merging).
2. Overwrite HANDOFF.md: next = convergence gate (or 05 if still open).
3. Append to DECISIONS.md: the changeset format + anything learned about hermes state semantics.
4. Report IN the records, then EXIT IMMEDIATELY.

## Scope edges

**In:** the `writeback` subcommand in the kit `board` tool (bash), snapshot refresh, its docs/proof.
**Out:** new-card writeback, note edits, non-ops-toolkit repos (all NOTES follow-ups pending Han's gate), Notion, cron.
**Not:** auto-merging the sync PRs, bidirectional merge logic beyond the hash rule, editing anything in BACKLOG.md other than the Status column of matched rows, Python, DuckDB.

## Where to look

07's mirror snapshot format (its HANDOFF names the file:line), dwarves-kit `backlog.sh` (legal states), the design doc's "Two-way without the graveyard" section + its 2026-07-05 amendment.

## PR body

- Outcome: staged `board writeback` (bash), Hermes card moves become reviewable BACKLOG.md status commits (v1: status moves, ops-toolkit board).
- Verification: 5-NC run-table + fixtures-only round-trip diff + `VERDICT: SECURE` (inline). GATE: hold for Han.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`. Stacked on #<07 PR>; review after it.

## Notes

- 2026-07-05 architecture change (Han-directed): writeback is a bash subcommand of the one board tool; Python+DuckDB dropped. The advisor P5 CRITICAL (fixtures-only proof, first real round-trip is Han's post-gate action) carries forward unchanged.
