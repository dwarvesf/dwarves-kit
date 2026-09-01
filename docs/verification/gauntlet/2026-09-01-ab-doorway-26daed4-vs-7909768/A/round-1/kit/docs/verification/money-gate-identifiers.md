# Proof of Done: money-gate matches identifier-shaped money code

**Feature:** close the money gate's two safety holes (snake_case blindness; a strict knob that silently did nothing).
**Date:** 2026-07-15 · **Lane:** normal · **Host:** dev laptop (macOS 26.5) · **Spec:** `lib/money-gate/SPEC.md` divergences 3 and 4

## What was wrong

The gate is supposed to ask before a money-touching edit lands. It was matching with `\b`
anchors, and `_` is a word character, so **it never matched inside a snake_case identifier**:
`payroll_total = 5000` sailed through while `payroll = 5000` fired. Identifier-shaped money
code is exactly what an agent edits, so the gate was blind to its own main case.

Separately, `MONEY_GATE_STRICT` was compared against the literal string `"1"`. An operator who
armed it with `MONEY_GATE_STRICT=true` got log-only mode while believing they were being
prompted: a safety knob that silently does nothing is worse than no knob.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `payroll_total`, `invoice_id`, `amounts` trip the gate | divergence 3 |
| A2 | `total_payroll`, `_balance_` (leading/trailing underscore) trip it | divergence 3 |
| A3 | `mypayroll`, `payrolling`, `tokenizer`, `balanced` do NOT trip it | NEGATIVE CONTROL (no over-match) |
| A4 | `MONEY_GATE_STRICT=true` / `on` arm the gate | divergence 4 |
| A5 | `0`, `false`, `no`, `off`, empty stay log-only | NEGATIVE CONTROL (no false ask) |
| A6 | Every pre-existing assertion still passes (no regression in the gate's other behavior) | regression |

## Implementation

| Piece | What | Where |
|---|---|---|
| Boundaries | `\b` -> `(?<![A-Za-z0-9])` ... `s?(?![A-Za-z0-9])`: `_` reads as a separator, plural caught, alphanumeric neighbour still blocks | `hooks/money-gate.py` `MONEY_RE` |
| Strict knob | literal `"1"` -> any truthy spelling (`1`/`true`/`yes`/`on`, case-insensitive) | `hooks/money-gate.py` `main()` |
| Tests | `[12]` flipped from characterization-of-the-hole to assertion-it-is-shut; `[12b]`, `[12c]`, `[10]`, `[10b]` added | `tests/test-money-gate.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Full suite (A1-A6) | `bash tests/test-money-gate.sh` | `test-money-gate: all 16 passed` | PASS |
| snake_case fires (A1) | item 12 | `ask` + `payroll` reported | PASS |
| underscore forms (A2) | item 12b | `ask` | PASS |
| NEGATIVE CONTROL no over-match (A3) | item 12c | no output, empty log | PASS |
| truthy strict (A4) | item 10 | `ask` for `true` and `on` | PASS |
| NEGATIVE CONTROL falsy strict (A5) | item 10b | log-only for 0/false/no/off/empty | PASS |
| Contract | `bash tests/test-kit-contract.sh` | green | PASS |

## Run detail

```
$ bash tests/test-money-gate.sh
...
[10] MONEY_GATE_STRICT accepts any truthy spelling ('true' now ARMS the gate)
  ok: STRICT=true arms the gate
  ok: STRICT=on arms the gate
[10b] NEGATIVE CONTROL: a FALSY strict value stays log-only (no false ask)
  ok: 0/false/no/off/empty all stay log-only
[11] exit 0 ALWAYS, even when emitting an ask (decision travels in JSON, not rc)
  ok: asked and still exit 0
[12] snake_case identifiers and plurals DO trip the gate (the hole is closed)
  ok: payroll_total / invoice_id / amounts now fire
[12b] the leading-underscore and trailing-underscore forms fire too
  ok: total_payroll / _balance_ fire
[12c] NEGATIVE CONTROL: widening did NOT make the gate match inside a longer word
  ok: no false fire inside longer words

test-money-gate: all 16 passed
Exit: 0
Verdict: PASS
```

NEGATIVE CONTROL, at the source level: restore the `\b` anchors and item 12 fails
(`still blind to snake_case`), proving the assertion is not vacuous. The over-match control
(12c) fails if the boundaries are widened to plain `.`, proving the fix is not a blunt one.

## Reproduce

```bash
cd <dwarves-kit>
bash tests/test-money-gate.sh
bash tests/test-kit-contract.sh
```
