# Follow-up: delivery audit + fixes (2026-07-05)

A post-ship follow-up to the kit-modularity mega, kept co-located with its records.

## Trigger

Han inspected the shipped kit and found SG-06 ("rewrite the README + PHILOSOPHY + F-bar
audit") was in reality a **+29-line append, 0 deletions** to an already-accurate README,
with ~83% of the PR being self-grading proof-of-done. The conductor had transcribed the
worker's "rewrite / 35-row audit" claims into "done" without counting diff lines. This
raised the question: are the OTHER mega-goal sub-goals also claim > delivery?

## The audit

Fanned out 6 read-only auditors over **~258 sub-goals across 41 mega-goals**, then a
rigorous re-verify pass, comparing each sub-goal's CLAIM against the real
`git diff <merge>^..<merge>` (never the sub-goal's own proof doc).

**Result: ~78% SOLID.** The tool-building megas (cc-elevation, kit-foldin, kit-face,
run-integrity, token-optim, vibe-dex-saas, safari core, icy, recon) are genuine, with real
code and real deletions. The rot is a **claims/framing problem, not broken delivery**: thin
docs/reconcile/audit sub-goals oversold as "rewrite/audit/gate", concentrated exactly where
there is no external "does it run" signal to resist ceremony.

**Every "confirmed bug" collapsed under deeper verification** (the same lesson, recursively):
- kit-hardening #107 (deployable-done): "no gate wired" -> FINE. `test-deployable-done.sh`
  is 17/17, enforcement rides `check()`'s stateful path; `deployable()` is a used label.
- gate-review-absorptions #697 (ops-contracts): "no check" -> FINE. The goal file DEFINES
  "check" as `grep the landed line`; the 3 prose contracts landed.
- The audit itself over-flagged 4 false positives from measurement traps (cross-repo
  PR-number collisions #194-197; stacked-PR base double-counting).

**One genuine integrity finding, out of scope (not the kit):** screenpipe-client +
screenpipe-menubar mark all sub-goals `[x]` on branches whose PRs (#1-14) never merged.

## Fixes shipped (all merged)

| Fix | PR |
|---|---|
| Lessons captured (repo memory `megagoal-proof-ceremony-rot`) | ops-toolkit #724 |
| (a) `delivery-ratio` advisory (proportionality nudge, ship-gate advisory, never blocks) + ADR-0033 | dwarves-kit #199 |
| (b) mega-scaffolder docs-tier routing: light docs -> sonnet, docs REWRITE -> opus + `/kit:pitch` discipline | dwarves-kit #200 + dotfiles #208 (deployed via scoped chezmoi apply) |
| The one genuinely-undelivered kit deliverable: README doubled-intro merged into one cohesive opening (+3/-6, real deletions) | dwarves-kit #201 |

## The durable lesson

Mechanical gates (proof-exists, even proof-ratio) cannot judge delivery-vs-claim, only
judgment can. **Validate by running and diffing, never by the proof doc's own claims.** It
bit the conductor live twice while building fix (a): a proof-of-done output written but not
run (claimed "6/2", real "7/1"), and a `cp -i` alias silently leaving a file broken
mid-test. Both caught, both are why the discipline is now in memory rather than just stated.
