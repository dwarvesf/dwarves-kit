---
name: gauntlet-proof-audit
description: Use to audit the gauntlet records, "are the ROUNDS.md records honest", "verify the proof corpus", "check each run record against its evidence", "audit the gauntlet corpus", "is the gauntlet proof trustworthy", or a scheduled gauntlet-proof-audit cadence run. Enumerates every committed gauntlet run record (ROUNDS.md/AB-ROUNDS.md), verdicts each claim against its own committed evidence (markers, checker-output.txt, scrub, run-dir grammar), reports discrepancies. An audit-loop instance (docs/patterns/audit-loop.md). NOT for re-running probes or rounds (that is `/kit:gauntlet` itself), NOT for the corpus-level stats projection (that is `lib/gauntlet/stats.sh`), NOT for non-gauntlet verification records.
disable-model-invocation: false
---

# Gauntlet proof-audit

## Overview

Audit every committed gauntlet run record against its own persisted evidence and report the
result. This is the gauntlet-proof-audit instance of `docs/patterns/audit-loop.md`: a skeptic
pass over `docs/verification/gauntlet/*/ROUNDS.md` (and `AB-ROUNDS.md`), the eval corpus
`/kit:gauntlet` produces and `lib/gauntlet/stats.sh` projects into numbers. Neither of those
checks that a record's CLAIMS match its own EVIDENCE: a "clean=true" that never reconciles with
`checker-output.txt`, a findings count with no matching finding, a scrubbed key that leaked
anyway, a run-dir that drifted from the contract's naming. This skill never re-runs a probe and
never rewrites a historical record; it reports discrepancies for the operator.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | `git ls-files 'docs/verification/gauntlet/*/ROUNDS.md' 'docs/verification/gauntlet/*/*-ROUNDS.md' 'docs/verification/gauntlet/*/AB-ROUNDS.md'` (committed records only; a room copy's own ROUNDS is untracked and never enters the set) |
| Contract | every CLAIM in the record is backed by its committed EVIDENCE: markers well-formed; recorded verdict == committed `checker-output.txt`; findings count reconciles with the rows; scrub clean (no resolved credential VALUE in committed evidence; a bare `op://` pointer is allowed, not a leak); run-dir grammar conforms; a quoted finding string is present in the cited transcript |
| Evidence class | Tier 1: the committed record files themselves via grep/wc/diff. Tier 2: `kit:audit-scanner` reads a quoted finding against the transcript. Evidence gitignored as a room artifact (transcript pruned) = UNTESTABLE → UNSURE |
| Apply mechanics | REPORT-first: a genuine discrepancy is FLAGGED with a dated correction note appended to the record (never a silent rewrite of the historical claim); UNSURE/DANGER listed in the PR body; REMOVE is disallowed (a record is evidence, not deleted) |

## Process

1. **Branch first.** All edits ride an isolated branch. Auditing on master is the failure this
   skill exists to prevent.

2. **Enumerate.** Run the item-set command above. Write the list down before judging anything.
   The list is the queue; a resumed or scheduled run picks up where the last one stopped.

3. **Tier 1, mechanical pass, zero model cost, every record.** For each record, extract and
   check the mechanical claims:
   - marker well-formedness is DELEGATED, never restated here: run `bash lib/gauntlet/stats.sh`
     first (like doc-drift runs `test-meta.sh` first). Its Pass-1 sweep is the single enforcer of
     the `[[QL-VERDICT ...]]` / `[[AB-VERDICT ...]]` grammar across the whole corpus; a non-zero
     exit naming a file is a pre-confirmed marker finding. Do not re-implement the regex here, so
     the grammar cannot desync from its enforcer,
   - for a record whose rounds carry a per-round `checker-output.txt` (`round-N/submission/` or
     `round-N/`, or a campaign row's own dir), the recorded verdict (the round table's
     GREEN/RED cell, or the row's Checker column) matches that file's own `SUBMISSION:
     GREEN|RED` tail line, AND the marker's own `clean=true|false` agrees with that verdict
     (clean=true only when every scored round is GREEN); a marker that disagrees with the
     checker output is a finding even when the table cell happens to agree,
   - the marker's `findings=K` reconciles with the round's named findings (an inline `F1..FK`
     list, or `round-N/findings.md`'s own heading count); K=0 means no F-item is named,
   - scrub: no resolved credential VALUE in the record dir's COMMITTED files, an
     `ANTHROPIC_API_KEY=<hex/base64 value>` or any recognizable token shape (`sk-ant-`,
     `sk-`, `ghp_`, an assigned `<TOKEN>=<20+ opaque chars>`); a real value is DANGER, it is
     an actual leak. A bare `op://...` reference is NOT a leak: it is a pointer, allowed by
     estate secret-handling policy exactly as a path containing an ID is; do not flag it. Note
     it only if the operator asked for a pointer inventory, never as a finding on its own,
   - run-dir grammar: the directory name carries a `<YYYY-MM-DD>-<preset>-<slug>` shape for any
     record dated 2026-09 or later (pre-2026-09 dirs are grandfathered per `commands/gauntlet.md`,
     never flagged for the old shape alone).
   A Tier 1 failure is a finding with both sides quoted (the claim, the evidence). A record with
   no committed `checker-output.txt` for a round it claims a verdict on is UNTESTABLE on that
   axis, not OK and not a fabrication either: downgrade that axis to UNSURE, evidence quoted as
   "no checker-output.txt committed for round-N".

4. **Tier 2, judgment pass, model-read, only where it earns its cost.** Dispatch `kit:audit-scanner`
   (its tools roster physically cannot write) for two cases only: a record Tier 1 flagged (judge
   how deep the drift goes), or a quoted finding whose exact wording needs matching against the
   transcript it cites (`transcript.jsonl` / `transcript.md`). Skip Tier 2 for every record Tier 1
   cleared with no quote-matching need; most records never need it.

5. **Verdict each record** with the audit-loop grammar: OK / FLAG / UNSURE / DANGER. **REMOVE is
   never used**: a run record is evidence of what happened, not a doc that can go stale and get
   deleted. A verdict with no checkable evidence downgrades to UNSURE (a pruned/gitignored
   transcript, a room artifact never committed). DANGER is reserved for a record that actively
   misrepresents its own evidence (a claimed GREEN whose checker-output.txt says RED) where an
   operator reading ROUNDS.md at face value would be misled about the artifact's real state; a
   plain reference leak or an untestable axis is FLAG or UNSURE, not DANGER.

6. **Apply.** Report-first: every FLAG and UNSURE is listed in the PR body with its quoted
   evidence, for the operator to read. Only a DANGER verdict gets a correction note, appended to
   the record (never a rewrite of the original claim): a dated `## Audit correction (YYYY-MM-DD)`
   block naming the discrepancy and citing the contradicting evidence file. The original round
   table, verdict line, and markers are left untouched; the correction sits beside them.

7. **Verify.** Re-run the item-set command; it must still enumerate the same records (an audit
   pass reads, it never adds or removes a record). If any correction note was appended, confirm
   it parses as prose (no marker collision with `QL-VERDICT`/`AB-VERDICT`, `lib/gauntlet/stats.sh`
   must still run clean). Run `bash tests/test-meta.sh`: green, or the run is not done.

8. **Ship.** Commit, push, open a PR whose body lists every FLAG/DANGER with its evidence and
   every UNSURE for the operator. If every record verdicts OK, create no branch and report CLEAN
   with the enumeration list.

## Cadence

On-demand first: run after a gauntlet campaign lands, before citing corpus numbers in a report,
or when a record's honesty is in question. For a recurring pass, wire `/loop` or a schedule the
same way `doc-drift` does; there is no default cron, cadence is the operator's to wire.
