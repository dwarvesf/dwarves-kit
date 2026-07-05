# Sub-goal 01: cc-harvest per-turn memory trigger

**Time budget:** ~2-3h · **Depends on:** none · **Branch:** feat/cc-elev-r4-01-harvest · **PR base:** main · **Merge policy:** auto

## Outcome

`cc-harvest` gains an OPTIONAL per-N-turns trigger so memory capture matches Hermes's memory
nudge (every ~10 turns), not just PreCompact/SessionEnd. It reuses the existing extractor +
dedup + ledger logic unchanged; only the trigger is new.

- A Stop-hook entry point that maintains a per-session turn counter and fires the existing
  harvest every N turns (N configurable, default 10).
- **Opt-in, default OFF.** Enabled via an env/config flag so current behavior is unchanged for
  anyone who does not turn it on.
- Detached/async (must not block the turn) and exit-0 always (a harvest never breaks a session).
- Single-flight: a harvest already in flight skips this turn's fire.

## Quality bar

Python stdlib only (cc-harvest's bar), no new deps, no daemon. Reuse the existing extraction +
dedup + ledger code paths; do NOT fork them. Counter keyed by `session_id`. Default off; when
off, zero behavior change. Never block, never non-zero exit.

## How to close the loop

- Add the Stop-mode + counter to `tools/cc-harvest/bin/cc-harvest` (a new flag/mode, e.g.
  `--stop-trigger`, gated on the opt-in flag), reusing the harvest function.
- Wire the Stop hook with `"async": true` (the cc-harvest hooks were made async 2026-06-19; match that).
- Smoke test: counter fires the harvest at the Nth turn, does NOT fire at turn < N (negative
  control), opt-in-off fires nothing (negative control), a slow harvest does not block (async neg control).
- Update `tools/cc-harvest/docs/proof-of-done.md` (new acceptance rows + run-table + the negative controls).

**Done =** cc-harvest fires its existing harvest every N turns via a Stop trigger, opt-in
(default off), async + exit-0, proven on a fixture + negative controls (turn<N no fire, opt-in-off
no fire, slow harvest no block), proof updated; on PR #NN.

## Scope edges

**In:** the per-turn trigger, counter, opt-in flag, Stop-hook wiring, tests, proof.
**Out:** the skill half (cc-self-improve, 02-04); changing the extractor/dedup/ledger; auto-flush.
**Not:** a daemon; a new model; writing a durable home (cc-harvest never does).

## Where to look

`tools/cc-harvest/bin/cc-harvest` (the harvest function + the existing PreCompact/SessionEnd
modes), `tools/cc-harvest/SPEC.md` + `README.md`, `tests/smoke.sh`, the `CC_HARVEST_*` env knobs,
`~/.claude/settings.json` Stop-hook pattern + the async flag added 2026-06-19, the cc-self-improve
single-flight lock design in SPEC-103 (same flock pattern).

## PR body

Outcome: cc-harvest optional per-N-turns Stop trigger (Hermes memory-nudge cadence parity); opt-in, async, exit-0.
Verify: smoke green with negative controls (turn<N no fire, opt-in-off no fire, slow harvest no block); real-run sample in the proof.
Roadmap: `_meta/megagoals/cc-elevation-r4/ROADMAP.md` (sub-goal 01).
