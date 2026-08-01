# Verification: backlog-reconcile (SPEC-225)

Behavioral proof per `proof-gate.sh contract`'s bar for this task type
(`type=reconcile class=behavioral`): "inventory with a verdict per item + reference-fix diff; a
seeded drifted item is caught", run end to end against the real primary flow, not a proxy test,
with a negative control (revert -> RED -> restore).

Two runs: (1) the content-pattern extraction fix (design critique High-1), proven against the
full live `_meta/BACKLOG.md`; (2) the seeded-drift status-mismatch detection + apply + negative
control (design critique CRITICAL-2), proven on an isolated fixture derived from the same repo's
real `ID-045`/`SPEC-055` pair.

## Run 1: content-pattern extraction vs the rejected fixed-column read

The design critique's Data-model lens found the live `_meta/BACKLOG.md` has real column-count
drift (83 of 177 active rows at NF=6, only 74 at the canonical NF=8) that would break a
fixed-column `Target artifact` read. This run proves the fix (content-pattern match, any cell,
never a fixed index) against the full live file.

```
$ bash extract-compare.sh _meta/BACKLOG.md
MISMATCH: ID-045 -- fixed-position read 'set`, `claimed` state, `/kit:assign --next`, `/kit:start` board nudge. Found + fixed 3 drifted rows on first render.', content-pattern found 'SPEC-055'
---
total active rows scanned: 177
fixed-column (position 4) extraction hits:   18
content-pattern extraction hits:              19
rows where fixed-position would have read the WRONG cell (mismatch): 1
```

`ID-045`'s own title embeds a literal pipe (`` `lib/backlog.sh board\|next\|set` ``), which
shifts a naive fixed-column split so position 4 reads a chunk of the title instead of
`SPEC-055`. Content-pattern extraction (scan every cell, match `^SPEC-\d+$` /
`^\(tiny, no spec\)$`) reads it correctly. This is exactly the failure class the design
critique predicted, reproduced on the exact row used for Run 2 below, not a synthetic example.

## Run 2: seeded status-mismatch, detect -> apply -> negative control

Isolated minimal fixture derived from the real `ID-045` row and its real target,
`docs/specs/SPEC-055-backlog-kanban.md` (`Status: SHIPPED ([Unreleased])`).

**Clean baseline** (board `Status: executing`, correctly maps to the spec's `SHIPPED`):

```
$ bash tier1.sh mini-clean.md <repo>
---
rows scanned: 1, flags: 0
```

**Seed the drift** (board `Status` changed to `validated`, spec still says `SHIPPED`):

```
$ bash tier1.sh mini-seeded.md <repo>
FLAG ID-045: board Status 'validated' vs spec SPEC-055 Status 'SHIPPED' (maps to executing|shipped) -- MISMATCH
---
rows scanned: 1, flags: 1
```

Caught, with quoted evidence on both sides (the row's own `Status`, the spec's own `Status:`
header) -- matches the pattern's evidence-class contract.

**Apply, via the skill's ONLY sanctioned mutation** (`lib/board/backlog.sh set`, not a second ad
hoc write path):

```
$ BACKLOG_FILE=mini-apply.md bash lib/board/backlog.sh set ID-045 executing "reconciled: spec SPEC-055 is SHIPPED"
ID-045 -> executing

$ cat mini-apply.md
| ID-045 | Backlog as kanban + pull mode | PHILOSOPHY | SPEC-055 | normal | executing [reconciled: spec SPEC-055 is SHIPPED]   |

$ bash tier1.sh mini-apply.md <repo>
---
rows scanned: 1, flags: 0
```

**Negative control**: revert the fix (back to the drifted status) via the same mechanism,
confirm the drift reappears (RED), then restore.

```
$ BACKLOG_FILE=mini-apply.md bash lib/board/backlog.sh set ID-045 validated
ID-045 -> validated

$ bash tier1.sh mini-apply.md <repo>
FLAG ID-045: board Status 'validated' vs spec SPEC-055 Status 'SHIPPED' (maps to executing|shipped) -- MISMATCH
---
rows scanned: 1, flags: 1

$ BACKLOG_FILE=mini-apply.md bash lib/board/backlog.sh set ID-045 executing "reconciled: spec SPEC-055 is SHIPPED"
ID-045 -> executing

$ bash tier1.sh mini-apply.md <repo>
---
rows scanned: 1, flags: 0
```

Full loop: GREEN (clean) -> RED (seeded) -> GREEN (applied via `backlog.sh set`) -> RED
(reverted, negative control) -> GREEN (restored). The detector responds to the actual injected
state, not a hardcoded always-fire/never-fire result, and the apply path is the real
`backlog.sh set` mechanism the shipped skill uses, not a stand-in.

## Run 3: full status-vocabulary coverage (design critique CRITICAL-2's actual fix)

Run 2 alone only re-proved the one vocabulary pair (`SHIPPED`/`executing`) already known to
work; `/kit:review-team`'s test-coverage lens correctly flagged that the CRITICAL-2 finding
("mapping covers 2 of >=5 real vocabulary words") that motivated Run 2 was not actually
exercised across the vocabulary it claimed to fix. This run closes that gap: three synthetic
fixture spec files (`SPEC-900` Status `DRAFT`, `SPEC-901` Status `PARKED`, `SPEC-902` Status
`SHIPPED (v2.0.0) 2026-01-01, Owner: Han`, a real free-text-suffix shape) plus four board rows.

```
$ bash tier1.sh vocab-fixtures.md <fixture-repo>
FLAG ID-903: board Status 'queued' vs spec SPEC-901 Status 'PARKED' (maps to parked) -- MISMATCH
---
rows scanned: 4, flags: 1
```

`ID-900` (`DRAFT`/`queued`, clean), `ID-901` (`PARKED`/`parked`, clean), and `ID-902`
(`SHIPPED (v2.0.0) 2026-01-01, Owner: Han`/`executing`, clean, proving the leading-keyword
extraction correctly strips the version/date/owner suffix) all pass with zero flags. `ID-903`
(`PARKED` spec, `queued` board, a deliberate mismatch) is caught, proving detection also works
in a vocabulary direction other than `SHIPPED`, not just the one pair Run 2 exercised.
`APPROVED` is not separately fixture-tested: it shares `DRAFT`'s exact mapping bucket
(`queued|claimed|speccing`), so `DRAFT`'s pass is representative, not a gap.

## Scope note

These runs prove Tier 1's core mechanics (content-pattern extraction, status-mapping detection
across the vocabulary, apply, negative control) with hand-written scratch scripts implementing
exactly the logic `skills/backlog-reconcile/SKILL.md`'s Process section describes. They do not
exercise Tier 2 (`agents/audit-scanner.md` dispatch) live, matching `topology-drift`'s own
precedent (no committed Tier-1 script; the SKILL.md prose IS the implementation an agent
re-derives per invocation) and this repo's `TASK-007` acceptance bar (the seeded-drift catch +
negative control, not a full live Tier-2 dispatch transcript). The full-file run (Run 1)
additionally confirms zero new false-positive risk from the fix at the real repo's actual scale
(177 active rows, 19 SPEC-pointing).

**Honest gap, named per `/kit:review-team`'s test-coverage lens.** Of the spec's `## Test plan`
20-row matrix, this document exercises cases 1 (implicitly, the fixtures + scripts exist and
run), 3, 3b (via the DANGER/missing-header logic path, not separately fixture-tested), 4, and 9
(the last two conceptually via Run 1/2's shape, not a live Tier-2 dispatch). The remaining
`mechanical`-tier cases (2, 2b, 5, 6, 7, 7b, 7c, 8, 8b, 8c, 10, 11, 12, 12b, 13) are NOT run
anywhere in this diff. They are cheap (no live-model cost) and are a legitimate follow-up to
close before this skill sees heavy adoption, not silently assumed passing. The literal ship gate
for THIS spec is narrower (`## Acceptance Criteria`: "the seeded-drift dogfood run is the
primary proof; no unit-test framework is introduced", matching `topology-drift` precedent), so
this gap does not block TASK-007, but a reader should not infer full matrix coverage from this
document's presence.
