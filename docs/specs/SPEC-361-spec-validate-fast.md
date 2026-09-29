# Spec: faster full-lane spec validation (grounding, delta re-validation)

Generated: 2026-09-29
Status: APPROVED
Lane: full (lane-classify: the change edits the spec validation gate)
Type: refactor
File: `docs/specs/SPEC-361-spec-validate-fast.md`
References: `commands/spec.md` (step 5), `commands/spec-validate.md`, `commands/wrap.md` (step 10 full-lane worker), `commands/review-team.md` (step 2) and `commands/battery.md` (parallel dispatch pattern)

## Problem

A real full-lane task took 4 validation rounds at 5 to 7 minutes each. Two causes:

1. Rounds 2 and 3 found defects the spec writer could have caught alone. Fixtures did not match the real `gh` output shape (a pending CheckRun carries `completedAt:"0001-01-01T00:00:00Z"`, not null). A negative control could not go red against its own fixtures.
2. Each round ran the 7 reviewers one after another in one agent, so a round cost the sum of seven reviews.

The fix must be faster without being weaker: every round still runs all 7 reviewers, and nothing is carried between rounds.

## Change

1. **Grounding before handoff.** `commands/spec.md` step 5 and the wrap step-10 worker paragraph: before `Spec ran` or `VALIDATE PENDING`, the writer adds a `## Grounding` section. For each external data shape the spec asserts, one read-only live sample (command plus excerpt, masked). For each negative control, a dry trace: mutation, fixture reads, code path, named test that goes red. A claim that cannot be sampled is stated as such. `commands/spec-validate.md` Reviewer 4: a missing or unsampled `## Grounding` is a warning, never a critical.
2. **Parallel reviewers.** The lead dispatches the 7 reviewers as 7 fresh-context, read-only `general-purpose` subagents in one message, in the background, each running one reviewer lens through `commands/spec-validate.md`'s new single-reviewer mode. Sonnet by default; Opus for Reviewer 6 (the blocking design-record lens). One merge subagent on Opus then writes the single Spec Validation Report and verdict. The lead owns every record, as today. A round costs the slowest reviewer plus the merge.
3. **Fail closed on a dead reviewer.** A reviewer that dies, times out, or returns no findings block leaves the round incomplete. An incomplete round records nothing and passes nothing to the merge. The lead re-dispatches the missing reviewers. A reviewer that fails twice stops the run with Status unchanged for the operator.
4. **Re-validation context.** A re-validation dispatches all 7 again. Each reviewer also gets the prior report and `git diff <last-validated-sha>..HEAD -- <spec>`, and confirms that its own prior criticals cleared. This is context only, never a skip.
5. **Round budget.** One re-validation after NEEDS REVISION, as today. A second re-validation is allowed only when the dispatch brief carries the field `operator_directed_build: true`. The `commands/wrap.md` step-10 brief sets it only when the operator directed the build; `/kit:spec` sets it when the operator asks in that session for the build to continue. With the field absent there is no extra round. Each round is recorded in the ledger as today.

## Picture

```
lead (holds rid, owns every record)
  |
  | one message, 7 background Agent calls (Sonnet; R6 Opus)
  +--> R1 --+
  +--> R2 --+
  +--> R3 --+
  +--> R4 --+--> all 7 returned? --no--> re-dispatch missing (2nd failure: stop)
  +--> R5 --+            |
  +--> R6 --+           yes
  +--> R7 --+            v
                  merge subagent (Opus) -> one Spec Validation Report + verdict
                         |
                  lead records Validate / design-record
  re-validation: same fan-out, each reviewer also gets prior report + git diff
```

## Design

Approaches, chosen design, and rejected alternatives are in `### Approaches considered` below; this block adds no other decision.

### Approaches considered

1. Parallel fresh-context reviewers plus one merge (chosen). Wall clock drops from the sum of seven reviews to the slowest one. Every reviewer runs on every round, so there is no carry path to go stale.
2. Section-hash verdict cache with delta re-runs (rejected). The first validation of this spec found 4 criticals, each a way the cache could carry a stale verdict: Reviewer 6 did not read Technical Design, Reviewer 2 did not read Design, `store` hashed the working tree instead of the validated sha, and a missing spec file failed open. A fifth finding settled it: `commands/spec-validate.md` requires a Decision Log entry per fix, and Decision Log was outside the section map, so every re-validation would have re-run all 7 anyway. The cache saved nothing and put the gate at risk.
3. Let one validator judge which reviewers to re-run from the diff (rejected). An LLM decides to skip a check with no mechanical floor.

### Interfaces (I/O contract)

- Reviewer brief (lead to subagent): spec path, `Reviewer N only`, plus on a re-validation the prior report path and the `git diff` range. Read-only: no edits, no Status flip, no `gate-ledger.sh`.
- Reviewer return: a block headed `[reviewer N]` with `Critical`, `Warnings`, `Passed`, and for Reviewer 6 the line `design-bearing=<yes|no> <pass|critical: <finding>>`. A return without that head is a dead reviewer.
- Merge brief: the 7 blocks. Output: the existing Spec Validation Report format and verdict. The merge adds no finding of its own and drops none.

Invariants: a verdict exists only after 7 reviewer blocks exist for the current spec text. Reviewer 6 stays the one blocking lens. No verdict crosses a round.

## Failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| A reviewer dies, times out, or returns no `[reviewer N]` block | Block count under 7 | Round incomplete, nothing recorded, re-dispatch the missing reviewer; a second failure stops the run with Status unchanged |
| Merge subagent dies or drops a finding | No report, or finding count differs from the reviewer blocks | Lead re-dispatches the merge once, then stops; the lead spot-checks that every Critical from a block appears in the report |
| Parallel reviewers duplicate one finding | Same issue under two reviewers | Merge keeps one entry and names both reviewers |
| A reviewer edits a file | Spec or Status changes during the round | The brief says read-only, and the lead diffs the spec before and after the round; a change voids the round |
| Harness cannot dispatch parallel Agent calls | Dispatch surface has no Agent tool | Fall back to the sequential single pass the command runs today |
| Cost rises with 7 subagents plus a merge | Token telemetry | Sonnet for six reviewers; one Opus each for Reviewer 6 and the merge; an accepted tradeoff, not asserted as a saving |

## Grounding

External shapes this spec relies on, sampled read-only on 2026-09-29:

| Claim | Command | Excerpt |
|---|---|---|
| A kit command already fans out read-only lenses in parallel with a per-lens model | `grep -n 'parallel' commands/review-team.md` | line 40: `### Step 2: Dispatch 3 lenses in parallel`; line 42: `Dispatch these 3 subagents via the Task tool. They can run simultaneously since they're all read-only`; the model tiering paragraph sets `model: sonnet` on two lenses and the session model on the third |
| Another command states the dispatch shape | `sed -n 51,52p commands/battery.md` | `Dispatch legs 1 and 2 IN PARALLEL (one message, multiple Task calls).` |
| A command already dispatches a validator subagent in the background | `sed -n 300,306p commands/wrap.md` | `dispatches the validator ... (fresh-context, read-only, general-purpose, Opus) in the background` |
| The validator must be `general-purpose` because it needs the Skill tool | `grep -n 'general-purpose' commands/spec.md` | step 5: `one fresh-context general-purpose subagent (the read-only kit:* agent rosters carry no Skill tool)` |
| `gate-ledger.sh rid` derives the rid from the branch | `bash lib/gate/gate-ledger.sh rid` | `spec-validate-fast` |

Consequences: the lead fans out, not a validator subagent, because a subagent may lack the Agent tool. The reviewers are `general-purpose` for the same Skill-tool reason step 5 gives. The dispatch text follows `review-team` step 2 and `battery`: one message, several calls, read-only, lead merges and records.

Not sampled: a live run of 7 concurrent reviewers, and the wall-clock saving. Both depend on the harness and model load and are not asserted. The first real validation of a later spec measures them.

This change is docs-only, so it has no negative control against fixtures. The checks are the grep assertions in AC5 and the meta suite.

## Acceptance Criteria (global)

- AC1: `commands/spec-validate.md` has a single-reviewer mode, a merge step, a dead-reviewer rule that fails closed, and re-validation context that is stated as context only.
- AC2: `commands/spec.md` step 5 and `commands/wrap.md` step 10 dispatch 7 parallel reviewers plus a merge, name the models (Sonnet default, Opus for Reviewer 6 and the merge), and keep the lead as the only recorder.
- AC3: the round budget names `operator_directed_build: true` in both `commands/spec.md` and `commands/wrap.md`; with the field absent there is no extra round.
- AC4: Reviewer 4 in `commands/spec-validate.md` warns on a missing or unsampled `## Grounding`, and `commands/spec.md` step 5 and the wrap worker paragraph require it before handoff.
- AC5: `grep -c 'operator_directed_build' commands/spec.md commands/wrap.md` is at least 1 per file, `grep -c 'Grounding' commands/spec-validate.md` is at least 1, and `bash tests/test-meta.sh` passes.

## Verification

`bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh`, then the AC5 greps.

## Edge Cases

1. Only Reviewer 6 fails to return: the round is incomplete even though six reviews exist; nothing is recorded.
2. The spec changes between dispatch and merge: the lead's before and after diff voids the round and it re-runs.
3. First validation: no prior report exists, so the context block is omitted; all 7 still run.
4. The operator directed the build but the field is missing from the brief: no extra round, and the item stays reported.
5. Reviewer 7 finds `not long-lived`: its block still carries `Passed`, so it counts as returned.

## Out of Scope

- Caching or carrying any verdict between rounds.
- A change to any reviewer's lens text, or to Reviewer 6's blocking rule.
- Parallel devs-team, advisor, or test-plan critique.

## Touches
- commands/**
- docs/implementation-notes/**

## Tasks

- [ ] T1: `commands/spec-validate.md`: single-reviewer mode, merge step, dead-reviewer rule, re-validation context, Reviewer 4 Grounding warning.
- [ ] T2: `commands/spec.md` step 5: grounding before handoff, parallel dispatch, models, round budget with `operator_directed_build`.
- [ ] T3: `commands/wrap.md` step 10: the same for the full-lane worker and the lead's dispatch, with the field in the brief.

## Decision Log
- DEC-A: drop the section-hash cache and the `lib/spec/validate-cache.sh` helper. Reason: the validator's 4 criticals and the Decision Log finding. Rejected: patching the map, since every fix a re-validation asks for edits the Decision Log.
- DEC-B: the lead fans out the reviewers itself, because a subagent may lack the Agent tool.
- DEC-C: the extra round needs an explicit `operator_directed_build: true` field, never an inferred intent.
- DEC-D: a dead reviewer fails closed, with one re-dispatch, then a stop for the operator.
