# Decision Brief: the cognitive-debt score

Date: 2026-07-25 · Status: BACKFILLED. The operator asked to "read
DECISION-BRIEF-cognitive-debt-score.md and implement"; no such brief existed, so this one is
written from the sources that do: ADR-0031 (the understanding gate), the live `| DEBT |`
ledger lines gate-ledger.sh already records, and SPEC-123/SPEC-126 (significance classify +
weekend batch). Consuming surface: the observability dashboard + the `debt` CLI verb.

## The problem (from ADR-0031)

Verification gates answer "is it correct?"; nothing answers "does the human still understand
it?". Losing that understanding is cognitive debt: cheap short-term, bites later. The kit
already RECORDS the debt events, every run can carry `| DEBT |` lines with
`significance=<low|high> worthiness=<low|high> verdict=<tap|wave|not-significant>` and the
human's `response=<engage|defer|wave>`, and the weekend batch (SPEC-126) pays them down. What
is missing is the READ side: nothing aggregates those lines into a number the operator can
glance at, so debt accumulates invisibly between paydowns, which is precisely the failure
mode the ADR describes ("the humans involved may have simply lost the plot").

## The decision

A **cognitive-debt score**: one glanceable number derived only from the recorded `| DEBT |`
lines, surfaced on the dashboard (Verify group) and via an agent-callable CLI verb. It is a
pressure gauge for the weekend paydown, not a grade of the human.

### v1 formula (documented, deliberately simple)

Score starts at 100 (fully absorbed) and loses points for unabsorbed material:

```
open defers = DEBT lines with verdict=tap response=defer NEWER than the last paydown
              (a paydown = any response=engage line; engage lines mark batch paydowns)
score = 100 - 10*(high-significance open defers) - 4*(low-significance open defers)
        - min(20, days since last paydown)          floored at 0
```

Honesty constraints that shaped the formula:

- **Engage lines do not name which defers they clear** (observed in the real ledger: the
  2026-07-20 paydown line says "item (e) still open"). Mechanical item-level linkage would be
  fake precision, so v1 treats a paydown as a checkpoint: only defers after it count as open,
  and the page shows the raw open-item list so the human judges the remainder.
- **Staleness is capped** (20 pts): an idle month should press on the score, not zero it.
- The score ships with its inputs (open items, last paydown date, per-verdict counts) so the
  number is auditable at a glance, never a black box.

### Surfaces

1. **Dashboard section** (Verify · Cognitive debt): score tile with ok/warn/bad coloring
   (>=80 / 50-79 / <50), last-paydown tile, open-defer list with reasons, verdict mix.
2. **CLI verb**: `dashboard.py debt [--format json]`, the agent-first surface; the weekend
   paydown skill and any conductor can read the score without rendering a page.
3. `stats --format json` includes the same block, so one call fetches fleet + money + debt.

## North-star conformance

N6 (a run-emitted signal turned into a consumable read surface); N7 (cognitive off-load is
the entire point, the score exists so the human does not hold the ledger in their head);
meta-principles: evidence before claims (score computed only from recorded lines), plain
files (reads the same run ledgers), propose-never-dispose (it pressures the paydown, it never
auto-schedules one).

## Rejected

- A per-item debt tracker with clear/close semantics: needs write-side changes to
  gate-ledger and invents linkage the data cannot support.
- Folding the score into the ship-gate: debt is advisory by ADR-0031's own decision
  ("it never blocks a correct build from being correct").
