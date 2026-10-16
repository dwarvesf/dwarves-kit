# Implementation notes -- harvest-bash

Deltas from SPEC-409. Nothing here repeats what the spec already states.

## 2026-10-16 An empty first file made awk swallow the candidates

- Context: the dedup awk program told its two inputs apart with `NR == FNR`. A ledger with no known slugs gives an empty first file, so `NR == FNR` stayed true for the candidates too, and every candidate was read as a known slug. 77 of 171 cases failed on that alone, most of them staging nothing.
- Decision/Change: the first file is matched by name, `FILENAME == ARGV[1]`.
- Why: a first-time harvest, with no ledger and no glossary, is the most common real run, and it staged nothing.

## 2026-10-16 A golden that carried the clock

- Context: the debounce cases read the stamp file, so their goldens held the epoch at generation time and failed an hour later.
- Decision/Change: the harness folds a stamp the hook just wrote (a ten-digit epoch within a day of now) to `@NOW@`. A stamp the case seeded and the hook left alone keeps its value, so a refresh and a no-op still differ.

## 2026-10-16 A traceback in a golden names the scratch directory

- Context: the shim let the Python's traceback reach stderr, and it holds the path of the run. The corpus could never match it.
- Decision/Change: `gen-expected.sh` blanks the stderr of a crash and keeps every other field as the Python left it. The port exits 0 silently on the same shapes. The operator verbs' usage line is renamed to `harvest_sweep.py`, where they now run.

## 2026-10-16 A failed redirect speaks before `2>/dev/null` takes effect

- Context: `{ ...; } >> "$ledger" 2>/dev/null` printed bash's own "Is a directory" message when the ledger was a directory, because redirections apply left to right.
- Decision/Change: `2>/dev/null` comes first. The locked child also exits with the status of `stage_locked`, and the parent treats a non-zero status as the crash it is; before, the parent printed `staged  new` with an empty count.

## 2026-10-16 The concurrency row needed processes, not threads

- Context: the old row drove `_harvest_payload` from eight Python threads behind a barrier. The function no longer exists.
- Decision/Change: eight real harvest processes share one ledger. Each fake extractor checks in at a rendezvous directory and waits for the other seven, so all eight reach the dedup and the append together. NC1 (no lock) turns the row red.

## 2026-10-16 harvest.py is split, not deleted

- Context: `hooks/harvest_sweep.py` imports the state-dir resolver, the slug rules, the ledger locks and the stager from `harvest.py`, and the operator verbs share its locks.
- Decision/Change: that library and the three verbs moved to `hooks/harvest_lib.py`; the sweep's entry runs the verbs. `tests/test-harvest-sweep.sh` imports the library under its old name. Porting the sweep itself is not part of this change.
