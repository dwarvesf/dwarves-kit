# SG-11: loop robustness (stalled-watchdog + liveness + tool-baked guardrails)

Merge policy: gate
Time budget: ~1 session
Depends on: #81 (orchestrate.sh phase 1)
Model: sonnet
Effort: medium

## Directional outcome
Make the orchestrator self-healing for unattended runs: detect a wedged sub-goal session,
prove liveness without a daemon, and nudge against the common wrong moves , all borrowed from
pi-swarm's hard-won coordination guardrails.

## Done =
`lib/orchestrate.sh` gains: (1) a stalled-watchdog , a running sub-goal session with no
progress signal in N minutes is flagged `stalled` (and, if configured, re-run or surfaced for
the human); (2) PID-liveness , the orchestrator knows if a spawned `claude -p` is still alive
via a process probe (not a heartbeat daemon), and reconciles a dead session (release its
in-progress state, do not advance its box); (3) tool-baked guardrails , the orchestrator warns
on the wrong move (e.g. advancing past a sub-goal whose box was not flipped, running a gate
sub-goal in auto context). `tests/test-orchestrate.sh` covers stalled-detection, dead-session
reconciliation, and at least one guardrail. PR opened.

## Close the loop (verification)
```
bash tests/test-orchestrate.sh            # stalled + dead-PID reconcile + guardrail assertions
```

## Scope edges
`lib/orchestrate.sh` + its test. No daemon (liveness is a probe, per the pi-swarm thesis). The
watchdog must be reversible/advisory by default (flag, do not silently kill). Do not duplicate
SG-10's event log; reuse it for the progress signal if present.

## Where to look
pi-swarm: `store/shared.ts` (`isAgentActive` PID-probe + `cleanupStaleTaskClaims`),
`lib/status.ts` (`computeStatus` active->idle->away->stuck), `queries.ts:167` (stalled =
no-progress-in-N-min), `handlers/spawn.ts` (anti-pattern guardrail warnings). Our
`lib/orchestrate.sh` (#81). Research note `research/2026-06-29-pi-swarm-comparison.md`.

## Proof expectation
A run-table covering stalled-detection, dead-session reconciliation, and a guardrail warning.
Full reviewable proof (behavioral).

## PR body
feat(kit): orchestrator loop-robustness , stalled-watchdog + PID-liveness + tool-baked
guardrails (borrowed from pi-swarm). Gated for team review.
