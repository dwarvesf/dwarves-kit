# Implementation notes -- risk-gated-proof-of-done

Gate proof-of-done by a task's risk class: high-risk runs the real flow + records it
(+ negative control / rollback); low-risk records an explicit exempt marker. Reuses the
existing lane classifier rather than inventing a parallel system.

## 2026-06-06 Risk taxonomy = three proof classes on top of the lane classifier
- Context: `lib/lane-classify.sh` already maps a description to tiny|normal|full|bug|backfill. Han's axis is "behavior change / deploy / migration / data" vs "docs/cosmetic".
- Decision/Change: add `lib/proof-gate.sh` mapping a description to one of three PROOF classes: `stateful` (deploy/migration/data/persistent), `behavioral` (implementation that changes behavior), `inert` (docs/comments/cosmetic/pure text). It reuses `lane-classify.sh` (tiny/backfill -> inert) and adds a stateful keyword pass.
- Why: the *kind* of proof differs by class. Stateful = exercise on a copy/dry-run + rollback note; behavioral = run the real flow + negative control; inert = exempt marker. One helper, single-sourced from the lane rules.
- Alternatives considered: overload lane-classify with a 6th lane (rejected: lanes are about review depth, proof-class is about verification kind; different axes); a brand-new taxonomy ignoring lanes (rejected: duplicates the keyword rules).
- Precedence: inert first (a typo in a migration file is still a typo, mirroring lane-classify's tiny-first rule), then stateful, then behavioral default. Limitation noted: keyword classification can't perfectly tell a logic change from a comment edit; cosmetic-first is the safe, kit-consistent default and a human can override (detect-don't-dictate).

## 2026-06-06 Behavioral demo target + the [UNAVAILABLE] honesty
- Context: Done needs >=1 high-risk class with a REAL recorded primary-flow run; dwarves-kit has no deploy/migration/data flow.
- Decision/Change: the live behavioral-class demo is `lib/proof-gate.sh` itself , its primary flow is classification, which is real runnable bash. Record real `proof-gate.sh class "..."` runs + a negative control (break it -> wrong output). Mark `stateful` (deploy/migration/data) as `[UNAVAILABLE: no deploy/migration/data flow in dwarves-kit]` for the live run, defined in the convention rather than faked.
- Why: honest , do not fabricate a migration. The behavioral class is genuinely exercisable here; the stateful class is not.
