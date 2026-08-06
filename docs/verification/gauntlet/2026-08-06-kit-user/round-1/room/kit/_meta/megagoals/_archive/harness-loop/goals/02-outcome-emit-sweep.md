# Sub-goal 02: outcome-emit-sweep

**Merge policy:** auto
**Time budget:** 2-4 hours of loop work
**Proof:** run-table (SPEC-193): a fixture run whose ledger shows OUTCOME start/end brackets for every phase the lane ran, `stats mega-durations` returning a non-empty wall-time row for it, PLUS the negative control: a legacy ledger with no brackets renders honest-empty (no fabricated zero rows). Ladder rung 2.
**Design:** obvious
**Depends on:** none
Model: sonnet
**Branch:** `feat/loop-02-outcome-emit`
**PR base:** master

## Touches

commands/*.md (gate-recording steps), lib/queue/orchestrate.sh (emit points), lib/gate/gate-ledger.sh (only if a helper is needed; the `outcome` verb exists per SPEC-129), tests/

## Outcome

The OUTCOME timing brackets (SPEC-129) fire at every gate call site that today skips them, so `stats mega-durations` and `stats digest` time-to-done read real numbers on new runs instead of honest-zero. The additive-marker invariant holds untouched: OUTCOME lines still cannot satisfy any gate check.

## Quality bar

Boring emit plumbing. Zero new markers, zero schema change, zero behavior change to any gate decision; only coverage of an existing emitter. A reviewer should be able to diff commands/*.md and see the same one-line bracket pattern at each site.

## How to close the loop

1. Inventory: `rg -n 'gate-ledger.sh (record|override)' commands lib | rg -v outcome` vs sites already bracketed; the delta is the work list, recorded in the spec.
2. Wire brackets; run a full fixture lane (the tests' golden run) and capture its ledger slice showing paired `OUTCOME | <phase> | start/end`.
3. `uv run stats mega-durations` over the fixture root: non-empty row, plausible dur.
4. NC: point stats at a pre-change ledger fixture: honest-empty output, exit 0.
5. Suite: `bash tests/run-tests.sh` (or the repo's runner) green; the additive-marker tests specifically.

**Done =** the inventory delta is fully bracketed + fixture run-table committed in the proof-of-done + NC captured + the standing coverage lint green (with its own NC: a planted unbracketed site fails it) + suite green.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HANDOFF.md: next dispatchable = 03 (or 07 if 03 done); first action = `gh pr view 226`. 3. DECISIONS.md: list the call sites deliberately left unbracketed (if any) + why. 4. Report in records, EXIT.

## Scope edges

**In:** emit coverage at existing gate sites, fixture + NC tests, PLUS the coverage made PERMANENT: the inventory-delta grep from step 1 ships as a standing test (a new gate call site without a paired OUTCOME bracket fails CI), built on a small shared `tests/lib/contract-lint.sh` helper (grep-diff-against-manifest, parameterized) that SG-08's registry lint reuses.
**Out:** new stats lenses, the dashboard (07), any marker schema change.
**Not:** "while here" refactors of gate-ledger.sh, a retention/rotation feature, backfilling old ledgers (they stay honest-empty forever, by design).

## Where to look

SPEC-129 (the emitter contract), `lib/gate/gate-ledger.sh` outcome verb, the commands' gate-recording steps, `lib/stats/src/stats/cli.py` mega-durations docstring (names the coverage gap).

## PR body

Wire SPEC-129 OUTCOME brackets at the gate call sites that skip them; mega-durations/digest time-to-done become non-empty on new runs. Verify: proof-of-done run-table (fixture ledger slice + stats row + honest-empty NC). Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-02.

## Notes
