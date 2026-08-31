# Proof of done: gauntlet room scrub + watch/campaign hardening

Date: 2026-08-31. Branch: fix/gauntlet-room-scrub. Source: retroactive security lens on #456 (1 HIGH, 2 MEDIUM).

## Recorded run

- Command: `bash tests/gauntlet/cleanroom/persist-check.sh`
- Exit: 0
- Output: `PASS leg A (exit=7, CARD.md persisted)` / `PASS leg B` / `PASS leg C (key scrubbed to <REDACTED-KEY>)` / `PERSIST-CHECK: GREEN`
- Command: `bash tests/gauntlet/tier1.sh`
- Exit: 0
- Output: `TIER1: GREEN` (lint glob covers all four touched scripts)
- Verdict: PASS

## Negative control

Leg C IS the measured red arm: its probe (`echo "$ANTHROPIC_API_KEY" > /work/leak.txt`) run against the pre-fix runner persists the literal canary into the record tree (the HIGH's exact exploitation path, public repo); post-fix the persisted file carries `<REDACTED-KEY>` and a repo-wide grep for the canary is empty. Additional checks in the same pass: committed run records grep-verified clean for the live key (twice, tonight); the campaign containment `case` refuses a `campaign-current` symlink resolving outside the gauntlet tree; every watch.sh render path now routes through the control-byte `sanitize` filter.

## Rollback

Single squash commit revert; no state. The scrub is additive on the persist path; reverting restores the eyeball-only scrub of the run-record contract.
