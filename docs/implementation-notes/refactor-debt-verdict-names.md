# Debt verdict names: wave becomes log / accept

Delta from the brief. Only the two debt meanings of `wave` change; the mega-goal wave is untouched.

## Decisions

- Verdict `wave` is now `log`. Response `wave` is now `accept`.
- The derived disposition `waved` covered both the silent verdict and the human response. I split it: a silent verdict reads `logged`, a human response reads `accepted`. Both stay collectible, as `waved` was. The `collect` header reads `Items: N (a accepted, l logged, d deferred)`.
- Writers: `significance-classify.sh` emits `log`. `gate-ledger.sh debt` and `debt-response` still accept `wave` but write `log` / `accept`. `debt-response` also folds a stored `verdict=wave` to `log` when it forward-carries.
- Readers (`weekend-batch.sh`, `dashboard.py collect_debt`) accept both words and give identical results. Stored rows are never rewritten.
- `quiz-gate.sh respond <rid> wave` works as an alias: it prints one note line saying `accept` is the new name and logs `accept`.

## Prose follow-up (same branch)

`commands/ship.md`, `commands/grill.md`, `commands/explain.md`, `docs/MANUAL.md`, `docs/WORKFLOW.md` and `lib/stats/docs/ledger-event-schema.md` now use `log` / `accept`. `commands/grill.md` writes `verdict=log`, and `tests/test-self-grill-watcher.sh` greps for it. `docs/WORKFLOW.md` says the `weekend-debt-paydown` skill is not shipped; the name stays because `tests/test-understanding-wiring.sh` checks for it. One `waved` mention remains on purpose, where WORKFLOW explains the split.

## Open

None. The lead confirmed no outside consumer reads `disposition: waved`.
