# Debt verdict names: wave becomes log / accept

Delta from the brief. Only the two debt meanings of `wave` change; the mega-goal wave is untouched.

## Decisions

- Verdict `wave` is now `log`. Response `wave` is now `accept`.
- The derived disposition `waved` covered both the silent verdict and the human response. I split it: a silent verdict reads `logged`, a human response reads `accepted`. Both stay collectible, as `waved` was. The `collect` header reads `Items: N (a accepted, l logged, d deferred)`.
- Writers: `significance-classify.sh` emits `log`. `gate-ledger.sh debt` and `debt-response` still accept `wave` but write `log` / `accept`. `debt-response` also folds a stored `verdict=wave` to `log` when it forward-carries.
- Readers (`weekend-batch.sh`, `dashboard.py collect_debt`) accept both words and give identical results. Stored rows are never rewritten.
- `quiz-gate.sh respond <rid> wave` works as an alias: it prints one note line saying `accept` is the new name and logs `accept`.

## Left alone (outside the slice)

Prose or probes that still say `wave` for the debt meaning: `commands/ship.md`, `commands/grill.md` (a literal `verdict=wave` command, and `tests/test-self-grill-watcher.sh` greps for it), `commands/explain.md`, `docs/MANUAL.md`, `docs/WORKFLOW.md`, `lib/stats/docs/ledger-event-schema.md`. All still valid input. A follow-up can reword them together with the grill probe.

## Open

An outside consumer may read the string `disposition: waved` from `collect` (the `weekend-debt-paydown` skill is named in `lib/reflect`, but I found no copy to check). The lead should confirm before landing.
