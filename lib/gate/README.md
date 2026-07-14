# gate

The **Govern leg's** engine (ADR-0034: Specify / Execute / Observe / Govern / Learn). Every
phase boundary in the kit routes through this module. It is what makes a lane a *contract*
instead of a suggestion.

Two things here can actually stop you. Everything else observes, classifies, or nudges.

```
        WORKFLOW.md lane x phase matrix          the branch diff
                    |                                  |
                    v                                  v
        gate-ledger.sh  (the LANE gate)      proof-ledger.sh  (the PROOF gate)
        "did every required gate run?"       "is there a fresh proof of done?"
              fails CLOSED                         fails OPEN
                    \                                  /
                     `------> hooks/ship-gate.sh <----'
                                 (exit 2 = block)
```

Both are diff/lane-keyed and spec-independent, so they fire the same whether the work came
through `/kit:execute` or a freeform `/goal` loop.

## The callables

Entry point is `bin/gate <verb>` (stable; SPEC-184). It forwards to `gate.sh`, which owns the
verb grammar and adds no logic. Call any script directly by path too; both work.

| Verb | Script | What it does | Can it block? |
|---|---|---|---|
| `gate ledger` | `gate-ledger.sh` | The lane gate + the run ledger. Records every gate decision, checks a run for completeness. | **yes** (`check` exit 1) |
| `gate proof-ledger` | `proof-ledger.sh` | The proof-of-done gate. Classifies the branch diff, demands a matching fresh proof. | **yes** (`check` exit 1) |
| `gate dispatch` | `dispatch-gate.sh` | Disjointness gate for `/kit:dispatch`. Two goals run in parallel only if their `## Touches` globs are provably disjoint. Also the drift guard. | **yes** (serializes / exit 1 on drift) |
| `gate proof` | `proof-gate.sh` | Classifier, not a gate. Task description to proof class + the artifact that work-type owes. | no |
| `gate quiz` | `quiz-gate.sh` | The star-tap NUDGE. Builds 5 diff-grounded questions, routes to `deep-understand`. | no (nudge only) |
| `gate coverage-delta` | `coverage-delta.sh` | Advisory. Source lines moved but test lines did not? Warn. | no (always exit 0) |
| `gate mutation-smoke` | `mutation-smoke.sh` | Advisory. Mutates a changed line, re-runs the suite. A surviving mutation means the suite does not bite. | no (always exit 0) |
| `gate proof-table` | `proof-table-gen.{sh,py}` | Generates a run-table from a rid's ledger. Refuses to write `proof-of-done.md`. | no |
| `gate verif-counts` | `verif-counts.sh` | Regenerates `docs/verification/COUNTS.md` from live suite runs. | no |

### The lane gate (`gate-ledger.sh`)

The single source for "which gates does this lane require" is the **`docs/WORKFLOW.md` lane x
phase matrix**, parsed at runtime. There is no second copy in code. A matrix cell of
`measure-twice` means required.

```bash
rid=$(gate ledger rid)                       # branch slug, `type/` prefix stripped
gate ledger required full                    # the lane's required gate keys
gate ledger record "$rid" Build ran "note"   # a gate decision
gate ledger check full "$rid"                # exit 0 iff every required gate has ran|override
gate ledger progress "$rid" full             # step k/n + checklist
```

Records are append-only, redacted (no command bodies), and one physical line per call
(`oneline()` collapses newlines, because a forged `| ran |` line would otherwise make
`check()` believe a gate ran).

### Ledger line grammar

```
TS | START   | lane=.. classified=.. type=.. repo=..
TS | GATE    | <phase> | ran|skipped|override | [reason]
TS | ACTION  | <text>
TS | TOKENS  | in=N out=N cache_read=N cache_create=N [cost=N]
TS | DEBT    | significance=.. worthiness=.. verdict=.. [response=..] [reason=..]
TS | OUTCOME | <phase> | start|end | at=<epoch> [caught=<bool> dur_s=N]
TS | MUTATION| verdict=flag|clean|skip [k=v ...]
```

**The load-bearing invariant:** only a `| GATE |` line in state `ran` or `override` satisfies
`check()`. Every other marker is *additive*, meaning `check()` / `override()` / `descent()` and
the ship-gate all ignore it (they key on `$2=="GATE"`). A TOKENS, DEBT, OUTCOME or MUTATION line
can never fake, satisfy, or mask a gate. Keep that property when adding a marker verb.

## Specs and decisions

| Where | What |
|---|---|
| `docs/decisions/0024-gate-ledger-and-ship-enforcement.md` | The lane gate + why mid-flight never blocks |
| `docs/decisions/0025-proof-of-done-ship-gate.md` | The proof gate |
| `docs/decisions/0026-colocated-table-first-proof.md` | Where a proof lives, and its shape |
| `docs/decisions/0031-understanding-gate.md` | The star-tap nudge (quiz-gate) |
| `docs/decisions/0035-durable-ledger-root.md` | Where the ledger is written |
| `docs/specs/` | `SPEC-032` dispatch, `SPEC-042/044` proof-of-done, `SPEC-048` ship-gate fail-closed, `SPEC-071/077` ledger fixes, `SPEC-076` V-model descent, `SPEC-097` ledger durability, `SPEC-125` quiz-gate, `SPEC-129` outcome-emit, `SPEC-130` coverage-delta, `SPEC-131` mutation-smoke, `SPEC-132/133` proof-table |

This module has no module-local `SPEC.md`; its specs are the numbered ones at the repo root.
That is why `lib/gate/SPEC` is still an open IOU in `tests/kit-contract-known-gaps.txt`.

## Tests

```bash
bash tests/test-gate-outcome.sh          # 22, SPEC-129 outcome markers + the additive property
bash tests/test-gate-vocab-recording.sh  # 17, every required gate name has a command that records it
bash tests/test-ledger-durability.sh     # 37, SPEC-097 durable root, override guard, forgery
bash tests/test-ledger-substrate.sh      #  9, the one append substrate
bash tests/test-quiz-gate.sh             # 29, SPEC-125 grounded questions + anti-fatigue
bash tests/test-ship-gate-fail-closed.sh #  5, SPEC-048
bash tests/test-ship-gate-profiles.sh    # install-dependent, see below
```

## The three things a newcomer gets wrong

**1. Recording a gate is not the same as passing it.** `check()` counts only `ran` and
`override`. But `progress()` and `descent()` count a phase as *disposed* if it is anything other
than a bare skip, so a `skipped` entry **with a reason** shows up as a green tick in `progress`
and still fails `check`. The checklist saying done does not mean the ship-gate agrees. That
divergence is deliberate (a skip is a decision worth seeing, not a pass), but it surprises
everyone once.

**2. The two gates fail in opposite directions.** The lane gate **fails closed**: an unknown
lane is refused, because reading an empty required-list would vacuously pass and let a run ship
with zero gates enforced. The proof gate **fails open**: no repo, no base, empty diff, missing
tooling all return 0, because a gate bug must never block unrelated work. If you are adding a
check, decide which one you are, and say so.

**3. An override is not a skeleton key.** Two guards you will hit. A reason already used to
override a *different* gate in the same run is rejected (exit 65), because one reason pasted
across every gate defeats the audit trail. And a proof-of-done override does **not** excuse
changed source files: it covers docs and sanctioned `deploy/` paths only. Overriding a branch
that touches `.sh`/`.py`/`.go` still blocks, by name.

Two smaller ones. `rid` is the branch slug with its leading `type/` segment stripped, and it must
stay byte-identical to `hooks/ship-gate.sh`'s `${BRANCH#*/}`; off a work branch it fails loudly
rather than record under a wrong key. And `tests/test-ship-gate-profiles.sh` prints
`[NO EXECUTABLE CHECK: ship-gate hook not installed]` and passes when the kit is not installed to
`~/.claude/dwarves-kit`, so a green run there proves nothing on a dev checkout.
