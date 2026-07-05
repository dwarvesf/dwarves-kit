# SG-09: eval harness , prove the win by ablation (the proof)

Merge policy: gate (stacked; reviewed at end of wave with the rest, per Han 2026-06-29)
Time budget: ~1-2 sessions
Depends on: SG-12 (the benchmark fixture); to measure a lever, that lever must have landed
Stacking: LAST. Stacks on SG-05's branch (both ops-toolkit); branch off SG-05's branch so the ablation can reference the planner-split experiment. Top of the ops-toolkit stack for the end-review.
Model: opus
Effort: high

## Directional outcome
Prove the wave actually produced a better result, rigorously, not by a naive before/after (which
lies: tasks differ, you cannot re-run identical work, cache/nondeterminism confound). The proof
is a token+quality ABLATION over a fixed benchmark, against a PRE-REGISTERED threshold.

## Done =
An eval harness runs the SG-12 benchmark suite under an ablation ladder, each arm N>=3 trials,
and records per-arm TOKENS (cache_read/turn, total, by-model , read from the transcripts as in
the token-hygiene SG-05 experiment) AND QUALITY (pass-rate on each task's deterministic check +
turns-to-green + rework count). Results land in a dated `research/` note as an ablation table
with the pre-registered success threshold marked pass/fail per lever and overall. The forensic
stays read-only. Merged via PR.

Ablation ladder (each step isolates one lever):
```
baseline:        marathon + full subagent returns + Opus-all
+ orchestrator:  fresh session per sub-goal (the cross-sub-goal reset , needs the mini-mega-goal task)
+ distilled:     bounded subagent returns (SG-04)
+ routing:       per-sub-goal model/effort (SG-03)
+ handoff:       feed-forward handoff (SG-02)
```

PRE-REGISTERED success (set BEFORE running; do not move the goalposts):
- Full stack uses <= 70% of baseline TOTAL tokens on the suite, AND
- pass-rate parity (no regression on any task's deterministic check), AND
- turns-to-green not worse than baseline.
- Per-lever: a lever is KEPT only if its isolated delta is a positive token win at quality
  parity; a lever that does not clear that bar is reported and DROPPED (honesty over advocacy).

## Close the loop (verification)
```
bash experiments/token-eval-bench/run-ablation.sh        # the harness over the SG-12 suite
test -f research/2026-*-token-optim-v2-eval.md            # the ablation table + verdict vs threshold
```

## Scope edges
The harness + a `research/` note (+ optional read-only additions to `tools/token-forensic`). No
fabricated attribution. Control confounds: reset the fixture between trials (SG-12 owns reset),
hold model constant when measuring a non-model lever, same cache state across arms, report
median + spread (not one run). Guard against cherry-pick / survivorship / weak-check (count a
failed run as infinite cost; use the real acceptance bar).

## Where to look
SG-12 (the benchmark fixture + runner), `tools/token-forensic` (`--loops`, by-model), the
token-hygiene SG-05 experiment (per-arm transcript token reading as the method), the proof-design
in `research/2026-06-29-pi-swarm-comparison.md` is unrelated; the proof methodology is the
2026-06-29 measurement discussion captured in this goal file.

## Proof expectation
The ablation table (median +/- spread per arm: tokens + pass-rate + turns-to-green) with the
pre-registered threshold marked, plus a per-lever keep/drop verdict and the field observational
check (`token-forensic --loops` on a real run). This IS the mega-goal's terminal proof, so the
numbers must be captured and reproducible.

## PR body
feat: eval harness proving token-optim-v2 by ablation (tokens + quality vs a pre-registered
threshold). The mega-goal's terminal proof. Gated for review of the methodology.

## From the token-efficient note (2026-06-29)
- Cross-check the harness numbers against the built-in `/usage` (alias `/cost`, `/stats`), which
  attributes live session cost to skill/subagent/plugin/MCP. token-forensic = historical
  cross-session; `/usage` = live this-session; they should agree directionally.
- Name the real objective: COHERENCE, not raw token. `turns-to-green` + `rework` ARE the
  coherence proxy; a lever that cuts tokens but raises them is a coherence regression and FAILS
  the gate. See `research/2026-06-29-token-coherence-design.md`.
