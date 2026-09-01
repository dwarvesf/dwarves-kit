# Sub-goal 03: coverage-delta gate (advisory)

**Merge policy:** auto
**Time budget:** 4-6 hours (design-bearing + over-tested).
**Proof:** run-table WITH a COVERAGE-DELTA row AND a FALSE-POSITIVE negative control: an under-tested behavioral diff (changed source, no matching test change) is FLAGGED · a well-tested diff (source + matching test change) does NOT trip (the false-positive NC , the load-bearing one) · a docs-only / test-only diff is exempt (nothing to flag) · the gate is ADVISORY , it WARNS, exit stays success, it never blocks the push · the warning names WHAT is under-covered. The COVERAGE-DELTA row names covered vs uncovered scenarios.
**Depends on:** 02 (branches off master-with-02).
Model: opus
Effort: high
**Branch:** feat/kri-03-coverage-delta
**PR base:** master (post-02-merge)

## Outcome

An ADVISORY coverage-delta gate: for a behavioral diff, it asks "did the test surface move the right way?" and FLAGS (warns) an under-tested change , directly serving the benchmark's headline finding (§2: "the coverage gap is the real problem, not the process; coverage is opt-in"). A well-tested diff (source change paired with a test change) does NOT trip. It WARNS, never blocks (gate-zero: advisory by default; a block needs Han's bless). Default signal (open-fork 3): a language-agnostic diff-line heuristic , changed non-test source lines vs added/changed test lines in the same diff , portable across the kit's polyglot targets, with a hook to a real coverage runner where one is configured.

## Quality bar

ADVISORY is a hard contract: the gate emits a warning and returns success , it must be impossible for it to block a push in its default form (prove it: a flagged diff still exits 0). The FALSE-POSITIVE negative control is load-bearing , a genuinely well-tested diff must NOT be flagged, or the gate is noise that trains the operator to ignore it. Over-test the boundary: under-tested -> flag, well-tested -> quiet, docs/test-only -> exempt. Reuse the kit's existing diff plumbing (`git diff` helpers the reviewers/verifiers already use) rather than a new differ. Record its decision on the gate-ledger (via 01's outcome marker if merged, else `record`).

## How to close the loop

`bash lib/lane-classify.sh classify "add an advisory coverage-delta gate that flags under-tested behavioral diffs"` then run that lane. DESIGN-BEARING: `/spec` + `/spec-validate` FIRST with a `## Design` block pinning (a) how the delta is computed (the diff-line heuristic + its exempt classes: docs-only, test-only, generated), (b) the advisory contract (warn + exit 0; the exact stdout shape), (c) where the gate hooks into the lifecycle (a phase boundary / the verification pipeline, NOT the push blocker), (d) the real-coverage-runner hook for configured targets. Resolve open-fork 3. Gate-zero: advisory by default , stop for Han ONLY if /spec concludes a block is genuinely required. Then `/kit:test-plan` with the COVERAGE-DELTA row + the FALSE-POSITIVE NC (a well-tested diff does NOT trip). Record gates via `bash lib/gate-ledger.sh record`. Assumptions: ROADMAP `## Assumptions` + open-fork 3.

**Done =** an under-tested behavioral diff is flagged, a well-tested diff does NOT trip (false-positive NC green), docs/test-only diffs are exempt, the gate is advisory (warns, exits 0, cannot block), the warning names what is under-covered, COVERAGE-DELTA row + gates recorded, committed at phase boundaries.

## Scope edges

**In:** the coverage-delta gate script + its lifecycle hook (advisory phase), the diff-line heuristic + exempt classes, the real-runner hook, the over-test suite (under/well/exempt + false-positive NC + advisory-cannot-block) + coverage-delta row.
**Out:** 04 mutation smoke (sibling); the block promotion (advisory only unless Han blesses); 06 docs.
**Not:** a push-blocking gate (advisory by default); a full coverage subsystem per language (a portable heuristic + an optional runner hook); re-implementing the diff plumbing.

## Where to look

`WORKFLOW.md` (the lanes + the gate at each phase boundary , where an advisory gate slots in WITHOUT touching the push blocker), `lib/proof-gate.sh` + `hooks/ship-gate.sh` (how a gate is wired; the ADVISORY-vs-BLOCK boundary , keep this OFF the block path), the `kit:code-reviewer` / verifier agents' `git diff` usage (the diff plumbing to reuse), `lib/gate-ledger.sh` (record the advisory decision; 01's `caught=` marker if it merged first), benchmark §2 (the coverage-gap motivation).

## PR body

Advisory coverage-delta gate: flags an under-tested behavioral diff (changed source with no matching test change), quiet on a well-tested one. Language-agnostic diff-line heuristic (portable across the kit's targets) + a hook to a real coverage runner where configured. ADVISORY , warns, exits 0, never blocks (a block needs a separate bless). Serves the benchmark's coverage-gap finding. Verify: under/well/exempt boundary + false-positive NC (well-tested does NOT trip) + advisory-cannot-block + coverage-delta row. Roadmap: ops-toolkit `_meta/megagoals/kit-run-integrity/ROADMAP.md`.

## Notes

<empty>
