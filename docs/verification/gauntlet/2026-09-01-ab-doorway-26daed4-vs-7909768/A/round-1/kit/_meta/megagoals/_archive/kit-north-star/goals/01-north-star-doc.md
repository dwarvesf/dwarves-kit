# Sub-goal 01: north-star-doc

**Time budget:** 1-2 hours of loop work
**Depends on:** none
**Branch:** `docs/north-star-01-criteria` (dwarves-kit)

## Outcome

`docs/PHILOSOPHY.md` carries a new `## 6. North-star criteria (2026-06)` section, in English, in the doc's existing voice (each criterion: the principle, what exists today, the gap, what a conforming proposal looks like). The three criteria:

- **N1, Every work type earns a right-sized loop.** Coexistence is explicit: normal chat stays chat, the kit engages when a task is being executed. Coding work already has lanes; research / eval / tool-comparison / test-design / cleanup / doc work owes its own loop, sized to its weight, with the executing agent either preassigned (a named subagent/skill) or selected dynamically (persona/profile). NOT "everything goes through a full cycle": right-sized, per type.
- **N2, Work is pulled from a board, not pushed by an operator.** The kit BACKLOG (`_meta/BACKLOG.md`, ID-NNN rows) is the proto-kanban; the gap is status states + a pull mechanism, so an agent can take the next queued item without the maintainer typing "go". Operator chat-driven work keeps working; pull is an additional trigger, not a replacement.
- **N3, Quality is test-first, shaped per type, and proof-stored.** Scenario/test design happens BEFORE execution (BDD/TDD-style for features; the dialect differs per work type), the depth matches the task, and every quality-check execution is recorded as an immutable run that the proof gate can see.

Each criterion ends with "what a conforming proposal looks like" so future SPECs trace here. The section is explicitly marked DIRECTION (proposals must trace to it), not an implementation commitment.

## Quality bar

Reads like the other five principle sections wrote it: opinionated, tradeoff-aware, with "decision this would reject" energy. A stranger maintainer could reject a misfit proposal citing only this section.

## How to close the loop

```sh
cd ~/workspace/<owner>/dwarves-kit
grep -c '^## 6\. North-star criteria' docs/PHILOSOPHY.md   # == 1
grep -c 'N1\|N2\|N3' docs/PHILOSOPHY.md                     # >= 6 (each named + referenced)
bash tests/test-meta.sh                                      # all green (no pin counts sections)
bash lib/lane-classify.sh classify "add a north-star criteria section to PHILOSOPHY.md"  # expect tiny/normal; record the gate via lib/gate-ledger.sh per the chosen lane
```

**Done =** PHILOSOPHY.md §6 exists with the three named criteria each carrying principle/exists/gap/conforming-proposal, suites green, PR open + CI green.

## Scope edges

**In:** `docs/PHILOSOPHY.md` only (+ a meta-test pin for §6 if the suite pins sections).
**Out:** any implementation of N1/N2/N3.
**Not:** rewriting the existing five principles; adding a §7; restating WORKFLOW content.

## Where to look

The kit's PHILOSOPHY.md (its §1 design-principles voice is the calibration target); the 2026-06-10 conversation summary in this folder's ROADMAP destination line.

## PR body

> PHILOSOPHY §6: the three north-star criteria (right-sized type loops; pull-based kanban backlog; type-shaped test-first quality with stored proofs) captured as direction in the doc's principle voice, so the W1/W2/W3 SPECs that follow trace to a stated kim chỉ nam instead of a conversation. Direction only; no implementation. Verify: `grep '^## 6\.' docs/PHILOSOPHY.md`; `bash tests/test-meta.sh`. Roadmap: ops-toolkit `_meta/megagoals/kit-north-star/ROADMAP.md`.

## Notes

