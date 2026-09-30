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

## Review fixes (lead-approved amendment AMEND-001)

- **Slice boundaries.** The task-verifier pass runs after each fork-risk slice, not only at the end.
- **Full lane.** `recheck-sample.sh decide "$RID" 1` rechecks every PASS; the normal lane keeps the configured sample.
- **Sampling moved to a script.** `lib/gate/recheck-sample.sh` keys on the rid (the HEAD sha could move with the builder's own commits), guards N=0 and non-numeric N, reads the root-only default itself, and records the decision. The spec's R5 text now says so.
- **Recheck scope.** One `decide` per run covers every task-verifier PASS, slice-boundary passes included. A slice-boundary pass sees that slice's tasks and the diff since the previous boundary. Edge cases 5 and 6 in the spec now state the full-lane override: `recheck_sample = 0` disables sampling on the normal lane only.
- **Checkpoint wording.** The amend path's checkpoint is the stop after the builder or a continuation returns. The summary template shows `key=<rid>`.
- **Continuation.** The lead checks `PROGRESS:` ids against `git log <base>..HEAD` (task commit subjects carry no IDs, so it matches subjects to task descriptions). A builder that dies without `PROGRESS:` gets a continuation, never fix-agent. Cap: 2 continuations, then escalate. The stray `<task-slug>` is now `<spec-slug>`.
- **Check-edit as a script.** `lib/gate/check-edit.sh` also flags modified test files that exist at the base ref, and `check-weakened:` lines for added skip, xfail, `.only`, `|| true`, and commented-out asserts. It limits the weakened scan to test and named files, because `|| true` is normal in plain scripts. New test files are not flagged.
- **LANE-SUGGEST.** The escalate call keeps stderr in a temp file and the Go? checkpoint shows the line. Prose now says spec words never pick `full`.
- **Self-attested recheck** re-reads the cited `file:line`, runs the nearest executable check, or logs `unverifiable`.
- **Touches** gained `lib/gate/recheck-sample.sh`, `lib/gate/check-edit.sh`, `lib/gate/README.md`. The new behavior tests live in `tests/test-whole-spec-dispatch.sh`, so no new test file.
- Registry row now says Step 3. The `model: opus` on the task-verifier line reads as conditional.
- Testing the scripts wrote three `recheck:` action lines for rid `whole-spec-dispatch` into the real ledger before I switched to a temp `DWARVES_KIT_LOG_DIR`. They are noise.

## Flagged, not changed

- `tests/fixtures/meta-agent/inline-role-spec.txt` is orphaned now (nothing reads it). It stays per the never-delete rule and sits outside this spec's Touches.
- `docs/CHANGELOG.md`, dated specs, research, and verification records still describe 2b-0 and Mode C. They are history.

## Open questions

- Builder tier (spec open question 1) stays `sonnet`. N = 5 and the 6-task threshold need the post-ship A/B and tagged runs.
