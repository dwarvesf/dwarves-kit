# Ceremony lens baseline

Produced by `cd lib/stats && uv run stats ceremony --json` (text form: `uv run stats ceremony`) over the live ledgers and transcripts on 2026-09-30. Read-only. Every cell below comes from that output. The lens rebuild took about 80 s.

## Scope

| Item | Value |
|---|---|
| Window | 2026-09-16T01:11:58Z to 2026-09-30T01:11:58Z (14 days ending at the latest GATE timestamp) |
| Ledger dir | `~/.local/state/dwarves-kit/logs/runs/` (all repos) |
| Git repo read for progress | the dwarves-kit checkout only, so lines and PRs are dwarves-kit numbers |
| Excluded rids | sg-01 (START 72, TOKENS 39), sg-02 (40, 26), sg-03 (3, 0), sg-one (101, 0), sg-two (39, 0), tier4-fixture-2 (48, 0), tier4-fixture (48, 0), turncap-fixture (77, 77) |
| Suspect fixtures (START, no GATE) | anon-skill-collision, circle, circle-phases, e2e, logline-format-fixes, skill-path-single |
| Transcript retention | earliest transcript 2026-09-02T07:30:38Z; 1179 files seen, 1172 read, 1 skipped as malformed |
| GATE rows without a timestamp | 0 |

## Gate records (a share of records, never of tokens or time)

| Measure | Value |
|---|---|
| ran | 747 |
| override | 87 |
| skipped (never in the share) | 162 |
| ran + override | 834 |
| ceremony records (ran + override) | 637 (ran 554, override 83) |
| ceremony share | 0.76 |
| catches | 49 |
| known-caught rows (OUTCOME bracket exists) | 178 |
| lines shipped (added + deleted, `(#N)` commits) | 55098 |
| PRs merged | 166 |

## Share by week

| week | ceremony | gate records | share |
|---|---|---|---|
| 2026-09-21 | 405 | 532 | 0.76 |
| 2026-09-28 | 232 | 302 | 0.77 |

## Subagent dispatches by agentType (1152 dispatches, all transcripts in the window)

| agentType | dispatches |
|---|---|
| general-purpose | 943 |
| kit:code-reviewer | 59 |
| kit:task-verifier | 40 |
| kit:security-reviewer | 18 |
| Explore | 16 |
| kit:advisor | 16 |
| kit:recheck-verifier | 16 |
| kit:fix-agent | 10 |
| kit:doc-verifier | 8 |
| claude | 6 |
| fork | 3 |
| kit:infra-reviewer | 3 |
| other kit:* types (10 types) | 12 |

## Join sources and tokens

| Measure | Value |
|---|---|
| rid_source tag | 0 (no dispatch carries `rid=` yet; the emitter change has not shipped) |
| rid_source window | 89 |
| rid_source ambiguous | 0 |
| rid_source none | 1063 |
| dispatches with no first-message timestamp | 20 |
| Attributed dispatches | 89, all in one run (`menu-bar-app`, 17 tasks, 5.2 dispatches per task) |
| Tokens, attributed dispatches only | total 955552861: input 11006, output 3572906, cache-read 892275931, cache-creation 59693018 |
| Tokens outside attributed dispatches | `?` (unattributed, never estimated) |

## Reading it

- The share sits at 0.76 in both weeks, so it is stable, not a burst.
- The window has catches (49 of 178 known), so `ceremony_share` does not fire on the live corpus. The zero-catch clause is the discriminator.
- Only 8 of 85 historical `build` rows have an OUTCOME bracket, so the window join attributes 89 of 1152 dispatches. Treat per-run dispatch and token cells as a floor.
- Cache-read is 93 percent of attributed tokens.

## Chosen threshold

`ceremony_share_max` stays at 0.70. The observed share is 0.76 and 0.77 per week, so 0.70 sits under the live range and the fire decision rests on zero catches plus the two volume floors (30 records, 10 known-caught rows).

## A/B row (criterion 8b)

PARTIAL. Post-ship of the dispatch-tag and whole-spec-dispatch changes: run one fixture spec through the old and new spine, both tagged `rid=`, then record `stats ceremony --json` here.
