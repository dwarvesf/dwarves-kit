# Implementation notes: lane-one-source

Delta from the worker brief. No spec backs this change.

## What changed

- `lib/gate/lane-data.sh`: `lane_known`, `lane_spec_header`, `lane_effective`. The last START-AMEND, else the first START, else the spec `Lane:` header, else (with `--default`) the classifier default.
- `lib/gate/gate-ledger.sh`: plain `start` validates the lane against `LANE_NAMES` (exit 64, valid list). `_effective_lane` calls the resolver. New `lane` verb prints `<lane>\t<source>\t<spec header>`.
- `hooks/ship-gate.sh`: descent, build-ran and the push check all take the lane from the `lane` verb. The spec lookup moved above the build-ran block so the descent lane can fall back to the header.
- `lib/gate/ship-rules.sh`: no change. It only receives the lane as an argument and never reads the ledger.

## Decisions

- A stray START or START-AMEND lane reads as absent, so the next source answers. Fail-closed on it would have refused runs that the header answered before.
- The spec header comes back raw, even when it is not a lane name. `check()` still fails closed on it. Filtering it would turn a bad header into "no lane" and open the non-adopted fail-open path.
- ship-gate does not pass `--default`. A spec with no header and no usable START keeps the fail-closed no-lane block in adopted repos. `--default` exists for callers that want a lane instead of a refusal.
- The first START is the first START line only. A later valid START does not replace a stray first one.

## Behavior changes at the ship boundary

- A plain first START now beats the spec header. Before, only a START-AMEND did. A spec with `Lane: full` and a first START of `normal` ships on normal gates and prints an `[advisory]` naming the override.
- A spec whose header the parser misses (for example `Status: ACTIVE. Lane: normal.` on one line) but whose ledger has a START now resolves from the START. Before it hit the no-lane block.

## Left alone, outside the slice

- `gate-ledger.sh` report and telemetry readers (`grep -m1 '| START |'`) and `record-batch` (`last START or START-AMEND`) read the lane directly. They tolerate stray names. Folding them into the resolver is a follow-up.
- `lane-telemetry.sh` has its own reader.

## Open question

The plain-START-beats-header rule lets a ledger writer lower a run below its spec header without `--lower`. The amend path guards that; the plain START path cannot, because the first START is written before anyone compares it to the header. The `[advisory]` is the only signal today. A rank check in ship-gate (header stricter than the ledger lane prints a louder notice) would close it.
