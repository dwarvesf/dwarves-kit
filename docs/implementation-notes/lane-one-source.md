# Implementation notes: lane-one-source

Delta from the worker brief. No spec backs this change.

## What changed

- `lib/gate/lane-data.sh`: `lane_declared_names`, `lane_declared`, `lane_known`, `lane_spec_header`, `lane_effective`. The ledger lane is the last START-AMEND, else the first START, else the spec `Lane:` header, else (with `--default`) the classifier default. The check lane is the stricter of the spec header and the ledger lane.
- `lib/gate/gate-ledger.sh`: plain `start` validates the lane against the declared lanes (exit 64, valid list). `_effective_lane` calls the resolver. New `lane` verb prints `<ledger lane>\t<source>\t<spec header or ->\t<check lane>`.
- `hooks/ship-gate.sh`: the push check uses the check lane. Descent and build-ran use the ledger lane. The spec lookup moved above the build-ran block so the descent lane can fall back to the header.
- `lib/gate/ship-rules.sh`: no change. It only receives the lane as an argument.

## Decisions

- A stray START or START-AMEND lane reads as absent, so the next source answers.
- The spec header comes back raw, even when it is not a lane name. `check()` still fails closed on it.
- ship-gate does not pass `--default`. A spec with no header and no usable START keeps the no-lane block in adopted repos.
- The first START is the first START line only.
- Plain `start` accepts a lanes.d overlay lane (a vertical kit's `study`). `start --amend` takes the five kit lanes only.
- Check lane, stricter wins by `lane_rank_of`. A rank tie keeps the old winner: amend keeps the ledger lane, plain START keeps the header. A lane with no rank never lowers a ranked one.
- An amend counts as a sanctioned lowering only when the `lane-lower` override line directly before it targets the same lane. That is the line `start --amend --lower --reason` writes.

## Measured effect on the ship check

Original master rule (amend, else header; no lane is refused) against this branch, over the 100 ledgers that join a spec (kit specs plus `~/workspace/*/*/docs/specs`). Verdict is `gate-ledger.sh check`.

| Result | Runs |
|---|---|
| Check lane differs | 7 |
| Allowed to refused | 1 |
| Refused to allowed | 1 |
| Unchanged verdict | 98 |

| Run | Flip | Why |
|---|---|---|
| `discord-prune` | allowed to refused | Header `Lane: full`, ledger holds one bare `START-AMEND lane=normal` with no START and no `--lower` reason. Master let the amend win; the new rule checks `full`. This is the loophole the change closes. Resuming it needs a `--lower --reason` amend. |
| `never-pinged-lifecycle` | refused to allowed | The header parser misses `Lane: normal` in the middle of a line, so master hit the no-lane block. It now resolves from its START lane (`full`). |

## Left alone, outside the slice

- The `gate-ledger.sh` report and telemetry readers (`grep -m1 '| START |'`), `record-batch`, and `lane-telemetry.sh` read START directly. They tolerate stray names. Folding them into the resolver is a follow-up.

## Open question

Any ledger writer can append a `lane-lower` override line (the `override` verb takes any phase name), so the sanctioned-lowering test shares the trust level of the amend verb itself. The diff floor still applies full-lane gates to hard paths whatever the lane says.
