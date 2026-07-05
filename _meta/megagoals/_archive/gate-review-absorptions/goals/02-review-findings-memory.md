# Sub-goal 02: review-findings-memory (rejected-findings ledger + findings=/rejected= emit)

**Merge policy:** auto
**Time budget:** 2-2.5 hours of loop work
**Proof:** full reviewable proof: fixture captures (a seeded previously-rejected finding is surfaced as "previously rejected <date>: <reason>" and NOT re-raised as new; a NOVEL finding on the same file still fires = the load-bearing NC); a real review run's gate-ledger line carrying `findings=N rejected=M` proven parseable by the merged kit_gates reader; coverage-delta row.
**Design:** bearing
**Depends on:** 01 (stacked; same files).
Model: sonnet
**Branch:** `feat/review-findings-memory`
**PR base:** `feat/stale-adr-inversion`
**Over-test: yes** (this adds a memory that can SUPPRESS review findings; a bug here silently mutes real defects on every future review)

## Outcome

ID-263 kit half, the shadcn/improve "considered and rejected" ledger generalized to kit reviews:

(a) **Per-repo ledger file** `docs/verification/rejected-findings.md`: append-only table `| date | lens | finding-key | verdict | reason |` (finding-key = short slug + file path; content stays here, only counts leave).
(b) **Pre-flag check** in `commands/review.md` + `commands/review-team.md` (and advisor.md if it reports findings): before reporting, grep the ledger; a match is surfaced as "previously rejected <date>: <reason>" in a separate short section, NEVER silently dropped and NEVER re-raised as a fresh finding. Judgment stays with the human: a previously-rejected finding whose evidence has materially CHANGED is re-raised with the delta named.
(c) **Append path**: when the operator rejects a finding at review close, the reviewer appends the row (the command instructs it; no new lib unless a helper is genuinely needed, prefer prose + grep).
(d) **Emit**: the review gate-ledger record line gains `findings=N rejected=M actor=<git user.name>` KVs (actor per DECISIONS: green-field emit grammars carry identity from birth). Grammar MUST parse with the kit_gates reader merged in harness-observatory PR #683 (its DECISIONS.md names the tolerance); cross-check before shipping.

## Quality bar

No gate-requirement change: reviews run exactly as before; the ledger only adds memory + counts. Fail-open: a missing/unparseable ledger file means "no memory", never an error that blocks review. The NC is absolute: suppression applies ONLY on a finding-key match; novel findings on the same file/line must still fire.

## How to close the loop

- Fixture: seed a rejected-findings file, dispatch a review over a diff re-containing the rejected pattern PLUS a novel defect; capture: rejected one surfaced-as-previously-rejected, novel one flagged fresh.
- NC proven load-bearing: break the check deliberately (make it match on file alone), watch the novel finding get wrongly suppressed, restore, re-run green.
- Live: one real review run's ledger line with `findings=/rejected=`; parse it with the kit_gates reader (run the actual query).
- Over-test: empty ledger, malformed row, finding-key collision across lenses; coverage-delta row.
- Kit-adopted: run the lane, record gates before push.

**Done =** fixture + NC-break captures committed, live emit line parsed by kit_gates, coverage-delta row in the proof.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: kit stack done; 04 (ops stack) is now unblocked on the grammar, record the exact KV grammar + ledger-file format for it. 3. `DECISIONS.md`: finding-key format + KV grammar verbatim, and pin ONE shared finding-key grammar with 03's decision JSON keying (advisor P6: two denial vocabularies reconciled while both are green-field; 03's PR body references this entry). 4. EXIT.

## Scope edges

**In:** `commands/review.md`, `commands/review-team.md`, `agents/advisor.md` (pre-flag check only), the ledger-file format doc line in `docs/verification/README.md` guidance if the kit carries one, tests/fixtures.
**Out:** the observatory adapter + query (04); ops-toolkit's own rejected-findings file (created organically by first use, not pre-seeded).
**Not:** auto-rejection (the HUMAN rejects; the ledger only remembers); severity scoring; any change to which findings reviewers look for; a new lib file unless prose+grep genuinely cannot do it.

## Where to look

`research/2026-07-04-pxpipe-plannotator-improve-absorption.md` §3 (A3); harness-observatory `DECISIONS.md` (kit_gates grammar tolerance); shadcn/improve's vet-pass taxonomy (by-design / mis-attribution / duplicates) for the reason vocabulary.

## PR body

Review findings memory: per-repo rejected-findings ledger, pre-flag check (surfaced-not-suppressed), operator-rejection append path, `findings=N rejected=M` gate-ledger KVs parseable by kit_gates. Load-bearing NC: novel findings still fire; fail-open on missing ledger. Stacked on stale-adr-inversion. Covers ID-263 (kit half).

## Notes
