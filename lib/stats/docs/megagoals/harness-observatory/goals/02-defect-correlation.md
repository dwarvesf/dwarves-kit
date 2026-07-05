# Sub-goal 02: defect-correlation (`git_fixes` adapter + the retrospective control arm)

**Merge policy:** auto
**Time budget:** 1.5-2 hours of loop work
**Proof:** full reviewable proof: run-table on real repo history; golden fixture (a known sub-goal with a later fix() on its files -> flagged; a clean one -> NOT flagged, the FP NC); coverage-delta row. Canonical proof index updated.
**Design:** bearing
**Depends on:** 01
Model: sonnet
**Branch:** `feat/lo-defect-corr`
**PR base:** `feat/lo-gate-yield`
**Over-test: yes** (flagship; the FP NC is load-bearing)

## Outcome

The control arm without new runs: a `git_fixes` adapter (the tool's FIRST git-sourced table: `sha, files, ts, subject`, read-only, same delete-and-rematerialize contract) + `ledger defect-correlation`: JOIN each shipped run's gate coverage (`kit_gates`) against later `fix()` commits touching the same files. A gate that ran+passed but a fix followed on its files = a MISS, queryable.

Covers: ID-245 change 3.

## Quality bar

Retrospective honesty: correlation is evidence, not proof of causation; the command's output labels say "fix-followed" not "gate-failed". Windowing (how long after ship counts) is an explicit tunable with a sane default, not a buried constant.

## How to close the loop

- Golden fixture: committed mini git-history fixture (or a fixture table) with one known miss + one clean run; tests assert both classifications.
- FP NC (load-bearing): the clean run with NO later fix must NOT be flagged, asserted.
- Real run: `uv run ledger defect-correlation --table` over ops-toolkit + dwarves-kit history; capture stdout as the run-table.
- Over-test: edge cases (merge commits, renames, fix commits touching unrelated files, multiple fixes same file); coverage-delta row recorded.
- Kit lane + gate-ledger records before push.

**Done =** both fixture classifications asserted green AND the real-history run captured, with the windowing default documented and the coverage-delta row committed.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 03-deviation-rate (JOINs this adapter); name the git_fixes table columns + window default. 3. `DECISIONS.md`: append the windowing decision + rename handling. 4. EXIT.

## Scope edges

**In:** new git adapter module, cli command, tests, proof docs, all under `tools/ledger-observatory/`.
**Out:** impl_notes (03), anomalies (04).
**Not:** git WRITE operations of any kind; per-line blame attribution (file-level only, v1).

## Where to look

`docs/benchmark-followup.md` change 3; `adapters.py` for the adapter contract shape; `git log --format` plumbing from the repo's other tools if any.

## PR body

`git_fixes` adapter + `defect-correlation`: gate-coverage x later fix() commits, the retrospective control arm (zero new runs). Stacked on the kit_gates PR; review after it. Verification per proof-of-done (fixture both-ways + real run + coverage-delta). Covers ID-245 (2/3).

## Notes

