# NOTES, orchestrator-finish

## Active blockers

<none yet>

## Proposed additions

- 2026-07-06: successor mega `kit-closeout`, verification absence-checks (ID-020) + hooks-as-fallback layering contract (ID-036) + loop QA-gate (ID-012 P2); all "shipped-but-reopened" full-lane items needing investigation. Scaffold when it starts.
- 2026-07-06: ID-002 (absorb ops-toolkit skills/hooks into the kit), fold under `kit-wiring`, not a fresh mega.
- 2026-07-06: ID-037 status is stale (`validated` but shipped SPEC-096), flip its BACKLOG row to shipped out-of-band.
- 2026-07-06 (advisor P6): a single lint asserting the token/START/cleanup invariants over EVERY dispatch/exit branch of orchestrate.sh , converts the 3 point-fixes (03/04/05) into a permanent regression fence so a new dispatch mode can't silently reintroduce the class. HIGH leverage.
- 2026-07-06 (advisor P6): audit orchestrate.sh for a 4th/5th silent-exit path (abort/Ctrl-C trap, goal-file-missing early return, dup-rid collision) with the same no-token/no-START/no-cleanup shape , audits miss siblings by construction; cheap now while the file is open across 5 branches. MED-HIGH.
- 2026-07-06 (advisor P6): a synthetic "chaos" e2e run as the mega's CLOSING proof , one invocation triggering wave + watchdog-stall + wave-dispatch + TIER-4 dissent together, asserting token totals reconcile and every rid has a ledger row. The composite none of the 6 Rung-2 proofs exercise; closes the gap between "6 fixes proven" and "overnight numbers trustworthy". HIGH.
- 2026-07-06 (advisor P6): after the lint (above) exists, wire it into hooks/ship-gate.sh as a permanent precondition for PRs touching lib/queue/orchestrate.sh (self-enforcing fence). MED, depends on the lint landing.
- 2026-07-06 (advisor P6): consider merging 04 (watchdog-tokens) + 05 (wave-START) into one PR (adjacent, both trivial) to cut stack depth , MED, pure process efficiency (kept separate for now: distinct paths/NCs).

## Event log

2026-07-06 · scaffolded · orchestrator-finish, 6 sub-goals (5 normal + 1 tiny-sweep), from the orphaned orchestrate-hardening spillover (ID-091,093,094,095,096,097,098,099)
2026-07-06 · advisor pre-launch · P5 critique + P6 over-suggest run. P5 verdict: 1 CRITICAL (flat lib paths in POINTER + goal 01 , FIXED, all subdir now) + 2 MAJOR (stack-order 03-before-05 gap , noted-accepted; goal 03 NC not operationalized , FIXED with a pre-fix-shows-zero clause) + 1 MINOR (goal 02 Depends-on fragment , tidied). P6: 5 suggestions → ## Proposed additions. Scaffold now launch-ready.
