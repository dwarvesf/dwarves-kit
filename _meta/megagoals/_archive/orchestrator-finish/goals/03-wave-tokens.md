# Sub-goal 03: wave-tokens (ID-094)

**Merge policy:** auto
**Time budget:** 1-3 hours of loop work
**Proof:** run-table showing per-sub-goal TOKENS captured on the wave (parallel) path. Rung 2 (negative control: a wave sub-goal whose token line is missing is caught).
**Design:** obvious
**Depends on:** 02 (stacked for orchestrate.sh merge hygiene, no logical dep)
Model: sonnet
**Branch:** fix/orchfin-03-wave-tokens
**PR base:** fix/orchfin-02-tier4-split

## Outcome

The wave (parallel) execution path captures per-sub-goal TOKENS exactly like the sequential path, closing the accounting hole when sub-goals run in a wave.

Verified reality (2026-07-06): the serial path extracts TOKENS (`gate-ledger.sh tokens`), but the wave reap loop only emits a `shipped` event + `_WAVE_LANDED`, never the token extraction , the header comment itself declares this a deliberate gap. (The original item also asked to "reconcile the WAVE_CAP default"; that half is DROPPED , the live default already agrees, `orchestrate.sh` `WAVE_CAP=2` == `commands/mega.md` "default WAVE_CAP=2". Only some stale internal COMMENTS still say "default 1"; fixing those comments is an optional trivial cleanup, not the point.)

## Quality bar

Every sub-goal's token spend lands in the ledger whether it ran solo or in a wave of five.

## How to close the loop

- Trace the wave reap loop in `orchestrate.sh` vs the serial token block; confirm where the serial path extracts TOKENS and that the wave path skips it.
- Add the per-sub-goal TOKENS extraction to the wave reap path, writing to the same ledger stream the serial path uses.
- Test (POSITIVE): simulate a 2-sub-goal wave; assert both token lines land in the ledger.
- Test (NEGATIVE CONTROL, operationalizes the Proof): run the SAME wave scenario against the pre-fix code (or the fix stubbed out) and assert ZERO token lines land , so the causal effect is demonstrated, not just post-fix presence.
- (Optional trivial cleanup: fix the stale "default 1" WAVE_CAP comments to "default 2".)

**Done =** the wave path writes per-sub-goal TOKENS for every sub-goal in the wave (captured 2-sub-goal-wave run-table showing both token lines), AND the negative control shows the pre-fix code produced ZERO wave token lines (the fix's causal effect is demonstrated).

**Stack-order note (advisor P5):** 03 (wave TOKENS) is stacked before 05 (wave START). Between 03 merging and 05 merging there is a transient window where wave TOKENS write to a rid log with no matching START , the exact symptom 05 closes, reintroduced for one stack-hop. ACCEPTED: the auto-bottom-up run lands 03→06 within the same loop, so the gap is minutes. If run out of order, land 05 before 03.

**Kit-adopted repo? Record the gates** (from dwarves-kit cwd, `lane-classify` → `normal`).

## Handoff on completion

1. ROADMAP `[x]` + PR #. 2. `HANDOFF.md` → 04. 3. `DECISIONS.md`. 4. Report, EXIT.

## Scope edges

**In:** the wave reap/collect path in `orchestrate.sh` and its (missing) token extraction.
**Out:** the sequential path's token capture (already works), the ledger format, the WAVE_CAP default (already consistent).
**Not:** changing WAVE_CAP's value, reconciling a default that already agrees, adding new token metrics, reworking the ledger.

## Where to look

The wave/parallel dispatch in `lib/queue/orchestrate.sh`, the token-extraction helper, `commands/mega.md`'s WAVE_CAP mention.

## PR body

Captures per-sub-goal TOKENS on the wave (parallel) path, closing the declared accounting gap where the wave reap loop skipped the serial path's token extraction (ID-094). WAVE_CAP-reconcile half dropped , the default already agrees (2==2). Verify: the 2-sub-goal-wave token run-table. Stacked on #<02 PR>; review after it. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes

- 2026-07-06: PR opened directly against `master`, not stacked on the 02 PR branch (dispatch prompt
  said "02 is already merged into master, so the stack has collapsed; base directly on master").
  This goal file's "PR base: fix/orchfin-02-tier4-split" / "Stacked on #<02 PR>" lines predate that;
  left them as-is (not owned by this sub-goal, and the conductor may want the history intact).
- 2026-07-06: implemented via a shared `_record_tokens` helper (used by both the serial loop and the
  wave reap loop) rather than duplicating the extraction block, so the two paths can never drift.
  Wave path recomputes the deterministic `$megadir/.orchestrate/<id>.stream.jsonl` path in the reap
  loop (the serial path's `_ROS_SLOG` global does not cross the wave's forked-subshell boundary).
- 2026-07-06: did the optional trivial WAVE_CAP-comment cleanup only where the comment was directly
  adjacent to code I touched (the `_wave_gate` docstring + the CAPTURE_TOKENS header block). Left
  three deeper narrative comments (near `_wave_converge`, and two in `cmd_run`'s size-dispatch loop)
  that also say "default WAVE_CAP=1" untouched: correcting them well would mean re-verifying older
  claims about ID-090/reachability that are outside this sub-goal's scope, higher risk than reward
  for an optional cleanup.
- 2026-07-06: pre-existing test flake noted (not caused by this change): `tests/test-orchestrate-
  wavefront.sh`'s FIFO-barrier concurrency cases ("wave_run g", "wave_run h2", BARRIER_T=4) time out
  under host load and are flaky on unmodified `origin/master` too (reproduced identically with zero
  diff applied). Out of scope for ID-094; flagged here for the conductor/06 (orchestrate-sweep).
