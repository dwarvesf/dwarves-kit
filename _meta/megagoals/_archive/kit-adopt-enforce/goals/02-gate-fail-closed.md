# Sub-goal 02: ship-gate lane arm fails closed + install uses adopt

**Time budget:** 1-3 hours of loop work, after 01's PR is MERGED to dwarves-kit master
**Depends on:** 01 (install.sh's adopt path calls the new `/kit:adopt`; rebase this branch on master after 01 merges)
**Branch:** `feat/kit-adopt-02-gate` (in `~/workspace/tieubao/dwarves-kit`)

## Outcome

A spec-driven full-lane change can no longer slip past the ship boundary without recording its lane and its required gates. The exact failure from the growatt-tui session (spec ran, review skipped, push sailed through) becomes a blocked push. And installing the kit offers adoption instead of printing a manual `cp` tip nobody runs.

## Quality bar

Fail CLOSED only where it is safe and intentional: a repo that adopted the kit (has the proof marker) AND has an active spec AND no recorded lane. Everywhere ambiguous (no repo, no spec, no marker, missing tooling) the gate still FAILS OPEN so it can never block unrelated work. The block message is actionable: it names the missing lane/gate and the one command to fix it. push-to-main / force-push stay safety-gate's job, untouched.

## How to close the loop

Built through the kit's full lane (dogfood); gate-ledger records the sequence for this work.

Drive the hook directly with crafted stdin (no real push needed):

    # spec exists, NO lane recorded -> MUST block (exit 2)
    printf '{"tool_input":{"command":"git push -u origin feat/x"}}' \
      | bash hooks/ship-gate.sh ; echo "exit=$?"   # expect 2 in a repo state with a spec + no lane
    # lane + required gates recorded -> MUST pass (exit 0)
    bash lib/gate-ledger.sh record <slug> Spec ran ; bash lib/gate-ledger.sh record <slug> Review ran ; ...
    printf '{"tool_input":{"command":"git push -u origin feat/x"}}' \
      | bash hooks/ship-gate.sh ; echo "exit=$?"   # expect 0
    # fail-open safety: no spec / no marker -> exit 0 regardless
    # install.sh offers adoption:
    grep -q -i 'kit:adopt\|adopt' install.sh && ! grep -q 'cp .*AGENTS.md ./AGENTS.md' install.sh

Add a test under `tests/` that encodes both the block and the pass (and the fail-open cases). The full suite stays green: `bash tests/test-meta.sh` + the new test.

**Done =** a crafted-stdin push through `hooks/ship-gate.sh` returns exit 2 on a spec-with-no-lane state and exit 0 once the lane + its required gates are recorded; the fail-open cases (no spec / no marker) still return 0; install.sh routes adoption through `/kit:adopt`; a new `tests/test-ship-gate-fail-closed.sh` (or equivalent) plus the existing suite pass; gate-ledger records the full lane for this sub-goal. PR open + CI green.

## Scope edges

**In:** the lane-arm branch of `hooks/ship-gate.sh` (the part that today fails open on "no lane"), a new test for it, the `install.sh` block that prints the adopt tip.
**Out:** the proof-of-done arm of ship-gate (already works, leave it), the adopt command itself (01), any consumer-repo files (03).
**Not:** changing safety-gate.sh, push-to-main handling, or the proof-class logic; adding new required gates to a lane (use WORKFLOW.md's existing lane->gate map); making the gate enforce under non-CC runtimes. Touch the smallest surface that flips fail-open->fail-closed for the one safe case.

## Where to look

`hooks/ship-gate.sh` (the lane arm + its current fail-open comment that literally says "no lane -> fail open"), `lib/gate-ledger.sh` (how lanes + ran/override entries are recorded and read), `WORKFLOW.md` (the lane->required-gate map the gate consults), `tests/` (mirror an existing hook test's harness), `install.sh` (lines ~325-326, the manual cp tip). Worktree off dwarves-kit master (rebased on 01).

## PR body

Flips `ship-gate.sh`'s lane arm from fail-open to fail-CLOSED for the one safe case (kit-adopted repo + active spec + no recorded lane), so a full-lane change cannot ship without recording its lane and gates. Fail-open everywhere ambiguous is preserved. Replaces install.sh's manual `cp AGENTS.md` tip with the `/kit:adopt` path.

Verify: crafted-stdin push sim blocks (exit 2) on spec-no-lane, passes (exit 0) once lane+gates recorded, stays open on no-spec/no-marker; `tests/test-ship-gate-fail-closed.sh` + `tests/test-meta.sh` green.

Part of mega-goal kit-adopt-enforce. Builds on PR for 01 (the adopt command install.sh now calls). 03 (ops-toolkit adoption) consumes both.

## Notes

(empty)
