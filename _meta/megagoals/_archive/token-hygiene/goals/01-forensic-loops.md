# SG-01: token-forensic --loops view

Merge policy: auto
Time budget: ~1 session

## Directional outcome
`token-forensic` can isolate loop/mega-goal runs and report subagent cost, so the dominant
waste class is measurable per run. Implements SPEC-120.

## Done =
`tools/token-forensic/bin/token-forensic --loops --days 30` prints a Loops view
(high-turn sessions with cost, turns, avg ctx/turn) + a subagent-cost line, merged via PR.

## Close the loop (verification)
```
cd ~/workspace/<owner>/ops-toolkit/tools/token-forensic
./bin/token-forensic --loops --days 30                 # Loops view appears, flags 4800/3251-turn runs
./bin/token-forensic --loops --loop-min 1500 --days 30 # fewer flagged (flag works)
```
Proof-of-done updated with the captured run.

## Scope edges
Read-only preserved. No fabricated parent attribution (gate on a real JSONL field per
SPEC-120 DEC-001). Touch only `tools/token-forensic/`.

## Where to look
`tools/token-forensic/bin/token-forensic`, `tools/token-forensic/docs/specs/SPEC-120-token-forensic-loops.md`,
`research/2026-06-28-token-spend-forensic.md`.

## PR body
feat(token-forensic): --loops view (loop-run + subagent cost). SPEC-120. Read-only; proof
in docs/proof-of-done.md.
