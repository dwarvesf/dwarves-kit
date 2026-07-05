# SG-03: per-sub-goal model/effort routing

Merge policy: gate
Time budget: ~1 session
Depends on: #81 (orchestrate.sh phase 1)
Model: sonnet
Effort: medium

## Directional outcome
The single biggest $ lever: each sub-goal runs on the right-priced model + effort instead of
Opus-for-everything (Opus = 86.5% of measured spend). Light sub-goals go to a cheaper tier;
Opus only does the hard work.

## Done =
`lib/orchestrate.sh` reads `Model:` / `Effort:` from each sub-goal's goal file and passes them
to the session (`claude -p --model <tier>` + effort), defaulting to inherit when absent.
`--dry-run` prints the chosen tier per sub-goal. `tests/test-orchestrate.sh` covers the parse,
the dry-run display, and the default-when-absent path. PR opened.

## Close the loop (verification)
```
bash tests/test-orchestrate.sh                          # routing parse + default assertions
bash lib/orchestrate.sh run <fixture-mixed-tiers> --dry-run  # shows per-sub-goal model/effort
```

## Scope edges
`lib/orchestrate.sh` parse + invoke only. The goal-file field convention is consumed here; the
GENERATOR that emits the fields is SG-08. Don't hardcode a model; read it per sub-goal.

## Where to look
SPEC-087 (add a routing section), `lib/orchestrate.sh`, the forensic by-model finding
(`research/2026-06-28-token-spend-forensic.md`), the 2026-06-29 routing discussion.

## Proof expectation
A run-table, plus a `--dry-run` capture showing different tiers per sub-goal. Full reviewable
proof (behavioral).

## PR body
feat(kit): per-sub-goal model/effort routing in the orchestrator. The biggest $ lever (Opus =
86.5% of spend). Gated for team review.
