# Implementation notes -- ID-398 failure-policy vocabulary

Backlog-driven (no `/kit:spec`, so this is the `<feature-slug>` form). Source: ID-398,
`docs/research/2026-07-25-acpx-absorption.md`.

## 2026-08-27 Vocabulary lands as a pattern doc, not a new verdict grammar

- Context: the row's approach text ("adopt close/escalate/continue as the named three-way
  exit of any judging node") could be read as replacing `task-verifier`'s `PASS` /
  `FAIL:fixable` / `FAIL:escalate` grammar or `/kit:review`'s `SHIP` / `FIX THEN SHIP` /
  `DO NOT SHIP` grammar. Both are widely wired (many readers grep the exact strings;
  `tests/test-outcome-emit-sweep.sh`, `lib/stats/src/stats/adapters.py`, dispatch.md, mega.md
  all key on them).
- Decision: `docs/patterns/failure-policy.md` defines close/escalate/continue as an
  INTERPRETIVE layer over existing verdict grammars (a mapping table), not a replacement.
  Nothing renames an existing verdict string.
- Why: renaming a wired verdict grammar is a different, much larger change than this row's
  `#f-lo` estimate and "contract additions to existing commands, no new engine" scope allow.
  The interpretive layer still gives every judging node a comparable failure-policy label.
- Alternatives considered: fork task-verifier's grammar to a 5-way PASS/FAIL:fixable/
  FAIL:escalate/FAIL:close/CONTINUE (rejected: breaks every existing reader of the 3-verdict
  grammar, well past this row's bound); do nothing until ID-394's ready-queue exists and wire
  it there only (rejected: the row explicitly also wants `/kit:execute`'s retry path and the
  review chain wired now).
- Impact: `commands/execute.md`'s retry-then-escalate path and `commands/review.md`'s root
  cause step both cite the pattern doc's mapping rather than inventing their own wording.

## 2026-08-27 close vs escalate at retry-exhaustion is a NEW distinction, not previously named

- Context: before this change, an exhausted retry loop (`/kit:execute` 2d) always said
  "ESCALATE to user" regardless of whether the underlying `task-verifier` reason was a design
  question or "the spec/task is wrong". Both cases needed a human, but for different reasons.
- Decision: `commands/execute.md` now tells the orchestrator to read the verifier's stated
  reason and label the exit `policy: escalate` (needs a human to choose a direction) vs
  `policy: close` (nothing to hand forward; the task should be dropped, not argued about) when
  reporting to the user and recording the Build-phase `OUTCOME` line.
- Why: `docs/patterns/failure-policy.md`'s own distinction ("which way should I continue" vs
  "should I even continue this at all") is directly actionable at this exact node, and it is
  the row's stated absorption target (acpx pr-triage's close verdict).
- Impact: the `## Execution complete` summary block gained a `Closed: [N]` line alongside
  `Escalations: [N]` (Step 4).

## 2026-08-27 Emitter: `policy=` as an optional field on the existing SPEC-129 OUTCOME marker

- Context: SPEC-129's `gate-ledger.sh outcome ... end caught=<bool>` is the kit's one existing
  additive-marker mechanism for judgment-node outcomes; `tests/test-gate-outcome.sh` AC7 pins
  additive-equivalence (every existing reader byte-identical whether OUTCOME is present or not).
- Decision: added `policy=<close|escalate|continue>` as a second, OPTIONAL KV on the same
  `end` line and round-tripped it through `outcome-read`. Omitting it reproduces the exact
  pre-existing line/output (no `policy=` token at all), verified by a new AC10 in
  `tests/test-gate-outcome.sh` plus a manual run confirming byte-for-byte parity.
- Why: "no new subsystem" -- the row explicitly wants this to land in the gate ledger's
  existing readers, and a second additive KV is the smallest change that fits the ledger's own
  additive-marker convention (mirrors how `caught=` itself was added).
- Alternatives considered: a new `| POLICY |` marker line (rejected: two lines to keep in sync
  per bracket, more surface than one optional field); a separate ledger file (rejected: a new
  store, explicitly out of scope).
- Impact: `lib/gate/gate-ledger.sh` `outcome`/`outcome_read`.

## 2026-08-27 Reader: lane-telemetry only, lib/stats left untouched

- Context: the row names "existing readers: lane-telemetry/stats". `lib/stats` is a separately
  tested Python pipeline (`lib/stats/src/stats/adapters.py::read_kit_gates`) with pinned fixture
  tests over the OUTCOME line's exact tuple shape; adding a `policy` column there means touching
  its schema and several downstream lenses' pinned fixtures.
- Decision: wired only `lib/telemetry/lane-telemetry.sh` (`_policy_agg` + a `report()` section)
  as the reader for this pass. `lib/stats` is unaffected, its adapters simply don't read the new
  field yet (additive, so nothing there breaks either).
- Why: the smallest deliverable that satisfies "emitter ships with its reader" without touching
  a second subsystem's pinned test fixtures for a `#f-lo` row.
- Alternatives considered: also extend `lib/stats/src/stats/adapters.py` (deferred, not done):
  a natural follow-up once a real policy-carrying corpus exists to design the lens against.
- Impact: `lane-telemetry.sh report` prints a "failure policy (close/escalate/continue, ID-398)"
  section when at least one run ledger carries a `policy=` field, silent otherwise (graceful-
  empty, matching the file's existing convention for `_token_agg`). `lib/stats` left for a later
  pass if the maintainer wants it.

## 2026-08-27 Root-cause-vs-symptom: `commands/review.md` only, not review-team's lenses

- Context: the row's approach item 2 wants root-cause-vs-symptom as "a separately-judged step
  in the review chain, not a clause inside one big review prompt". `commands/review.md`'s
  Correctness section previously had no root-cause language at all (it wasn't even a buried
  clause; `agents/task-verifier.md`'s FAIL:escalate description is the closest existing mention).
- Decision: added a new, separately-weighted "Root cause vs symptom" subsection to
  `commands/review.md` Step 2, with its own `root-cause:` finding-key prefix (matching the
  existing `stale-adr:` prefix convention), explicitly N/A for pure new-feature diffs.
- Why: `commands/review.md` is the single-pass entry point workflow-paths.md's "Check (review
  chain)" diagram names first; `commands/review-team.md` dispatches `agents/code-reviewer.md`
  for its architecture/test-coverage lenses, a separate agent file whose own root-cause pass
  is a reasonable follow-up but not required to satisfy this row's approach text.
- Alternatives considered: also add the step to `agents/code-reviewer.md` (deferred, not done:
  would widen the diff past this row's bound; flagged here for the maintainer).
- Impact: `commands/review.md` Step 2 only.

## Verification

- `bash tests/test-gate-outcome.sh` -- 25/25 (AC10 new, others unchanged).
- `bash tests/test-lane-telemetry.sh` -- 29/29 (4 new ID-398 assertions incl. a negative
  control that the failure-policy section stays silent with no `policy=` data).
- `bash tests/test-meta.sh` -- 808/815, identical 7 pre-existing failures reproduced on
  unmodified `master` at the same commit (confirmed via a side-by-side run in the main
  checkout, not a stash); none of the 7 are in a file this change touches.
- `bash tests/test-outcome-emit-sweep.sh` -- 49/51, identical 2 pre-existing failures
  reproduced on unmodified `master`.
