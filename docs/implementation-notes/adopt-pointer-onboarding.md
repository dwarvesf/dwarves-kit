# Implementation notes: adopt pointer and two-idea tour

Only decisions, deviations, tradeoffs and open questions that differ from the spec.

| # | Note |
|---|---|
| 1 | Premise check: `lib/adopt.sh:179` hard exit, `:203-207` copy, `:197` import, `tests/test-adopt.sh:37-41` and `:86-96` all match the spec. All 28 historical `AGENTS.md` versions start with `# AGENTS.md: the operating layer`. |
| 2 | Ledger: `gate-ledger.sh record` accepts only `ran` or `skipped`. The Build start is recorded as `Build ran "start"`. |
