# SPEC-320: every spec is validated, in a fresh context

**Status:** DRAFT
Lane: full
Type: spec-feature
**Proof:** `docs/verification/spec-autovalidate.md`; `tests/test-hooks.sh`, the lane-plan and gate blocks; `tests/test-meta.sh`, the command-wiring block.

## Problem

A spec can reach the build without anyone but its author reading it.

| Path | Spec written | Validate today |
|---|---|---|
| `/kit:spec` | yes | step 4 reminds the operator; nothing runs |
| `/kit:execute` on an APPROVED spec | yes | nothing; execute accepts APPROVED (execute.md:12) |
| Lane matrix, normal lane | Spec is `measure-twice` | Validate is `skip`: no plan, no progress line, no ship advisory |
| `/kit:wrap` step 10, full lane | the worker writes it | the same worker "runs the lenses" on its own spec |

The self-run pass is weak evidence. On 2026-09-26 three step-10 workers self-validated their specs as APPROVED. A fresh-context design critique and review then returned REVISE on all three, including a reproduced CDPATH fail-open in `lib/spec/spec-next.sh`. One fresh-context `/kit:spec-validate` run on SPEC-314 caught seven gaps before any code.

## Contract

1. **One validator shape.** The validator is a fresh-context `general-purpose` subagent (the read-only `kit:*` agent rosters carry no Skill tool). Its prompt names the spec path, so the command does not pick "the most recent non-shipped spec". It invokes `kit:spec-validate` through the Skill tool, or the bare `spec-validate` a bash install symlinks, runs all reviewers in one pass without pausing, and is READ-ONLY by prompt: report only, no edits, no Status flip, no gate-ledger calls. It returns the command's report plus the Reviewer 6 line. Model: Sonnet on the normal and backfill lanes, Opus on the full lane.
2. **The lead owns every record.** From the report, the lead records, under the rid of the branch the spec lives on (`gate-ledger.sh rid` run inside that worktree, never the lead's own branch):
   - `Validate ran "APPROVED critical=0 warnings=<K> fresh agent=<id>"` only on APPROVED;
   - on NEEDS REVISION, the findings are folded into the spec and the validator runs once more; still not APPROVED records `Validate skipped "NEEDS REVISION: <criticals>"`, which the full lane's ship-gate refuses;
   - `design-record ran "design-bearing=<yes|no> pass"` on a Reviewer 6 pass, and `design-record skipped "critical: <finding>"` on a Reviewer 6 critical, so the full lane's ship-gate refuses a blocked design;
   - both outcome brackets, the `start` written before the dispatch so `dur_s` measures the validation.
   Status flips to `VALIDATED` only under `/kit:spec-validate`'s own verdict rules (Reviewer 6 still blocks).
3. **`/kit:spec` dispatches it.** After step 4's approval and, on the full lane, after the devs-team and advisor fold, `/kit:spec` dispatches the validator and applies item 2. The reminder line is removed.
4. **`/kit:execute` preflight.** After execute's spec-to-build lane re-check (execute.md steps 18-40), so an escalation to the full lane picks the Opus tier, and before task 1: on a spec whose `Lane:` is normal, full, or backfill and whose rid has no validate line (`gate-ledger.sh show <rid> | grep -qi '| GATE | validate |'` fails), execute dispatches the validator and applies item 2. The lead folds warnings and continues. A critical, a second NEEDS REVISION, or a Reviewer 6 BLOCK stops execute before task 1 with the findings and asks the operator; execute never builds a spec whose validation did not pass. This covers hand-written specs and specs from paths that skip `/kit:spec`.
5. **No fresh context available.** An agent with no subagent tool does not self-validate. It commits the spec and stops with `VALIDATE PENDING: <spec path>` to whoever dispatched it. A self-run pass never records `Validate ran`.
6. **`/kit:wrap` step 10, full lane.** The worker writes and commits the spec, then stops with `VALIDATE PENDING`. The lead, on that notification, dispatches the validator in the background. On the report: a Reviewer 6 BLOCK leaves the item `REPORTED` with `reported: spec-validate BLOCK: <finding>` and the worker is not resumed; otherwise the lead applies item 2 and resumes the worker with `SendMessage`, handing it the report to fold and build. A worker that cannot be resumed is replaced by a fresh builder on the same worktree, given the committed spec and the report. The sentence that has the worker "run the `kit:spec-validate` lenses" is replaced.
7. **Matrix.** The `docs/WORKFLOW.md` Validate row becomes `run-lite` on normal and backfill (full stays `measure-twice`). Normal and backfill runs now list Validate in `plan` and `progress`; the ship-gate does not refuse and prints nothing for it (lite phases have no ship-time advisory). `plan-record` now needs a validate disposition on those lanes, and `progress` on a past normal rid reads one step short of complete; the CHANGELOG says both. No read-side alias: three live ledgers carry `spec-validate` lines whose notes say self-validated, and counting them would contradict item 5.
8. **`/kit:spec-validate` itself records honestly.** Run directly, it records `Validate ran` only on APPROVED and `Validate skipped "NEEDS REVISION: <criticals>"` otherwise, and `design-record skipped "critical: ..."` on a Reviewer 6 critical, matching item 2.

## Picture

```
 /kit:spec ---------+
 /kit:execute (pre) +--> fresh validator (read-only, Skill kit:spec-validate) --> report
 wrap step 10 lead -+                                                              |
        ^                                                                          v
        |                                              lead records Validate + design-record
 worker: write + commit spec,                          under the SPEC branch's rid
 stop VALIDATE PENDING                                             |
                                                  BLOCK? --yes--> REPORTED, worker not resumed
                                                     | no
                                                     v
                                         SendMessage worker (or fresh builder): fold, build
```

## Design

Design-bearing: it changes the step-10 worker lifecycle and the matrix the ship-gate reads.

Step-10 item lifecycle:

```
  worker: spec committed
        |
        v
  VALIDATE PENDING --(lead: validator)--> report
        |                                   |
        |                     R6 BLOCK -----+----> REPORTED (stop)
        |                                   |
        |                     NEEDS REVISION: fold, one re-run
        |                                   |
        v                                   v
  resume worker (SendMessage) <--- APPROVED (records written by the lead)
        |    \
        |     +-- worker gone --> fresh builder on the same worktree
        v
  build -> negctl -> proof -> commit -> lead opens the draft PR
```

Chosen approach: execute in the commands, advise in the matrix. Only a lead with a subagent tool can give a spec a reader who is not its author, so every entry point that writes or consumes a spec dispatches the same read-only validator. The matrix change makes the gate visible on normal-lane runs without refusing pushes.

Approaches considered:

| Approach | Why not |
|---|---|
| Keep the reminder | The status quo, measured today: specs skip validation or grade themselves. |
| Validate `measure-twice` on the normal lane | The operator's first ask. The ship-gate reads the installed kit's WORKFLOW.md, so one cell refuses every normal-lane spec push in every adopted repo on the next update, and lane telemetry reclassifies every historical shipped normal run as incomplete. The measured failures were all full-lane, which already requires Validate. Revisit once the Validate outcome `caught=` rate on normal-lane runs earns it. |
| A hook that auto-runs validation on a spec write | A hook cannot dispatch a subagent; it would need a model call inside a hook, which PHILOSOPHY keeps to bash + jq. |
| A headless `claude -p` validator script workers call themselves | A fresh context without the SendMessage split, but a new component with cost, auth, and timeout surface; `lib/bench/lens-eval.sh` carries that risk for evals only. Revisit if the split proves brittle. |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| Validator dies or times out | no report | nothing recorded; Status stays pre-VALIDATED; full lane's ship-gate refuses, normal lane's advises |
| Validator edits the spec or writes the ledger | a diff or a non-`fresh` Validate line | read-only prompt; the lead owns every record |
| Lead records under its own rid | the worker branch's check still shows the gap | item 2 names the SPEC branch's rid |
| Worker never resumed | worktree with a spec-only commit | a fresh builder takes the worktree; otherwise the next wrap scan lists it under Left alone, nothing pushed |
| NEEDS REVISION recorded as ran | the gate would pass a failed review | item 2 records `ran` on APPROVED only |
| Harness without SendMessage | cannot resume | the fresh-builder path covers it |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: matrix | `docs/WORKFLOW.md` (Validate row; stale lines ~57, ~165, ~1010, ~1281, ~1354; a depth-call note for normal = run-lite) | `plan normal` and `plan backfill` list validate as lite; `required normal` unchanged |
| T2: pins | `tests/test-hooks.sh` (~1200-1217), `tests/test-e2e.sh` (~69, ~78, ~87), `tests/test-gate-ledger-plan-record.sh` (`NORMAL_TAIL`, the `-eq 9` counts, plus a case for the new validate disposition refusal) | pins updated; new asserts: normal and backfill list validate lite, tiny and bug do not; seen red first |
| T3: commands | `commands/spec.md` step 4, `commands/execute.md` preflight, `commands/wrap.md` step 10, `commands/spec-validate.md` record lines | the validator shape, item 2's records, the preflight and its stop rule, the split lifecycle, item 8; the reminder and the self-run sentence gone; `tests/test-meta.sh` greps each |
| T4: docs | `docs/CHANGELOG.md` (COMPAT: normal and backfill plans gain a lite Validate step; plan-record needs its disposition; past normal rids read one step short in `progress`; spec-validate records ran on APPROVED only), `docs/MANUAL.md` spec-validate entry, regenerated `docs/FEATURES.md` | present |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Normal plan lists validate lite | `gate-ledger.sh plan normal` | `validate  lite` |
| Normal ship not refused | normal rid with spec, build, ship, no Validate; `check normal <rid>` | exit 0 |
| Full ship refused on skipped Validate | full rid with every gate ran except `Validate skipped "NEEDS REVISION..."` | exit 1, `MISSING-GATE: validate` |
| Honest direct record | test-meta greps `commands/spec-validate.md` for `ran` on APPROVED only and `skipped` otherwise | present |
| plan-record refusal | `plan-record` on a normal rid with no validate disposition | exit 64 naming validate; with one, exit 0 |
| Tiny, bug untouched | `plan tiny`, `plan bug` | no validate |
| Commands wired | test-meta greps: spec.md dispatch + read-only + `VALIDATE PENDING`; execute.md preflight; wrap.md split; the reminder and self-run sentence absent | present / absent |
| Live | `/kit:spec` on a throwaway idea in this worktree | a subagent validator ran; the ledger shows `Validate ran ... fresh agent=` |

Negative control: `lib/gate/negctl.sh` reverts the normal cell of the Validate row to `skip`; the plan test goes red.

## Verification

`bash tests/test-hooks.sh`, `bash tests/test-meta.sh`, `bash tests/test-e2e.sh`, `bash tests/test-gate-ledger-plan-record.sh`, and `bash tests/run-all.sh --changed` exit 0. The live row is recorded in `docs/verification/spec-autovalidate.md`.

## After state

Every spec from `/kit:spec`, `/kit:execute`, or a wrap step-10 worker is read by a fresh-context, read-only validator before the build, and the lead records the result under the spec's own rid. The full lane refuses a push without an APPROVED validation; `/kit:execute` refuses to build any normal, full, or backfill spec whose validation did not pass; the normal lane's plan lists the step.

Not covered: `/kit:mega` and `/kit:dispatch` sub-goals reach the validator only through `/kit:execute`'s preflight. Nothing proves a `fresh` record came from a fresh context; the agent id in the note is an audit trail. A spec edited after validation is not re-validated.

## Decision Log

- Execute in the commands, advise in the matrix on the normal lane. The operator asked to require it; the design critique showed the hard gate lands estate-wide and reclassifies history, while the measured failures were full-lane. The flip to `measure-twice` stays one cell.
- A self-run pass never counts as validation.
- Second fresh validation returned NEEDS REVISION with 3 criticals, all folded: the read-side alias dropped (it would credit old self-runs), `/kit:spec-validate`'s own record lines made honest (item 8), and the false ship-gate advisory claim removed; nine warnings folded into items 1, 2, 4, 7 and T2-T4.
- Fresh validation (Opus, 7 reviewers) returned NEEDS REVISION with 3 criticals: the test-pin blast radius, the design-record owner, and a Design section with no diagram. The design critique returned REVISE. Every finding is folded in above.

## Design critique
Date: 2026-09-26
Design source: SPEC-320 ## Contract + ## Design (first draft)
Lenses run: simplicity, performance, boundaries, data-model, operability; missing: none

### High findings
1. Hard gate on the normal lane not supported by the evidence -- fix: run-lite on normal, auto-dispatch everywhere.
2. Rollout is estate-wide via the installed WORKFLOW.md -- fix: run-lite (as 1).
3. `commands/spec-validate.md` path missing in bash installs and consumer repos -- fix: Skill invocation.
4. The validator would edit, flip Status, and record -- fix: read-only prompt; the lead records.
5. design-record owner unnamed -- fix: the lead records it.
6. `ran` on NEEDS REVISION passes the gate -- fix: `ran` on APPROVED only.

### Medium findings
1. Paths bypassing `/kit:spec` -- fix: `/kit:execute` preflight.
2. Worker resume is fragile -- fix: fresh-builder fallback.
3. Wrong rid in step 10 -- fix: the SPEC branch's rid.
4. Missed test pins -- fix: T2 lists them.
5. Stale WORKFLOW lines -- fix: T1 lists them.
6. Undefined normal-lane step-10 clause -- fix: full lane only.

### Low findings
1. `fresh` is gameable -- fix: agent id in the note.
2. No model tier -- fix: Sonnet normal, Opus full.

### Scores
- Simplicity: 5/10
- Performance: 5/10
- Boundaries/composability: 4/10
- Data-model & correctness: 4/10
- Operability/failure-modes: 5/10

### Verdict: REVISE

Resolved in this revision: all High, Medium, and Low findings above.
