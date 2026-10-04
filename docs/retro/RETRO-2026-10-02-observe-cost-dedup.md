# Retro: session-observe cost dedup (#877)
Date: 2026-10-02
Sprint: 2026-10-02 (one session; found during recon for an ops-toolkit experiment)

Answers to the three questions are lead-drafted from the session evidence; the operator was not asked interactively because the retro ran inside `/kit:wrap`.

## Metrics
- Tasks planned: 1 (dedup usage in `cost` and `burn`), completed: 1, deferred: 0
- Commits: 3 on the branch, squash-merged as 5030a8cc
- Files changed: 5 (`session-observe`, `tests/smoke.sh`, two synthetic fixtures, `docs/verification/observe-cost-dedup.md`)
- Effect on one real 28 MB transcript: output tokens 951,560 to 352,544 (2.7x over), cache_read 298.8M to 130.0M (2.3x over), est USD 553 to 235

## What worked
- Recon for a different tool (a Go transcript replay) surfaced the bug: a parser that had to get per-actor totals exact exposed that the existing `cost` view summed one record per content block.
- An independent verifier recomputed the totals with its own script and matched the branch to the token; the negative control (dedup key forced unique) turned 3 smoke cases red.
- One shared helper fixed every usage-summing caller (`collect`, `burn_collect`, `entry_fee_session`) instead of only the named view.

## What hurt
- The ship-gate classified `lib/session/observe/` as an auth hard path because its pattern matches any `session/` directory. The diff went to the full lane and needed 12 gate overrides.
- The gate ledger rejects a reason reused across gates, so the 12 overrides each needed a distinct suffix; 11 first attempts failed with exit 65.
- `burn` dedup kept the first streamed chunk (output_tokens 8) and undercounted output; nothing in the old smoke suite covered a multi-chunk message.

## Action items
- [ ] Narrow the auth hard-path pattern so `lib/session/` (transcript sessions) does not match, with a classifier truth-table row for this path -- owner: @tieubao -- deadline: 2026-10-09
- [ ] Let `gate-ledger.sh override` accept one reason for a list of phases (e.g. `override <slug> all-lane "<reason>"`) so a false-positive lane is one audited line, not twelve -- owner: @tieubao -- deadline: 2026-10-09

## Lane telemetry
- Misfire lines present (`ledger-io-core`, `wrap-absorbed-proof`, `wrap-step0-scope`, one floor-check downgrade) belong to earlier cycles; this cycle adds one: the auth hard-path false positive above, dispositioned as action item 1 (a classifier fix + truth-table pin).

## Kit feedback
- Hard-path false positive on `session/` (action item 1).
- Override ergonomics (action item 2).
