# Mega-goal: orchestrator-finish

**Destination:** the dwarves-kit orchestrator (`lib/queue/orchestrate.sh` + the ship/gate path) is hardened , token accounting complete on every path, gate coverage auditable, no unbounded transcript/secret exposure, and the TIER-4 close split so one verifier's blind spot can't pass the whole run.
**Quality bar:** boring and bulletproof. Every path that spends tokens records them; every gate that claims coverage can prove it; nothing writes an unbounded secret-bearing stream. Nobody debugging an overnight run has to guess whether the numbers are real.
**Stacking tool:** gh (stacked PRs)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-06

Single-repo (dwarves-kit, kit-adopted). Run the loop FROM dwarves-kit cwd so sub-goals use the SDD lane natively; the portable run contract is `~/.claude/skills/plan-for-mega-goal/references/OPERATE.md`. These are the orphaned spillover of the completed+archived `orchestrate-hardening` mega; each row is an existing dwarves-kit BACKLOG ID.

## Sub-goals

- [x] 01-gate-vocab-align , close the full-lane gate RECORDING gap , `build`/`design-critique`/`design-record` are required but no command records them (ID-091), `auto`, PR #204 , merged 11e04b1
- [x] 02-tier4-split , TIER-4 close = 3 fresh verifier sessions + aggregator (ID-093), `auto`, PR #205 , merged 4ff2f88 (macOS bash-3.2 RETURN-trap fix on re-review)
- [x] 03-wave-tokens , per-sub-goal TOKENS on the wave path (ID-094; WAVE_CAP half dropped , default already agrees), `auto`, PR #206 , merged 9380c8a
- [x] 04-watchdog-tokens , WATCHDOG_STALL_SECS branch captures tokens to `$slog` (ID-097), `auto`, PR #207 , merged f906fd4
- [x] 05-conductor-rid-check , the WAVE dispatch path emits a START/rid (it currently emits none) so gate coverage is auditable (ID-099, rescoped), `auto`, PR #208 , merged 78037b5
- [ ] 06-orchestrate-sweep , tiny batch: stream.jsonl rotation/redaction cap (ID-095) + `Model:` allowlist pre-flight (ID-096) + happy-path tmux kill-window cleanup (ID-098), `auto`, PR #209 (open, CI green, HELD for operator , gated-final)

## Validation (code-grounded, 2026-07-06)

All 8 backlog IDs were adversarially verified against the CURRENT `lib/queue/orchestrate.sh` + `hooks/ship-gate.sh` + `lib/gate/gate-ledger.sh` before launch (some backlog rows were suspected stale). Verdict: every item is REAL (the gap exists in the live code), none dropped. Four had stale/imprecise framing, now corrected in the goal files: 01 (recording gap, not a vocab typo; + a 3rd unrecorded name `design-record`), 03 (WAVE_CAP half dropped , default already 2==2), 05 (rescoped , serial warns-not-blocks, the real gap is the wave path emitting no START), 06/ID-095 ("unbounded growth" is false , files are per-id truncated-per-run; the risk is no rotation/redaction cap).

## Dependencies (only if non-trivial)

- 01 is independent (touches `hooks/ship-gate.sh` + `lib/gate/gate-ledger.sh`), base `main`.
- 02 → 03 → 04 → 05 → 06 are stacked (each base = the prior branch) NOT because of a logical dependency but because they all edit `lib/queue/orchestrate.sh`; stacking serializes the edits so they never conflict. Any can be built in any order logically; the stack is a merge-hygiene device.
- **Stack-order caveat (advisor P5, accepted):** 03 (wave TOKENS) lands before 05 (wave START). For the one stack-hop between 03-merge and 05-merge, wave TOKENS write to a rid log with no matching START (the symptom 05 closes). Accepted because auto-bottom-up lands 03→06 in the same loop (gap = minutes); if landing out of order, merge 05 before 03.

## Assumptions

- Backlog IDs are preserved per sub-goal so the dwarves-kit board stays in sync; on ship, flip the row on `_meta/BACKLOG.md`.
- ID-092 (executing elsewhere), ID-084 (PR #125 in review), ID-037 (already shipped SPEC-096, status stale) are OUT of this mega.
- Terminus = build + merge (non-deployable internal hardening; no deploy/UAT gate). Stated intentionally so the missing deploy gate is not a forgotten step.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read _ pr; do
      gh pr view "$pr" --json state,reviewDecision,statusCheckRollup
    done
