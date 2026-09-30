# Ceremony lens baseline

Produced by `cd lib/stats && uv run stats ceremony --json` (text form: `uv run stats ceremony`) over the live ledgers and transcripts on 2026-09-30, re-run after the reader fixes (the live ledgers and transcripts keep growing, so numbers drift by a few rows between runs; a re-run of the command reproduces these within that drift). Read-only. Every cell below comes from that output. The lens rebuild took about 80 s.

## Scope

| Item | Value |
|---|---|
| Window | 2026-09-16T02:03:19Z to 2026-09-30T02:03:19Z (14 days ending at the latest GATE timestamp) |
| Ledger dir | `~/.local/state/dwarves-kit/logs/runs/` (all repos) |
| Git repo read for progress | the dwarves-kit checkout only, so lines and PRs are dwarves-kit numbers |
| Excluded rids | sg-01 (START 72, TOKENS 39), sg-02 (40, 26), sg-03 (3, 0), sg-one (101, 0), sg-two (39, 0), tier4-fixture-2 (48, 0), tier4-fixture (48, 0), turncap-fixture (77, 77) |
| Suspect fixtures (START, no GATE) | anon-skill-collision, circle, circle-phases, e2e, logline-format-fixes, skill-path-single |
| Transcript retention | earliest transcript 2026-09-02T07:30:38Z; 1203 files seen, 1197 read, 0 skipped (the one earlier skip was an in-flight transcript whose last line was still being written; the reader now tolerates that) |
| GATE rows without a timestamp | 0 |

## Gate records (a share of records, never of tokens or time)

| Measure | Value |
|---|---|
| ran | 752 |
| override | 87 |
| skipped (never in the share) | 162 |
| ran + override | 839 |
| ceremony records (ran + override) | 637 (ran 554, override 83) |
| ceremony share | 0.76 |
| catches | 49 |
| known-caught rows (OUTCOME bracket exists) | 179 |
| lines shipped (added + deleted, `(#N)` commits) | 55604 |
| PRs merged | 173 |

## Share by week

| week | ceremony | gate records | share |
|---|---|---|---|
| 2026-09-21 | 405 | 532 | 0.76 |
| 2026-09-28 | 232 | 307 | 0.76 |

## Subagent dispatches by agentType (1176 dispatches, all transcripts in the window)

| agentType | dispatches |
|---|---|
| general-purpose | 963 |
| kit:code-reviewer | 62 |
| kit:task-verifier | 40 |
| kit:security-reviewer | 18 |
| Explore | 16 |
| kit:advisor | 16 |
| kit:recheck-verifier | 16 |
| kit:fix-agent | 10 |
| kit:doc-verifier | 9 |
| claude | 6 |
| fork | 3 |
| kit:infra-reviewer | 3 |
| other kit:* types (10 types) | 12 |

## Join sources and tokens

| Measure | Value |
|---|---|
| rid_source tag | 0 (no dispatch carries `rid=` yet; the emitter change has not shipped) |
| rid_source window | 167 |
| rid_source ambiguous | 0 |
| rid_source none | 1009 |
| dispatches with no first-message timestamp | 20 |
| Attributed dispatches | 167 in two runs: `menu-bar-app` (89, 17 tasks, 5.2 dispatches per task) and `lanes-as-data` (78, no `tasks=` in its build reason) |
| Net tokens, attributed dispatches only (input + output + cache-creation) | 78131123 (input 15634, output 5652856, cache-creation 72462633) |
| Cache-read tokens, attributed dispatches only | 1239255352 |
| Total incl. cache-read | 1317386475 |
| Tokens outside attributed dispatches | `?` (unattributed, never estimated) |

## Reading it

- The share sits at 0.76 in both weeks, so it is stable, not a burst.
- The window has catches (49 of 179 known), so `ceremony_share` does not fire on the live corpus. The zero-catch clause is the discriminator.
- Only 8 of 85 historical `build` rows have an OUTCOME bracket, so the window join attributes 167 of 1176 dispatches. Treat per-run dispatch and token cells as a floor.
- Cache-read is 94 percent of the total incl. cache-read, which is why the headline is the net figure. Net tokens per task for `menu-bar-app`: 63276930 / 17 = 3722172.

## Chosen threshold

`ceremony_share_max` stays at 0.70. The observed share is 0.76 and 0.77 per week, so 0.70 sits under the live range and the fire decision rests on zero catches plus the two volume floors (30 records, 10 known-caught rows).

## A/B row (criterion 8b)

PARTIAL. Post-ship of the dispatch-tag and whole-spec-dispatch changes: run one fixture spec through the old and new spine, both tagged `rid=`, then record `stats ceremony --json` here.
