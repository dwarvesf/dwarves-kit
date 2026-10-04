# Implementation notes: gate-ledger inherit

Delta from `docs/specs/SPEC-393-task-gate-inherit.md`. What the spec already states is not repeated here.

## Builder warnings from validate round 1

These came out of the round-1 validation. The lead ruled that they stay out of the spec. Each is a check the build's tests or the review should cover, or a risk the spec accepts.

- **Concurrent writers on one child rid.** Two `inherit` calls, or an `inherit` racing a hand `override` on the same child, can interleave between the conflict check and the write loop. The spec accepts this race. `plan-record` guards the same window with a `cmp` against a snapshot (`lib/gate/gate-ledger.sh` lines 653-659); `inherit` does not need that guard in v1, because a re-run converges through the idempotent skip. Do not add a lock.
- **Override counts in the stats and debt readers.** Inherited lines are `override` GATE lines, so every reader that counts overrides counts them too. Known readers: `lib/mega/mega-report.py`, `lib/stats/src/stats/ceremony.py`, `lib/stats/src/stats/anomalies.py`, `lib/stats/src/stats/adapters.py`, and `lib/telemetry/lane-telemetry.sh` (lines 226-228). Expect override rates, ceremony and anomaly signals to rise for multi-task specs. The fixed token `inherited from <runid(parent)>: ` is the read-side split if a reader needs one later. v1 changes no reader. The review should confirm that no reader treats an override count as a hard failure.
- **The parent ledger is host-local.** The verb reads `runs/<parent>.log` under the resolved ledger root on this host. A spec validated on another machine has no parent ledger here, so the verb refuses with exit 1. That refusal is correct. The fix is to run the inherit on the host that holds the parent ledger, or to sync the ledger first. Name this in the refusal message ("no ledger for parent '<p>' under <root>") so the lead sees which root was read.
