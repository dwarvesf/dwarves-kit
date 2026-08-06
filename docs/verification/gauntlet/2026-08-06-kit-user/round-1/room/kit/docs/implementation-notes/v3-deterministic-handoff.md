# Implementation notes: token-optim-v3 SG-02 deterministic-handoff

Delta from the sub-goal spec (`ops-toolkit/_meta/megagoals/token-optim-v3/goals/02-deterministic-handoff.md`).
Only records decisions/changes not already pinned by the spec.

## 2026-06-30 setup
- **PR base = `master`, not `main`.** The sub-goal spec says "PR base: dwarves-kit main"; the repo's
  actual default branch is `master`. Targeting `master`. Worktree `feat/v3-det-handoff` off `origin/master`.
- Cross-repo per pointer rule: SG-01's extractor is PORTED into the kit (no git-stack across repos).

## 2026-06-30 design decisions (delta from spec)
- **Opt-in via `DETERMINISTIC_HANDOFF=1`, default off.** The spec says "change how the handoff is
  GENERATED", not "always on". Default-off keeps the per-session `claude -p` invocation
  byte-identical (the kit's standing rule for `--stream`/watchdog), so this lands as a parallel
  path, not a behavior change. Matches the kit's conservative posture.
- **Input = the captured stream-json transcript.** The generator needs the finished session's
  transcript; the default invocation discards stdout. So when the flag is on, the run is captured
  to `.orchestrate/<id>.stream.jsonl` (reusing the `--stream` capture path; the live `tee` only
  happens under `--stream`). The deterministic-handoff path is NOT wired through the watchdog path
  (`WATCHDOG_STALL_SECS>0`); the two opt-in paths are independent. Acceptable: a run uses one or
  the other.
- **Read-pointers emit `path`, not `path:line`.** SPEC-087's HOT sample shows `file:line`. The
  ported extractor has no line data; fabricating `:line` would break the grounded-ness SPEC-087
  demands ("cannot become an optimistic lie"). We emit the real touched paths + edit counts.
- **`--date` is passed in (no clock in the generator).** Keeps output a pure function of inputs ->
  deterministic. The orchestrator passes `date -u +%F`; tests pass a fixed date.
- **DECISIONS.md append is idempotent** via a `<!-- handoff-gen:<sha> -->` content marker, so
  re-running on the same transcript appends nothing (append-only stays honest; determinism holds).
- **Session goal carried in the WARM ledger**, not the HOT handoff: the hot file is about the NEXT
  action, but the finished run's goal is load-bearing context, so it lands in DECISIONS.md under
  "What this run was" (also satisfies the SG-01 fidelity anchor set).
- **Proof posture (gate):** determinism + fidelity + no-LLM + orchestrator-wiring + default-unchanged
  are CAPTURED (44/44 tests). The live turns-to-first-correct-action A/B (real cold-resume sessions
  via the SG-12 bench) costs real Opus tokens; left as Han's gate-time confirmation. Box NOT flipped.
