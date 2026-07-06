## 2026-07-03 18:00 Debt-ledger response-writer schema mismatch (TIER-4 close finding)

Context: understanding-gate's TIER-4 close (3 independent review lenses: architecture, security,
advisor) converged on and reproduced live a cross-sub-goal integration bug. SG-02's classifier
(`gate-ledger.sh debt`, SPEC-123) writes a FAT `| DEBT |` line (`significance=`/`worthiness=`/
`verdict=`). SG-04's human-response verb (`gate-ledger.sh debt-response`, used by `quiz-gate.sh
respond`) wrote a THIN line (`response=` only). The ledger is last-line-wins for readers, so
`weekend-batch.sh mark-paid` (SG-05) read sig/wor/verdict off the last line and re-emitted them
through the fat `debt` verb, which validates those fields as required enums -- empty values crashed
it with exit 64. Because the fat writer (`significance-classify record`) is unwired today, EVERY
live `debt-response` is thin, making this the default path on any human-responded item, not an edge
case. `tests/test-weekend-batch.sh` previously only ever hand-seeded fat lines directly into the
fixture ledger (bypassing `respond`/`debt-response` entirely), which is why the suite never caught
this.

Decision: implement the fix exactly as prescribed by the assigning prompt (root cause + design were
already established by the TIER-4 close, not re-derived here):

1. `gate-ledger.sh debt_response()` now forward-carries: it looks back at the ledger for THIS rid's
   last FAT debt line (one containing `verdict=`) and, if found, re-emits its significance/worthiness/
   verdict alongside the new `response=`. If no fat line exists (today's live default), it writes the
   thin line as before -- it never fabricates sig/wor.
2. `weekend-batch.sh cmd_mark_paid` no longer calls the fat `debt` verb at all. It closes via
   `debt-response <rid> engage "<reason>"`, which only requires a valid response enum and is safe
   whether or not a fat line exists upstream (forward-carries when one does).
3. `weekend-batch.sh cmd_list` / `cmd_collect` walk back to the last FAT debt line for display when
   the last line lacks significance=/worthiness= (a new `_last_fat_debt_line` helper), so the digest
   shows real numbers instead of blanks whenever a classifier line exists anywhere in the rid's
   history. Blank stays blank when none exists -- an honest, documented gap until
   `significance-classify record` is wired (a separate, out-of-scope decision).
4. Security LOW (folded in per the assigning prompt): a free-text `reason=` value containing a
   token shaped like a control field (e.g. `response=engage`) could be misread by a naive
   whole-line KV-parse. Two layers: (a) writer -- `gate-ledger.sh debt()` and `debt_response()` now
   replace any `=` inside a `reason` value with `:` before writing, so a reason can never contain a
   real `KEY=value` token; (b) reader, belt-and-suspenders -- `weekend-batch.sh _kv()` now cuts the
   line at the first ` reason=` (`struct="${line%% reason=*}"`) and parses control keys only from
   that prefix, since the writer's field order always puts control keys before `reason=`. `_disposition()`
   inherits this fix automatically (it calls `_kv`).
5. Cosmetic: `.github/workflows/test.yml`'s `test-significance-classify.sh` step comment mislabeled
   `SPEC-122`; corrected to `SPEC-123` (the actual spec `tests/test-significance-classify.sh` and
   `lib/classify/significance-classify.sh` cite in their own headers).

Alternatives considered (all rejected per the assigning prompt's single-root recommendation):
wiring `significance-classify record` to make every debt line fat from the start (explicitly out of
scope, a separate Han decision); having `mark-paid` special-case empty enums inside the fat `debt`
verb itself (would still leave `debt()`'s required-enum validation doing double duty as both a
classifier-input guard and a paydown-closer guard -- two callers, one validation, easy to
re-break); rejecting (rather than stripping) a `reason=` containing `=` (would break the legitimate
`quiz-gate.sh respond`'s existing `"SG-04 quiz-gate nudge ref=$ref"` reason text, a real feature,
not an attack).

Impact: `weekend-batch.sh mark-paid` on any human-responded (`defer`/`wave`/`engage`) item now
closes cleanly regardless of whether a classifier ever ran for that rid. New regression coverage in
`tests/test-weekend-batch.sh`: a true end-to-end `debt-response` (thin) -> `collect` -> `mark-paid`
case (the exact bug), a forward-carry case (fat line before a response line), and two reason-
injection security cases (writer-side neutering + reader-side struct-prefix cut, independently).
