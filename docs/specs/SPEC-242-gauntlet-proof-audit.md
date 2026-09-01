# Spec: Gauntlet proof-audit, an audit-loop instance over the run-record corpus

Generated: 2026-09-01
Status: VALIDATED
Lane: normal
References: `docs/patterns/audit-loop.md` (the pattern this instances); `skills/doc-drift/SKILL.md` + `skills/backlog-reconcile/SKILL.md` (sibling instances, the authoring template); `commands/gauntlet.md` (the record grammar being audited: QL-VERDICT/AB-VERDICT markers, per-round `checker-output.txt`, scrub rules 7/8); `lib/gauntlet/stats.sh` (SPEC-240, reads the same corpus, shares the record-dir enumeration); `agents/audit-scanner.md` (the shared read-only Tier-2 scanner); `_meta/BACKLOG.md` ID-495.

**Scope:** a new model-invocable SKILL (no command file, no agent), auditing existing gauntlet run records against their own evidence. A skeptic pass in the recheck-verifier shape. It never re-runs a probe and never rewrites a historical record; it REPORTS discrepancies for the operator.

## Problem

The gauntlet corpus (`docs/verification/gauntlet/*/ROUNDS.md`, `AB-ROUNDS.md`) is the flywheel's eval data and is trusted at face value: a ROUNDS.md says "clean=true findings=0" and everyone believes it. Nothing checks that a record's CLAIMS match its own persisted EVIDENCE, that a quoted finding actually appears in the transcript, that a recorded GREEN matches the committed `checker-output.txt`, that the scrub was actually clean, that the run-dir grammar conforms. A fabricated or drifted record would pass unnoticed. This is the audit-loop's "test coverage / feature liveness" shape applied to proof records.

## Solution

### Approaches considered

1. **A new audit-loop SKILL `gauntlet-proof-audit`** mirroring doc-drift's structure (chosen): item set = record dirs, contract = claims match evidence, Tier-1 grep + Tier-2 scanner, report-first.
2. Fold into `lib/gauntlet/stats.sh`: rejected, stats is a read-only projection (numbers), not a verdict-producing audit with a gate; different job, different output.
3. A blocking gate at gauntlet-record commit time: rejected, the audit is a cadence/on-demand skeptic pass over the accumulated corpus (audit-loop is on-demand-first), not a per-commit hook.

### Chosen approach + why

A SKILL at `skills/gauntlet-proof-audit/SKILL.md`, model-invocable (`/kit:gauntlet-proof-audit`), following the audit-loop pattern's four slots. It enumerates every run-record dir, Tier-1 greps each record's claims against its committed evidence files, dispatches `kit:audit-scanner` (Tier-2) only where Tier-1 flags or where a finding-quote needs semantic matching against the transcript, verdicts each record with the audit-loop grammar, and ships a report. Because records are point-in-time, the dominant verdicts are OK / UNSURE / DANGER, not FIX: a historical record is not rewritten (that would corrupt the evidence trail); a genuine defect is reported and, if the record is actively misleading, marked with a correction note that names the discrepancy, never a silent edit.

### Extensibility & boundaries

- New record grammars (a future `[[X-VERDICT]]`) extend the contract's marker list; the enumeration and tiering are unchanged.
- Boundary: it audits records, it does not re-run probes, re-score, or delete a record. A record that cannot be verified from its committed evidence (e.g. the transcript was gitignored as a room artifact) is UNTESTABLE → UNSURE, never REMOVE.

## Picture

```
enumerate run-record dirs (git ls-files docs/verification/gauntlet/*/*ROUNDS.md)
      |
      v
per record, Tier 1 (grep/wc, zero model cost):
  - every QL/AB-VERDICT marker is well-formed (the stats.sh grammar)
  - the recorded per-round verdict matches committed checker-output.txt
  - claimed findings count reconciles with the round rows
  - scrub: no resolved credential VALUE in committed evidence (a bare op:// pointer is allowed)
  - run-dir grammar conforms (dated container, per-round files present)
      |
      v
Tier 2 (kit:audit-scanner) ONLY where Tier 1 flagged, or to match a
  quoted finding against the transcript it cites
      |
      v
verdict each record: OK / FLAG(=FIX-note) / UNSURE / DANGER   (REMOVE never)
      |
      v
report: a PR body (or a CLEAN report if nothing flagged); UNSURE/DANGER
  listed for the operator, never auto-resolved
```

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | `git ls-files 'docs/verification/gauntlet/*/ROUNDS.md' 'docs/verification/gauntlet/*/*-ROUNDS.md' 'docs/verification/gauntlet/*/AB-ROUNDS.md'` (committed records only; a room copy's own ROUNDS is untracked and never enters the set) |
| Contract | every CLAIM in the record is backed by its committed EVIDENCE: markers well-formed; recorded verdict == committed `checker-output.txt`; findings count reconciles with the rows; scrub clean (no resolved credential VALUE in committed evidence, `sk-ant-`/an assigned key value; a bare `op://` pointer is allowed per estate policy, not a leak); run-dir grammar conforms; a quoted finding string is present in the cited transcript |
| Evidence class | Tier 1: the committed record files themselves via grep/wc/diff. Tier 2: `kit:audit-scanner` reads a quoted finding against the transcript. Evidence gitignored as a room artifact (transcript pruned) = UNTESTABLE → UNSURE |
| Apply mechanics | REPORT-first: a genuine discrepancy is FLAGGED with a dated correction note appended to the record (never a silent rewrite of the historical claim); UNSURE/DANGER listed in the PR body; REMOVE is disallowed (a record is evidence, not deleted) |

## Task Breakdown

### Phase 1

- TASK-001: `skills/gauntlet-proof-audit/SKILL.md` (frontmatter with the trigger description + `disable-model-invocation: false`; the four-slots table; the Tier-1/Tier-2 process mirroring doc-drift; the report/gate step; a cadence note).
- TASK-002: wire it in: README Skills-table row, regenerate `docs/FEATURES.md`, add the instance as a row in `docs/patterns/audit-loop.md`'s SDLC-instances table (or its own "gauntlet" note if it does not fit the product-work table).
- TASK-003: the acceptance run: execute the skill's Tier-1 pass against the LIVE corpus once, record the enumeration + per-record verdict table as the proof (a real run, not a described one).

## After state

- `/kit:gauntlet-proof-audit` audits every committed gauntlet record against its own evidence and reports verdicts.
- The first live run produces a verdict per record; a CLEAN corpus reports CLEAN with the enumeration list.
- `bash tests/test-meta.sh` stays green (new skill has its README row + FEATURES entry).

## Acceptance Criteria (global)

1. The skill's item-set command, run live, enumerates exactly the committed `*ROUNDS.md` records (count derived, never hardcoded), and NONE of the untracked room-copy ROUNDS files.
2. Tier-1 run against the live corpus produces a verdict for every enumerated record with quoted evidence per non-OK verdict.
3. A planted discrepancy is caught: take one record in a scratch copy, change its recorded verdict to contradict its committed `checker-output.txt` → the Tier-1 pass FLAGS it with both sides quoted; restore → OK.
4. `bash tests/test-meta.sh` green (README Skills row present, FEATURES regenerated).
5. The skill never rewrites a historical claim silently and never emits REMOVE (verified by reading the SKILL.md apply-mechanics section against this contract).

## Verification

```
# the item-set command lists only committed records:
git ls-files 'docs/verification/gauntlet/*/ROUNDS.md' 'docs/verification/gauntlet/*/*-ROUNDS.md' 'docs/verification/gauntlet/*/AB-ROUNDS.md'
# the live Tier-1 audit run (the acceptance artifact), recorded in the proof
# planted-discrepancy control per AC-3 on a scratch copy
bash tests/test-meta.sh
```

## Survival set (loop-engineering Step 2b; this is an audit-loop, not a revise-engine, so the set is the audit-loop's)

| Scenario | Answer |
|---|---|
| clean corpus | reports CLEAN with the enumeration list, no branch, no edits |
| a real discrepancy | FLAG with both sides quoted + a dated correction note on the record; PR lists it |
| untestable evidence | a record whose transcript was gitignored/pruned → UNSURE (UNTESTABLE), never REMOVE |
| gamed audit | the cheapest gaming: mark a record OK without opening its evidence → counter: every OK requires a spot-checked evidence citation (the audit-loop hard rule: no-evidence verdict downgrades to UNSURE) |
| interrupted | the enumeration is a written list (a queue); a resumed run re-verdicts from the top, verdicts are idempotent (read-only over records) |

## Out of Scope

Re-running probes, re-scoring, deleting or rewriting historical records, a blocking commit-time gate, a scheduled cron (cadence is on-demand-first; a schedule is the operator's to wire later), auditing non-gauntlet verification records.

## Decision Log

- Skill, not command/agent: siblings (doc-drift, backlog-reconcile) are skills; keeps the architecture inventory + agent roster untouched.
- Report-first, REMOVE-disallowed: a proof record is evidence; correcting it silently would defeat the audit. Discrepancies are flagged with a dated note.
- Tier-2 via kit:audit-scanner: the shared read-only scanner keeps the propose/apply split mechanical in an unattended cadence run.

## Open questions

None blocking. Whether a FLAG should append the correction note automatically or only propose it in the PR body is left to the implementer's read of the doc-drift apply-mechanics; default to proposing in the PR body + a note only on DANGER (an actively misleading record).
