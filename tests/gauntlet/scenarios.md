# Gauntlet scenario matrix (persona A: kit user)

The durable artifact of SPEC-227: one row per journey feature, cards materialize
from rows at run time and get frozen into the run record. Doorway rows (J1/J2)
are the shipped seed card; J3+ are the full-flow rows. Run order = row order
(doorway first; never pay for a full-lane probe while a doorway finding is open).

| Row | Feature | Scenario | Category | Status |
|---|---|---|---|---|
| J1 | install + adopt | doorway card: install kit from tarball, adopt fixture | happy | card shipped (`seed-card-user.md`) |
| J2 | tiny lane | doorway card's README-flag fix through the loop | happy | card shipped (same card) |
| J3 | full lane | "add a `--repeat N` flag with tests" end to end: brief -> spec -> validate -> execute -> review -> ship | happy | card: `seed-card-user-J3.md` |
| J4 | bug lane | planted regression; recorded root cause BEFORE the fix | failure-injection | matrix only (P3/P4) |
| J5 | gate collision | behavioral change vs the ship gate: proof with negative control, or documented override | failure-injection | matrix only |
| J6 | mid-flight drift | ask changes after the spec hardens; amend add-only, no silent widening | boundary | matrix only |
| J7 | resume | session killed mid-execute; cold session resumes from disk, redoes nothing | recovery | matrix only |
| J8 | review response | planted edge-case hole; fix-then-ship, no verdict shopping | failure-injection | matrix only |

Generation contract: rows J4-J8 materialize via `make-card.sh` (SPEC-227 P3)
after the SPEC-203 loop pass (P2) reconciles this hand-cut matrix. Do not
hand-author more cards ahead of that pass; the loop finding rows a human missed
is the point of running it.
