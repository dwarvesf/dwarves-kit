# Sub-goal 05: retro-cycle

**Merge policy:** auto
**Time budget:** 1-2 days of loop work (the mega's keystone)
**Proof:** (SPEC-195) run-table + ONE recorded LIVE run against the real ledgers staging >=0 candidates, every candidate citing lens + figure + rids; honest-empty NC (empty window -> "0 candidates", staging file untouched, exit 0); idempotency NC (immediate re-run stages nothing new); adversarial-check NC (a planted ungrounded proposal is dropped, captured). Rung 3: a fresh-context recheck-verifier re-executes the live-run command. COVERAGE-DELTA row required (over-test).
**Design:** bearing
**Depends on:** 01, 02, 04
Model: opus
**Branch:** `feat/loop-05-retro-cycle`
**PR base:** `feat/loop-04-surface-consol` (stacked; review after SG-04)

## Touches

lib/learn/propose* (never drain*), lib/learn/staging-format* (IF first to merge, per the shared-fixture rule), kit.toml [features], tests/test-config-reserved-keys* (the SPEC-188 lint) + tests/test-learn-propose*, lib/stats (window glue only if needed), _meta/megagoals/harness-loop/goals/ (the kit-retro template), docs/specs/SPEC-195*

## Outcome

`learn propose` closes the Learn leg per the auto-improvement design (docs/research/2026-07-05-auto-improvement-loop-design.md), three stages: (1) deterministic aggregate, the stats lenses over a window (last N megas / --days), producing the signal table; (2) interpret, ONE sonnet `claude -p` pass that turns signals into hypotheses, each citing lens + figure + rids, prompt gets ONLY the aggregate + the board/staging for dedup; (3) an adversarial check per proposal (claim-verifier pattern, refute-if-uncertain drops it), then a deterministic staged write of survivors as `## [staged]` blocks (the byte-format add-backlog already reads). Dedup HARD against open rows, staged rows, `[expired]`, and rejected/dropped rows; dedup keys are ANCHORED matches (`| <key> |` style), never bare substrings, per the SPEC-144 lesson (a short key wrongly matching as a suffix of a longer rejected one, `docs/implementation-notes/spec-144-review-findings-memory.md`), with an NC mirroring SPEC-144's Run-3 fixture. The interpret + adversarial passes emit their token cost via the existing TOKENS marker so the weekly cycle's spend is observable in stats. Whichever of SG-05/SG-06 merges FIRST lands the shared staging-block format fixture + parse helper in lib/learn/ (one definition of the block edges); the second consumes it. The run also SURFACES (never processes) the starvation counters: learned-ledger queued count + oldest age, `learn debt list` count, AND the memory-staleness signal (`stats memory-sweep` runs in the aggregate stage; dead-path/stale-note counts appear as cited signals, e.g. a "12 memory notes reference dead paths" line that can become a proposal). Memory REPAIR stays out: ID-100 context-lifecycle is the owner; this is the weekly tripwire until it ships. The recurring vehicle is the drafted kit-retro contract, shipped as a goal TEMPLATE the weekly consumer LaunchAgent instantiates as `kit-retro-YYYY-WW` (date-suffix IS the recurrence; zero queue changes). `[features] auto_improvement` flips to `[impl]` and the SPEC-188 lint is amended in the same PR so the reserved-keys guard stays honest.

## Quality bar

Propose-only, cite-the-number, dedup-hard: those three disciplines ARE the feature; an ungrounded "maybe improve X" reaching the staging file is a P0 defect. Trust is the product: a rejected proposal that reappears next week kills the loop's credibility permanently.

## How to close the loop

1. Spec (SPEC-195) via the full lane; Design block from the research doc's 3-stage diagram; /kit:spec-validate.
2. Build; goal-file template carries the drafted kit-retro contract's three steps + state line + RUNNER markers, wc -m < 4000.
3. LIVE run: `bin/learn propose --days 30` against the real XDG ledgers; capture the staged diff; verify every block cites evidence.
4. The three NCs above, each captured in the proof-of-done.
5. Lint: amended SPEC-188 test green (auto_improvement now legally read; team.* still inert).
6. Fresh recheck-verifier re-executes step 3's command.

**Done =** live run + all three NCs + amended lint green + goal template < 4000 chars + recheck PASS, all in the committed proof-of-done.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HANDOFF.md: next = 06 or 09; note for 10: the LaunchAgent runbook must reference the goal template path. 3. DECISIONS.md: window default, dedup key chosen, model/effort of the interpret pass. 4. Note on ops-toolkit ID-273's row that kit-retro moved here (one line, rides SG-10's housekeeping if easier). 5. EXIT.

## Scope edges

**In:** learn propose (3 stages + surfacing counters), the goal template, the features flip + lint amendment, its spec.
**Out:** the LaunchAgent plist itself (consumer-side, prepared in 10), add-backlog changes (06), Hermes cards (NOTES successor).
**Not:** auto-promotion in ANY form, editing kit/skills/CLAUDE.md from the cycle, a second ledger, per-run retro changes (/kit:retro untouched).

## Where to look

docs/research/2026-07-05-auto-improvement-loop-design.md (the architecture, verbatim); the drafted contract at ops-toolkit `_meta/megagoals/kit-wiring/goals/kit-retro.md`; `docs/implementation-notes/spec-144-review-findings-memory.md` (the anchored-dedup lesson); `lib/stats` README (lenses, env sources, the propose byte-format anomalies already writes); `hooks/backlog-stage.py` render_candidate (the staged block shape); kit:claim-verifier agent (the refute pattern).

## PR body

`learn propose`: ledger -> cited, deduped, adversarially-checked backlog proposals behind the unchanged add-backlog gate; kit-retro-YYYY-WW recurring goal template; [features] auto_improvement -> [impl] + SPEC-188 lint amended. Verify: live-run diff + 3 NCs in the proof-of-done. Stacked deps: SG-01 ADR, SG-02 timing, SG-04 lib/learn. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-05.

## Notes
