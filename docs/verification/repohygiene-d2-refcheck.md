# repo-hygiene detector 2: recorded runs for the reference check

Board row: ID-832. Run id: `repohygiene-d2-refcheck`. Lane: full. Type: behavioral.
Full record, including the measured before and after across five real repos:
`lib/repohygiene/docs/proof-of-done.md` (co-located with the module, per SPEC-016). This file
is the ship-gate's recorded run and rollback note.

## What changed

Detector 1 proves nothing references a tracked file before flagging it. Detector 2 did the same
job for staging entries and skipped that proof, emitting on age alone. Detector 2 now runs the
same grep, and skips OS artifacts outright.

## Recorded runs

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 0 | 91/91 passed, 0 failed (82/82 before this branch) |
| 2 | `bash tests/run-all.sh` | 0 | 134 suites run, 1 skipped; failures `test-orchestrate-gate-dispatch` and `test-orchestrate-wavefront`, the same two this module's existing proof records as failing identically on master, neither touching anything this branch changes |

## Live run of the primary flow

The primary flow is the scanner against a real repo. Recorded against the five repos of the
2026-09-11 sweep, whose detector-2 findings had already been judged by hand, one at a time,
before this fix existed.

```
Command: bash lib/repohygiene/repohygiene.sh scan --repo <repo> --detectors 2
Exit:    0
Verdict: PASS

         family-office  3 findings -> 0
         trading        1 finding  -> 0
         dfoundation    0          -> 0
         console-labs   0          -> 0
         books          0          -> 0
```

Every dropped row was confirmed live by hand before the fix was written:

| Dropped row | Why it was never decay |
|---|---|
| `_inbox/gay-chong-co-ghe-da-nang.md` | `operations/eldercare-mobility-aid-danang.md:31` names it, by path, as the deliberate home for third-party phone numbers the tracked tree keeps out |
| `_inbox/rename-applied-2026-05-25.log.tsv` | `docs/ingest/drive-dedupe-2026-09-03.md:70` cites it as evidence for a dedupe decision |
| `_inbox/from-hermes/` | The family bot's only writable directory; a nightly job drains it, so old and empty is that job working |
| `_inbox/.DS_Store` | An OS artifact, and the only finding `trading` produced in the whole sweep |

No finding a human had judged real was suppressed.

## Negative controls

Each control disables ONE half of the change and re-runs the suite, then the tree is restored
to `4152f9b` and the suite returns to 91/91.

```
Control 1: replace the reference-check guard with a no-op
Command:   bash tests/test-repohygiene.sh
Exit:      1
Verdict:   RED, as required. 89/91, failing exactly
           "an entry cited by full path is not flagged" and
           "an entry cited by bare basename is not flagged".
           The OS-artifact assertions still pass.

Control 2: replace the OS-artifact case arm with a pattern that never matches
Command:   bash tests/test-repohygiene.sh
Exit:      1
Verdict:   RED, as required. 89/91, failing exactly
           "a .DS_Store is never a finding" and "a Thumbs.db is never a finding".
           The citation assertions still pass.

Restore:   git checkout lib/repohygiene/repohygiene.sh
Command:   bash tests/test-repohygiene.sh
Exit:      0
Verdict:   PASS, 91/91 passed, 0 failed.
```

The two controls fail DISJOINT assertions. That is what proves the two halves are tested
separately rather than one guard masking the other.

## In-suite controls

Three of the nine new assertions exist only to catch a check that suppresses too much:

- the citers are deleted and committed, and both entries must reappear as findings. Without
  this, a reference check that suppressed EVERY entry would have passed the three assertions
  above it;
- a citation from INSIDE the staging dir must not suppress, or any drop with a sibling note
  naming it would silently suppress itself;
- a real drop sitting beside the OS junk must still be flagged.

## Rollback

`git revert` the two commits on this branch. Detector 2 returns to flagging on age alone, which
restores the four false positives above and nothing else. No data migration, no state, no
deployed surface: the scanner is read-only by contract and this change only narrows what it
emits.
