# Sub-goal 04: mutation smoke (advisory)

**Merge policy:** auto
**Time budget:** 4-6 hours (design-bearing + over-tested).
**Proof:** run-table WITH a COVERAGE-DELTA row AND a FALSE-POSITIVE negative control: a mutation injected into changed code makes a BITING suite FAIL (the suite catches the mutation) · a suite that does NOT bite (a mutation survives) is FLAGGED · a BITING suite is NOT flagged (the false-positive NC , the load-bearing one) · the smoke is ADVISORY , it WARNS, exit stays success, never blocks · bounded runtime (a small fixed mutation set on changed hunks only, not a full sweep). The COVERAGE-DELTA row names covered vs uncovered.
**Depends on:** 02 (branches off master-with-02).
Model: opus
Effort: high
**Branch:** feat/kri-04-mutation-smoke
**PR base:** master (post-02-merge)

## Outcome

An ADVISORY mutation smoke that catches the honesty gap coverage-delta (03) cannot see: tests that EXIST but do not actually bite. It mutates a line in the changed code and asks "does the suite fail?" A biting suite (mutation caught -> suite fails) is NOT flagged; a non-biting suite (mutation survives -> suite still green) IS flagged as a suite that does not really test its code. This is the HONESTLY-PROVEN pillar: a green suite that passes on mutated code is a false proof. It WARNS, never blocks (gate-zero: advisory by default). Default scope (open-fork 4): a CHEAP smoke , a small fixed set of mutation operators applied to the changed hunks only, first-surviving-mutation = flag , not a full mutation-testing sweep. Bounded runtime is a hard requirement.

## Quality bar

ADVISORY is a hard contract (warn + exit 0; prove a flagged run still exits 0, cannot block). The FALSE-POSITIVE negative control is load-bearing: a genuinely biting suite must NOT be flagged, or the smoke is noise. The runtime bound is load-bearing too , a full mutation sweep is out of scope; the smoke mutates only the changed hunks with a small operator set and stops at the first survivor. It must restore the code after mutating (no residue , prove the working tree is byte-identical after a run). Reuse the kit's test-runner detection (how verifiers already find + run the suite) rather than a new runner. Record its decision on the gate-ledger.

## How to close the loop

`bash lib/lane-classify.sh classify "add an advisory mutation smoke that flags a suite that does not bite on changed code"` then run that lane. DESIGN-BEARING: `/spec` + `/spec-validate` FIRST with a `## Design` block pinning (a) the mutation strategy (the operator set + that it targets changed hunks only + first-survivor-stops), (b) bite detection (run the suite pre-mutation green, mutate, re-run, survival = suite still green), (c) the advisory contract (warn + exit 0), (d) code restoration (mutate in a copy / restore after; the working tree must be clean after), (e) the runtime bound. Resolve open-fork 4. Gate-zero: advisory by default , stop for Han ONLY if /spec concludes a block is genuinely required. Then `/kit:test-plan` with the COVERAGE-DELTA row + the FALSE-POSITIVE NC (a biting suite is NOT flagged). Record gates via `bash lib/gate-ledger.sh record`. Assumptions: ROADMAP `## Assumptions` + open-fork 4.

**Done =** a mutation in changed code makes a biting suite fail, a non-biting suite is flagged, a biting suite is NOT flagged (false-positive NC green), the working tree is byte-identical after a run (no residue), the smoke is advisory (warns, exits 0, cannot block), runtime is bounded, COVERAGE-DELTA row + gates recorded, committed at phase boundaries.

## Scope edges

**In:** the mutation-smoke script + its lifecycle hook (advisory phase), the operator set on changed hunks, bite detection, code restoration, the runtime bound, the over-test suite (bite/no-bite + false-positive NC + advisory-cannot-block + clean-tree-after) + coverage-delta row.
**Out:** 03 coverage-delta (sibling); a full mutation-testing sweep (smoke only); the block promotion; 06 docs.
**Not:** a push-blocking gate (advisory); a full/slow mutation sweep (bounded smoke on changed hunks only); a new test runner (reuse the verifier's detection); leaving mutated code behind (restore + prove clean tree).

## Where to look

`lib/system-verifier` / `kit:system-verifier` + `kit:task-verifier` agents (how the kit detects + runs a project's suite , reuse that detection), `WORKFLOW.md` (where an advisory phase slots in, OFF the push blocker), `lib/proof-gate.sh` (the advisory-vs-block boundary), `lib/gate-ledger.sh` (record the decision; 01's `caught=` marker if merged), the effectiveness-audit "task-verifier rubber-stamps / a green suite that does not bite" thread (the motivation , this smoke is the check task-verifier structurally cannot be).

## PR body

Advisory mutation smoke: mutates a line in changed code and asks whether the suite bites. A biting suite is quiet; a suite where the mutation survives (tests pass on broken code) is flagged as a false proof. Cheap + bounded (a small operator set on changed hunks only, first survivor stops), restores the tree after (clean-tree-after proven). ADVISORY , warns, exits 0, never blocks. Catches the honesty gap coverage-delta cannot see. Verify: bite/no-bite + false-positive NC (biting suite NOT flagged) + advisory-cannot-block + clean-tree + coverage-delta row. Roadmap: ops-toolkit `_meta/megagoals/kit-run-integrity/ROADMAP.md`.

## Notes

<empty>
