# Implementation notes -- enforce-proof-of-done

Turn the proof-of-done discipline from advice into a wall at the ship/merge boundary,
spec-independently (so freeform /goal work is caught too), reusing the existing
ship-gate machinery.

## 2026-06-06 The existing ship-gate is spec-keyed -> the bridge needs diff-keying
- Context: `hooks/ship-gate.sh` (PreToolUse on `git push`/`gh pr create`) resolves branch slug -> SPEC file -> Lane -> `gate-ledger.sh check`. It FAILS OPEN when there is no spec (deliberately, "quality gate not safety gate").
- Problem: a freeform /goal that committed without a SPEC has no spec -> the existing gate never fires. That is exactly the bridge gap Han named ("fires regardless of whether the kit or a freeform /goal produced the change").
- Decision/Change: add `lib/gate/proof-ledger.sh` that classifies the BRANCH's aggregate diff (via `proof-gate.sh`, not via a spec) and requires a matching proof-of-done entry; wire it into `ship-gate.sh` as a second, spec-independent check, and widen the matcher to also catch `gh pr merge` / `git merge`.
- Why: the diff is the universal key every change has; a spec is optional. Keying on the diff makes the wall fire on kit and freeform work alike.
- Alternatives considered: a brand-new hook framework (rejected by scope: reuse the PreToolUse + gate-ledger pattern); hooking /goal's Stop hook (rejected: lives outside the kit, and a goal can finish without merging; the merge boundary is the universal choke point).

## 2026-06-06 Classification + validity rules (kept conservative, fail-open on ambiguity)
- class from diff: stateful if changed paths / commit subjects hit deploy/migration/data keywords; inert if the diff is only docs/markdown; else behavioral.
- behavioral pass = the branch diff added/modified a `docs/verification/*.md` that has BOTH a green/PASS entry AND a `NEGATIVE CONTROL` entry.
- stateful pass = a verification entry with a run AND (`rollback` or `[UNAVAILABLE`).
- inert = pass (a doc typo triggers no ritual, per the quality bar); an explicit `[PROOF OF DONE: exempt` marker is accepted, not required.
- override = `proof-ledger.sh override <slug> "<reason>"` logs a trace; check passes if an override is logged. Never a silent bypass.
- FAIL OPEN on genuine ambiguity (no repo, empty diff, no base, missing tooling) so a gate bug can never block unrelated work, mirroring ship-gate's stance.
