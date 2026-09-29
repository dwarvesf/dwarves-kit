# Implementation notes: lanes as data (SPEC-368)

Decisions, deviations, and open questions that differ from the spec.

| # | Note |
|---|---|
| 1 | Premise check at build start: the cited lines in `gate-ledger.sh`, `kit-config.sh`, `gate-policy.sh`, `kit.toml` match the spec. |
| 2 | The ledger for rid `lanes-as-data` already held the spec-phase records; the builder appended a START line and a `build ran` line at the start, then an OUTCOME start bracket. The final `build ran` follows at the end. |
