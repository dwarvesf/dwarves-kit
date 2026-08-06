# Proof of done , `mega report` (the RUN_REPORT telemetry generator)

## Why (the fold-in gap)

`/kit:mega` and the mega-goal skill both required a telemetry close ("gate matrix +
callable stack, read from the rid ledger"), but no code could render it , the
presentation lived as conductor habit from the pre-fold era and died in the migration
(harness-loop's matrix was rebuilt with throwaway python by hand, Han flagged it
2026-07-12). `mega report <slug>` makes the close mechanical.

## Confirmation run-table

| Check | Command | Exit: | Result |
|---|---|---|---|
| Hermetic suite (15 checks) | `bash tests/test-mega-report.sh` | Exit: 0 | PASS 15/15 |
| Live dogfood on the real mega | `bin/mega report harness-loop` | Exit: 0 | PASS , matrix matches the hand-built RUN_REPORT for every rid-backed row |
| Existing verbs unregressed | `bash tests/test-mega.sh` + `bash tests/test-mega-review.sh` | Exit: 0 | PASS both |

## NEGATIVE CONTROL

1. **Rid-less sub-goal renders honest dashes, never a guess**: fixture sub-goal 02 has no
   ledger; its row carries zero `●` cells and the literal `(no rid ledger matched)` flag.
2. **A body SPEC cross-ref is NOT attributed**: the fixture goal file carries `SPEC-123`
   on its `**Proof:**` line and `SPEC-999` in the body; the row shows 123, and a grep for
   999 in the row fails (this is the exact misattribution the live ROADMAP produced:
   SG-05 briefly showed SPEC-188 from "the SPEC-188 lint amended").
3. **Unknown ledger gate cannot silently vanish**: the planted `mystery-gate` row lands in
   an explicit `extra ledger gates` note, not in any column.
4. **Read-only over sources**: the fixture ledger's shasum is byte-identical after two
   generator runs (one with `--out`).

## Reproduce

```bash
bash tests/test-mega-report.sh
bin/mega report harness-loop   # live render against the real ledgers
```

Verdict: PASS
