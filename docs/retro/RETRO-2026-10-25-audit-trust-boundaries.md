# Retro: audit trust-boundary fixes (#1023)
Date: 2026-10-25
Sprint: 2026-10-24 to 2026-10-25

## Metrics
- Tasks planned: 4 medium findings. Completed: 4. Deferred: 0.
- Commits: 1 squash (`9d81ae2c`). Files changed: 21 (+384, -21).
- Source: a source-only run of cloudflare/security-audit-skill against the kit (14 confirmed, 15 needs_validation).

## What worked
- Finding records carried trace, root cause and a smallest fix. The builder needed no spec to start.
- Each fix shipped with a regression test that went red on the old code (negctl PASS).
- One `kit:security-reviewer` lens before merge caught two more gaps, fixed or documented in the proof.

## What hurt
- The full-lane gates (think, design, spec, validate, test-plan) were recorded `skipped`. An external audit record has no ledger shape of its own.
- Strict symlink refusal in `adopt` now rejects `CLAUDE.md -> AGENTS.md`. Only `trials/buzz` hits it today.
- Two residual gaps stayed open: secrets-guard without `realpath` on PATH, and a symlinked parent of a staging file.

## Action items
- [ ] Decide whether an external audit record (findings.json entry) counts as the design record for a fix lane, so the gate shows `ran`, not `skipped`. -- owner: @tieubao -- deadline: 2026-11-08

## Lane telemetry
- The misfires the sweep listed (`run-all-keep-fail-output`, `vps-mon-ping-transport`, `wrap-absorbed-proof`) belong to other cycles. Accepted noise: not this cycle.

## Kit feedback
- `wrap land` ships a full-lane hard path without running the ship-gate. That is finding 14 of the same audit (low), still open.
