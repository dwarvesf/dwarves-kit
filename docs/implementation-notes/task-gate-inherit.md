# Implementation notes: gate-ledger inherit

Delta from `docs/specs/SPEC-393-task-gate-inherit.md`. What the spec already states is not repeated here.

## Builder warnings from validate round 1

These came out of the round-1 validation. The lead ruled that they stay out of the spec. Each is a check the build's tests or the review should cover, or a risk the spec accepts.

- **Concurrent writers on one child rid.** Two `inherit` calls, or an `inherit` racing a hand `override` on the same child, can interleave between the conflict check and the write loop. The spec accepts this race. `plan-record` guards the same window with a `cmp` against a snapshot (`lib/gate/gate-ledger.sh` lines 653-659); `inherit` does not need that guard in v1, because a re-run converges through the idempotent skip. Do not add a lock.
- **Override counts in the stats and debt readers.** Inherited lines are `override` GATE lines, so every reader that counts overrides counts them too. Known readers: `lib/mega/mega-report.py`, `lib/stats/src/stats/ceremony.py`, `lib/stats/src/stats/anomalies.py`, `lib/stats/src/stats/adapters.py`, and `lib/telemetry/lane-telemetry.sh` (lines 226-228). Expect override rates, ceremony and anomaly signals to rise for multi-task specs. The fixed token `inherited from <runid(parent)>: ` is the read-side split if a reader needs one later. v1 changes no reader. The review should confirm that no reader treats an override count as a hard failure.
- **The parent ledger is host-local.** The verb reads `runs/<parent>.log` under the resolved ledger root on this host. A spec validated on another machine has no parent ledger here, so the verb refuses with exit 1. That refusal is correct. The fix is to run the inherit on the host that holds the parent ledger, or to sync the ledger first. Name this in the refusal message ("no ledger for parent '<p>' under <root>") so the lead sees which root was read.

## Build rulings from validate round 2 (APPROVED, 34 warnings)

The lead picked these warnings to apply in the build. Each one changes code or a test, not the spec text.

- **Fail closed on lane data.** When `LANES_KIT_ONLY=1 required full` fails, or the filtered set is empty, the verb exits 1 and writes nothing. A test pins this by pointing the kit-root lane read at a broken lane table.
- **Exit 65 has two meanings, each with its own stderr line.** The parent conflict prints `inherit: child '<rid>' already inherited <phase> from another parent ...`. A refused write prints `inherit: override() refused the <phase> write (exit <n>) ...`. AC-7 and AC-8 assert their own text.
- **AC-7 and AC-8 fixtures use parents that fully pass.** Parents `y`, `watch-hub` and `watch-hub-spec` each hold all seven phases with `ran` as the last state. A refusal then comes from the check under test and never from the judge.
- **Ledger root pinning.** The harness sets `DWARVES_KIT_LOG_DIR` and unsets `KIT_LEDGER_DIR`. One test asserts that the verb's write and `show` read the same file.
- **Task ownership moves.** The AC-5 reverse case (skipped rounds, then ran, passes) and the AC-9 overlay case move under TASK-1b, because both assert a write.
- **One hermetic positive AC (AC-11).** After `inherit` plus `record build|review|docs ran` and `override ship|reflect`, `check full <rid> --kit-lanes` exits 0.
- **Input hygiene.** `<ts>` must match `YYYY-MM-DDTHH:MM:SSZ` or that phase is refused. The grandparent name `<G>` passes through `runid` before it is printed.
- **Explicit propagation.** The write loop calls `override ... || return $?`. NC-8 mutates exactly that line.
- **Usage.** `inherit` joins the bottom `usage:` string.
- **Wording.** Refusals read "last state ran", never "passed". The no-ledger message says the ledger is host-local and names the root.

## Review fix: judge rows split on \037, not a tab

Context: the fresh-context review (Opus, correctness and forgery lens) found that `IFS=$'\t'` treats a tab as whitespace. An empty state field collapsed, so a hand-edited parent line `ran | GATE | validate |  | <iso>` read as state `ran` at that time, and the verb wrote an inherited line for it.
Decision: the judge awk prints rows split by `\037`, and both read loops split on `\037`. An empty state now reports `last state empty, not ran`.
Why: `\037` is not IFS whitespace, so empty fields survive the read. It works in bash 3.2.
Impact: two tests beyond the spec. EMPTYSTATE pins the forgery shape. AC-3, AC-4 and AC-5 also assert that the parent ledger stays byte-identical on refusal. NC-9 (split on a tab again) turns EMPTYSTATE red, and under that mutation the verb exits 0 and writes the line.
