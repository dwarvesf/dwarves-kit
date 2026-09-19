# SPEC-305: runtime-reorg as a fourth loop-engineering shape

**Status**: DRAFT
Lane: normal
**Owner module**: `skills/loop-engineering/SKILL.md` (shape list), `commands/execute.md` (trigger surface)
**Source**: ops-toolkit backlog ID-770; Saboo dynamic-agent-org image (x.com/Saboo_Shubham_/status/2078301249376825397); Kopadze graph-engineering article (x.com/i/article/2080668775796314331)

## Problem

The kit's three loop shapes (bounded-revise engine, campaign/worklist, bounded
search-select) are all chosen **up front** and none rewrites the run's topology
mid-flight. The Saboo image carries four runtime reorg events the kit currently
handles by hand or not at all:

1. *Two fixes promote a model* - today the retry loop exhausts at 2 and stops
   for a human; the only model bump is the static `Model:` spec header.
2. *A failure cluster forms a review board* - today each task's FAIL is handled
   in isolation; no rule notices that 3 failures share a module.
3. *Budget over progress collapses the fan-out* - no rule connects spend to
   verified progress mid-run.
4. *A small task runs solo* - execute.md says "not for one-prompt tasks" as
   prose; it is not a recorded topology decision.

Each of these is a signal -> topology-rewrite rule. The shape they share: the
lead watches a small set of run signals and, when one crosses its threshold,
rewrites the dispatch plan for the REST of the run, recording the reorg as a
ledger action. This is a fourth shape: **signal-driven runtime reorg**. It is
not a loop over an artifact; it is a policy layer over any running loop.

## Design

### The shape (Step 2 of loop-engineering)

```
run signals observed per task boundary
        |
        v
+-------------------------------+
| reorg rules (each fires once) |
|  R1 fix-count >= 2       -> promote next dispatch one model tier
|  R2 same-module FAILs >=2 -> pause fan-out, dispatch scoped review
|  R3 budget/progress skew -> collapse remaining fan-out to serial+cheap
|  R4 task under solo-floor -> lead implements inline, no worker dispatch
+-------------------------------+
        |
        v
gate-ledger.sh action "<rid>" "reorg: <rule> fired on <signal>"
        |
        v
continue run under the rewritten topology
```

### Rules mapped to existing mechanics

| Rule | Signal | Reorg move | Existing surface it rides |
|---|---|---|---|
| R1 promote | 2nd FAIL:fixable on one task | next fix dispatch bumps model tier (sonnet -> opus) | the retry loop's dispatch site; `model:` dispatch param; verifier-tier-parity rule still applies |
| R2 review board | >=2 task FAILs sharing a fingerprint prefix or module path | suspend task fan-out; dispatch one review lens on the cluster before resuming | `kit:review-team` single-lens dispatch; gate-ledger action |
| R3 collapse | stated budget or turn ceiling >50% consumed with <25% tasks verified | remaining independent tasks dispatch serially at cheap tier | orchestrate wave fan-out; SPEC-303 turn ceiling telemetry |
| R4 solo | task AC is one-file / sub-floor diff | lead implements inline; verifier still runs (never self-verify) | execute.md "not for one-prompt tasks" prose, formalized |

### Invariants

- **Fires once each.** Each rule may fire at most once per run; a reorg never
  triggers another reorg rule (no cascades). The run either converges under the
  new topology or stops and reports - the Ralph Wiggum rule applied to reorg
  itself.
- **Recorded, never silent.** Every fired rule appends
  `gate-ledger.sh action <rid> "reorg: <rule> <signal>=<value>"`. An operator
  reading the ledger sees the topology history.
- **Never removes rigor.** Reorg may add a gate, promote a tier, or serialize
  dispatch; it may never drop a verifier, skip a gate, or widen permissions.
  Same up-only invariant as `lane-classify.sh escalate`.
- **Signal honesty.** A rule whose signal is not measurable in the current run
  (e.g. R3 with no stated budget and no token telemetry) is skipped with a
  ledger note, never guessed.

### Survival set (Step 2b)

- convergence: no signal crosses threshold; the run is identical to today's.
- non-convergence: all four rules fire and the run still fails; the ship report
  names every reorg and the run stops honestly.
- bad input: a signal arrives malformed or absent; the rule skips with a note.
- interrupted run: ledger actions survive the session, so a resumed run sees
  which promotions already fired and does not re-fire them.
- gamed metric: the cheapest gaming move is promoting to opus on every task;
  the once-per-run cap plus the recorded ledger line is the counter.

## Test plan

| # | Scenario | Expect |
|---|---|---|
| 1 | Desk-trace a recorded run with a real fix cycle (agent-namespace run, 2026-09-19) | Rules classify correctly: which would have fired, which correctly stayed silent |
| 2 | Signal-availability check: each rule's trigger maps to an observable surface (verdict text, fingerprint, ledger, spec header) | Every rule names a concrete signal source or is marked telemetry-gated |
| 3 | Live test on the next real `kit:execute` multi-task run | Reorg events (or their correct absence) appear as ledger actions |

## Verification

Desk-trace of a past run + signal-availability check (rows 1-2) are executable
now; row 3 is carried as the adoption AC. This spec is an eval draft: it gates
the shape's admission into the SKILL.md shape list, not its build.

## After state

- `loop-engineering` SKILL.md Step 2 lists a fourth shape: signal-driven
  runtime reorg, with the routing question "does the loop need to rewrite its
  own topology mid-run on a signal?"
- `execute.md` carries a reorg-policy section binding R1-R4 to the dispatch
  loop's actual signal surfaces.
- The four Saboo events each have a named rule; nothing else is claimed.
