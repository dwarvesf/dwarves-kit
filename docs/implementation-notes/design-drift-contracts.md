# Implementation notes: design-drift-contracts

Delta from the audit only.

## Decisions the audit did not settle
- kit-contract: the lint has C10 (EXEC) as well as C8 and C9. The brief named two; the counts are fixed to ten and C10 is documented, because a "nine rules" page would be wrong the same way.
- kit-contract: the "five of the seven absence rules" count could not be checked, so it now says "several". The negative-control claim now reads "every rule (C1 to C10)", which the lint's NC section confirms.
- consumer-contract: the bin table is not generated from `bin/*` headers (row 15). It stays hand-kept, with a line saying `ls bin` is the full set. A generator is a code change, out of a docs slice.
- PHILOSOPHY: the wave qualifier is also applied at the "A cross-task DAG / scheduler / runtime" out-of-scope bullet, which said "a topological / wave scheduler" stays out. Same contradiction as :102.
- PHILOSOPHY: "memorize 11 commands" became "memorize the command list" (row 26 named it; no count to maintain).
- Version strategy moved to ADR-0040, copied as written, with a note that v1.x is historical and v2/v3 lines are direction only.
- workflow-map fold: the unique content was the spine, the day loop and the wrap config paragraph. The cycle, V-model, type loops, lane tree, engines, side-flows, alternate flows and hard stops already existed in WORKFLOW.md and were not copied. Dropped from the day loop: the unverifiable "13-15 minutes" and the "five always-on lints" list (six suites carry `# always:`). The spine's retro path was corrected to `RETRO-<date>-<slug>.md`.
- workflow-map.md stays as a stub, because `skills/loop-engineering/SKILL.md:183` still names it and `docs/workflow-paths.md` cited it (now repointed).
- tiers.md: dropped rows keep their row and say `dropped`, so the product map still shows what was planned. Statuses come from `_meta/BACKLOG.md`.
- lib/README.md: the file-list table became a purpose table, one line per `lib/` directory plus the root scripts. `lib/learn/` is untracked cruft on the main checkout and is not listed.

## Skipped or not reproduced
- Row 27 (Python in hooks): left as is, operator call.
- Row 19 (workset) and other UNSURE rows: not in this slice.
- WORKFLOW.md "Opt-in side-flows (11)" is still the original eleven. A pointer to `docs/FEATURES.md` was added; extending the table needs per-command facts and is a separate edit.

## Open questions
- Should `docs/research/2026-08-25-fleet-design/SCHEMA.md` keep "Status: canonical"? The README header now says the design was dropped; the schema text was left as written.
