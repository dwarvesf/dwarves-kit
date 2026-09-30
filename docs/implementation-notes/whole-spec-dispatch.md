# Implementation notes: whole-spec dispatch

Spec: `docs/specs/SPEC-369-whole-spec-dispatch.md`. Deltas from the spec only.

## Premise adaptations (rebased tree)

- **execute.md base size.** The rid tag change grew the rebased file to 36652 bytes (spec base `c5981b0f`: 36055). Every `commands/execute.md:NNN` citation in the spec pointed at the old text. I rebuilt the file from the contract and kept the lane re-check and validation preflight verbatim, except `task 1` became `the build` (three sites), as R9 asks.
- **WORKFLOW.md line numbers** moved after SPEC-368. I edited by section heading, inside the R11 list only: Build row and cycle diagram, V-model rows, roster section, completion contract, engines paragraph and diagram, hard-stops row, alternate-flows retry line.
- **`docs/MANUAL.md:257`** (`/kit:verify`, "per done task") stays: `/kit:verify` is out of scope.
- **`docs/guides/autonomy.md` row** says "advisory phase boundary" now. It meant lifecycle phases, not execute checkpoints, but the spec lists it, so the wording no longer promises a checkpoint.

## Decisions

- **Step order in execute.md.** Negative control and the proof-class gate run after the end verifiers and the sampled recheck, so the negative control reverts a build that already passed. R4 keeps both "verbatim" but fixes no position for them.
- **Mid-flight amend kept.** The amend path still says "amend at a checkpoint". With phase checkpoints gone, the checkpoint is the stop after the builder returns. `docs/WORKFLOW.md` "Mid-flight amend" prose is outside R11 and unchanged.
- **New suite carries its own negative control.** `tests/test-whole-spec-dispatch.sh` runs the same structural checks on `c5981b0f:commands/execute.md` and requires at least 5 of 7 red. It skips with a message when the base commit is absent (shallow clone). The spec's T11 shell command still works unchanged.
- **Fixture split.** `check.sh` covers AC-1 and AC-3. AC-2 (README names `hello.txt`) has no command on purpose, so a build reports it `confirmed-by: read` and the `(self-attested)` path gets exercised in the trial.
- **`fix-agent` spelled `kit:fix-agent`** in two execute.md spots: the bare-agent-name lint in `tests/test-meta.sh` flagged them.
- **test-meta-agent.sh.** The `NO_SPECIALIST` assertion is now an absence assertion, the golden inline-role-spec section is removed.

## Flagged, not changed

- `tests/fixtures/meta-agent/inline-role-spec.txt` is orphaned now. It sits outside this spec's Touches, so I left it.
- `docs/CHANGELOG.md`, dated specs, research, and verification records still describe 2b-0 and Mode C. They are history.

## Open questions

- Builder tier (spec open question 1) stays `sonnet`. N = 5 and the 6-task threshold need the post-ship A/B and tagged runs.
