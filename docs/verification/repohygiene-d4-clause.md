# repo-hygiene detector 4: recorded runs for the clause-scoped budget read

Board row: ID-831. Run id: `repohygiene-d4-clause`. Lane: full. Type: behavioral.
Full record: `lib/repohygiene/docs/proof-of-done.md` (co-located with the module, per
SPEC-016). This file is the ship-gate's recorded run and rollback note.

## What changed

Detector 4 read a budget from any doc line that named the log and carried a line count. Naming
the log and carrying a count are not the same as stating a budget FOR it. It now reads a number
only from a clause that names the log AND carries an `<N> ... lines` phrase, and only the N
inside that phrase.

## Recorded runs

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 0 | 98/98 passed, 0 failed (91/91 before this branch) |
| 2 | `bash tests/run-all.sh` | - | run by CI on ubuntu-latest and macos-latest; see the PR's checks |

## Live run of the primary flow

The bug was found by running the scanner against `dfoundation`, whose `_meta/INGEST_LOG.md`
drew a FIX verdict against a threshold belonging to a different file.

```
Command: bash lib/repohygiene/repohygiene.sh scan --repo <dfoundation> --detectors 4

Before:  4  FIX  _meta/INGEST_LOG.md  total=187 lines vs threshold 100; busiest month
                 2026-05 at 18 vs per-month 0001; source docs/decisions.md:57 ...
After:   4  UNSURE  _meta/INGEST_LOG.md  total=201 lines, busiest month 2026-05 at 18;
                 no documented threshold found in this repo, so there is nothing to
                 judge against
Verdict: PASS. The repo documents no INGEST_LOG budget, so UNSURE is the correct verdict,
         and it matches the one reached by hand when the false positive was found.
```

The 100 came from `docs/specs/SPEC-019-folder-simplification.md:27`:

> Slim `HANDOFF.md` to <=100 lines (status-only; journal content stays in INGEST_LOG).

That budget is HANDOFF.md's. INGEST_LOG is named only as where the journal content goes. The
`0001` per-month threshold came from digit runs in two unrelated `docs/decisions.md` rows.

### True positives must survive

A fix that suppressed every source would also pass the above, so the same command was run
against a repo whose budget is real and whose log is over it.

```
Command: bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit> --detectors 4
Exit:    0
Result:  4  FIX  _meta/LAB_LOG.md  total=997 lines within threshold 2000, but month
            2026-09 at 530 vs per-month 200; source CLAUDE.md:29 "- **Trim when it
            crosses thresholds.** If LAB_LOG exceeds ~2000 lines or any single month
            occupies more than ~200 lines ..."
Verdict: PASS. Both numbers still read correctly from one sentence, and the genuine
         FIX still fires.
```

Across the five repos of the 2026-09-11 sweep, detector 4 emits 1 finding (dfoundation's
honest UNSURE) where it previously emitted 1 false FIX. `family-office` and `console-labs`,
whose budgets were written during that sweep, still read them and stay clean.

## Negative controls

Each control disables ONE half of the narrowing and re-runs the suite. The tree was restored
to `876c66a` after each and the suite returned to 98/98.

```
Control 1: the clause must name the log  ->  `if (index(seg, base) == 0) continue` becomes `if (0) continue`
Command:   bash tests/test-repohygiene.sh
Exit:      1
Verdict:   RED, as required. 96/98, failing exactly
           "a sibling's budget on the same line is not this log's budget" and
           "the sibling's number never becomes a threshold".

Control 2: the number must sit in an N-lines phrase  ->  the phrase regex loses its `[^0-9]*lines` tail
Command:   bash tests/test-repohygiene.sh
Exit:      1
Verdict:   RED, as required. 96/98, failing exactly
           "a line with digit runs but no N-lines phrase is not a budget source" and
           "a loose digit run in prose never becomes a per-month threshold".

Restore:   git checkout lib/repohygiene/repohygiene.sh
Command:   bash tests/test-repohygiene.sh
Exit:      0
Verdict:   PASS, 98/98 passed, 0 failed.
```

The two controls fail DISJOINT assertions, which is what proves the two halves are tested
separately rather than one masking the other.

Control 2 did not bite on the first attempt, and the miss was a fixture defect, not a missing
rule: the noise line's `3400 lines` sat in the same clause as the log's name, so it qualified
under both the fixed and the mutated code, and the assertions were written against numbers the
scanner never emitted either way. The `N lines` phrase now sits fenced in its own clause, and
the assertions test what the evidence field actually says.

## In-suite controls

Two of the seven new assertions exist only to catch a narrowing that rejects too much:

- the same sentence is rewritten so the budget IS the log's own, and the FIX must appear with
  `total=250 lines vs threshold 100`;
- a genuine budget on a different line from the noise must still apply, at
  `total=250 lines vs threshold 200`.

## Rollback

`git revert` the commits on this branch. Detector 4 returns to reading any line that names the
log and carries a count, which restores the borrowed-threshold FIX and nothing else. The
scanner is read-only by contract, detector 4 is report-only in every case, and this change only
narrows which numbers it will read.
