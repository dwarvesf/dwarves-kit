# Mega-goal: orchestrator-finish

**Destination:** the dwarves-kit orchestrator (`lib/queue/orchestrate.sh` + the ship/gate path) is hardened , token accounting complete on every path, gate coverage auditable, no unbounded transcript/secret exposure, and the TIER-4 close split so one verifier's blind spot can't pass the whole run.
**Quality bar:** boring and bulletproof. Every path that spends tokens records them; every gate that claims coverage can prove it; nothing writes an unbounded secret-bearing stream. Nobody debugging an overnight run has to guess whether the numbers are real.
**Stacking tool:** gh (stacked PRs)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-06

Single-repo (dwarves-kit, kit-adopted). Run the loop FROM dwarves-kit cwd so sub-goals use the SDD lane natively; the portable run contract is `~/.claude/skills/plan-for-mega-goal/references/OPERATE.md`. These are the orphaned spillover of the completed+archived `orchestrate-hardening` mega; each row is an existing dwarves-kit BACKLOG ID.

## Sub-goals

- [ ] 01-gate-vocab-align , ship-gate required-set names match what `/kit:*` actually records (ID-091), `auto`, PR #
- [ ] 02-tier4-split , TIER-4 close = 3 fresh verifier sessions + aggregator (ID-093), `auto`, PR #
- [ ] 03-wave-tokens , per-sub-goal TOKENS on the wave path + WAVE_CAP default reconciled (ID-094), `auto`, PR #
- [ ] 04-watchdog-tokens , WATCHDOG_STALL_SECS branch captures tokens to `$slog` (ID-097), `auto`, PR #
- [ ] 05-conductor-rid-check , conductor rejects a missing rid so gate coverage is auditable (ID-099), `auto`, PR #
- [ ] 06-orchestrate-sweep , tiny batch: stream.jsonl retention cap (ID-095) + `Model:` allowlist pre-flight (ID-096) + happy-path tmux kill-window cleanup (ID-098), `auto`, PR #

## Dependencies (only if non-trivial)

- 01 is independent (touches `hooks/ship-gate.sh` + `lib/gate/gate-ledger.sh`), base `main`.
- 02 → 03 → 04 → 05 → 06 are stacked (each base = the prior branch) NOT because of a logical dependency but because they all edit `lib/queue/orchestrate.sh`; stacking serializes the edits so they never conflict. Any can be built in any order logically; the stack is a merge-hygiene device.

## Assumptions

- Backlog IDs are preserved per sub-goal so the dwarves-kit board stays in sync; on ship, flip the row on `_meta/BACKLOG.md`.
- ID-092 (executing elsewhere), ID-084 (PR #125 in review), ID-037 (already shipped SPEC-096, status stale) are OUT of this mega.
- Terminus = build + merge (non-deployable internal hardening; no deploy/UAT gate). Stated intentionally so the missing deploy gate is not a forgotten step.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read _ pr; do
      gh pr view "$pr" --json state,reviewDecision,statusCheckRollup
    done
