# Implementation notes: gate-ledger plan-record

Delta from `docs/specs/SPEC-287-gate-ledger-plan-record.md`. What the spec already states is not repeated here.

## 2026-09-13 21:40 Refuse-before-write by replay, not by copied rules

Context: the grill-reason enum and the distinct-override-reason guard live inside `record()` and `override()` and fire only at write time. The spec asks for validate-everything-then-write without restating those rules.
Decision: replay the whole disposition set twice. The first pass points `KIT_LEDGER_DIR` and `RUNS_DIR` at a mktemp dir seeded with a copy of the rid's real log; only a clean replay runs against the real dir.
Why: one source of truth for each rule. The seed copy is what lets the dry run see prior overrides, so a reason reused from an earlier session is still refused.
Alternatives: a validation function that mirrors the two guards. Rejected because it drifts the moment either guard changes.
Impact: two passes per call, sub-second. The scratch dir must be restored on every exit path; the reviewer lens checks this.

## 2026-09-13 21:40 Exit code answers "did the write happen"

Context: the spec says the verb prints `check`'s verdict after writing.
Decision: return 0 after a successful write and print the verdict; never return `check`'s code. A refusal propagates the underlying code (64 for an argument fault or a bad grill reason, 65 for a reused override reason).
Why: `ship` may be omitted by design and is required on most lanes, so returning `check`'s code would make the sanctioned happy path exit non-zero.

## 2026-09-13 21:40 Reason parsing splits on the first colon and trims one leading space

Context: `grill: reason=home-turf: why` and `grill:reason=home-turf: why` are both natural to type.
Decision: split `<phase>:<reason>` on the first colon, trim a leading space in the reason.
Why: without the trim the grill enum check rejects the spaced form.
Impact: `--ran` accepts a bare phase (matching `record`), `--skipped` and `--override` require a reason.

## Open questions

- `tests/test-meta.sh` fails one pre-existing pin on master (`sweep pin: zero gate-ledger rid call sites say spec-slug`, 15 found in commands/, AGENTS.md, docs/WORKFLOW.md); this branch touches none of those files. Someone should fix the pin or the call sites in their own PR.
