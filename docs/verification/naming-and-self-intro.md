# Proof of done: naming-and-self-intro (SPEC-222)

## Acceptance criteria

| AC | Claim | Status |
|---|---|---|
| AC-1 | `docs/research/2026-08-01-naming-reconciliation.md` with findings table (verdict per item, all 5 dimensions, blast-radius counts on every rename proposal) | MET (run 4: 16 findings, 6 proposal groups with file/occurrence counts) |
| AC-2 | every applied fix zero-break; no feature file renamed, no code/test-referenced identifier changed | MET (runs 1-3: full affected-suite sweep green; independent reviewer re-verified) |
| AC-3 | AGENTS.md "## Self-intro" section with the `[kit:<name>] <one-line purpose>` rule + next-touch adoption note | MET (run 1) |
| AC-4 | start/assign/execute open with the concrete banner instruction (start `--brief` exempt) | MET (run 1) |
| AC-5 | test-meta pins AC-3 + AC-4; suite green | MET (run 1); discriminates (runs 5-6) |
| AC-6 | docs/MANUAL.md Conventions documents the banner in one line | MET (commit 1 diff) |

## Confirmation runs

| # | Check | Command | Result |
|---|---|---|---|
| 1 | meta integrity + the new SPEC-222 pins | `bash tests/test-meta.sh` | 746/746 PASS, exit 0 |
| 2 | hook suite (unchanged surface regression check) | `bash tests/test-hooks.sh` | 492/492 PASS |
| 3 | every suite pinning an edited file | `bash tests/test-{advisor,design-record,references-field,loop-engineering-contract,audit-scanner-contract,review-team-plants,docs-wiring,delivery-ratio}.sh` | all green (15/15, 26/26, 15/15, 32/32, 15/15, 8/8, 22/22, 8/8) |
| 4 | FEATURES freshness after description edit | `bash lib/registry/feature-registry.sh generate` + test-meta freshness pin | fresh (byte-identical; the stale state was caught RED mid-run, see negative controls) |
| 5 | negative control A: banner strip | `sd -s '[kit:start]' '[kit-start]' commands/start.md; bash tests/test-meta.sh` | 745/746, exactly `commands/start.md wires the self-intro banner (SPEC-222)` FAIL; restored -> 746/746 |
| 6 | negative control B: AGENTS.md heading strip | `sd -s '## Self-intro (...)' '## Self intro (...)' AGENTS.md; bash tests/test-meta.sh` | 745/746, exactly the AGENTS.md Self-intro pin FAIL; restored -> 746/746 |

## Run detail

The reconcile-type contract for this run is "inventory with a verdict per item + reference-fix diff; a seeded drifted item is caught". The inventory is the 16-row findings table in the research doc (every row carries quoted evidence with file:line). The reference-fix diff is commit 2 (8 files: review-team lens unification, six leg->stage prose stragglers, 8 glossary rows, FEATURES regeneration). The seeded-drift catch is exercised twice, on the OTHER half's pins (runs 5-6): each mutation flips exactly its one pin RED and nothing else, and restoration returns 746/746.

An unplanned live catch confirms the FEATURES freshness pin discriminates too: after `docs/specs/SPEC-222-*.md` landed, `test-meta` went RED on `docs/FEATURES.md is fresh` (the spec's command mentions changed the registry's Specs-refs projection) until regeneration, exactly the drift class the pin exists for.

Review: single-lens `kit:code-reviewer` (architecture + regressions) on the full branch diff, verdict FIX THEN SHIP with 1 MEDIUM (this file was promised by the spec but not yet committed, closed by this commit) + 1 LOW (assert_true idiom in the new test-meta loop, fixed to the file's `$(cmd && echo 0 || echo 1)` convention). The reviewer independently re-verified the zero-break claim, the pinned-literal survival in review-team.md, and the FEATURES byte-identity.

## Reproduce

```
bash tests/test-meta.sh                                        # 746/746
sd -s '[kit:start]' '[kit-start]' commands/start.md
bash tests/test-meta.sh                                        # expect exit 1, exactly the start.md banner pin RED
sd -s '[kit-start]' '[kit:start]' commands/start.md
bash tests/test-meta.sh                                        # 746/746 again
```
