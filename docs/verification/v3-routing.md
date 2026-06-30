# Proof of done , data-driven routing (token-optim-v3 SG-06)

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | Router suggests per-sub-goal model from v2 SG-09's measured data | met (`lib/route-suggest.sh` reads the 12-col SG-09 ledger) |
| 2 | Suggestion matches the measured-cheapest-at-parity choice | met (rich-data row below) |
| 3 | A cheaper-but-FAILING arm is never suggested (infinite-cost guard) | met (negative control below) |
| 4 | Abstains, not overfits, on thin data | met (thin-data row below, the real committed SG-09 state) |
| 5 | Suggester, never a silent auto-router; extends SG-05's meta-agent | met (meta-agent Mode B routing section; output is advisory) |

## Why abstention is the headline behavior

v2 SG-09's COMMITTED data is a haiku-only n=1 proof run (the full multi-model Opus matrix is gated on
Han's methodology blessing, ~30+ Opus sessions). So for every real task in the ledger, only ONE model
was measured, which means "cheapest-at-parity" is undecidable and the honest output is ABSTAIN. The
router fires a confident suggestion only when >=2 models passed the same task. This is the quality bar
("when the data is thin, it says so rather than overfitting"), not a limitation worked around.

## Confirmation run-table

`route-suggest.sh <ledger> <task>` over the SG-09 ledger schema. Effort is abstained on in all cases
(SG-09's schema has no effort column; we do not suggest what was never measured).

| Fixture | Task | Measured (PASS arms) | Suggested | Matches cheapest-at-parity? |
|---|---|---|---|---|
| rich-ledger.tsv | code-add-flag | haiku 322,602 tok; opus 901,000 tok; (sonnet 90,000 tok **FAIL**) | **model=haiku** | yes (haiku is cheapest PASS; failing sonnet excluded) |
| thin-ledger.tsv (real SG-09 proof) | mini-mega | haiku only | **ABSTAIN thin-data** | n/a (correctly abstains) |
| rich-ledger.tsv | no-such-task | none | **ABSTAIN no-passing-data** | n/a |

```
$ bash tests/test-routing.sh
=== rich data: suggest measured-cheapest-at-parity ===
  -> SUGGEST  model=haiku  effort=abstain  basis=cheapest-at-parity for 'code-add-flag': opus=901000tok, haiku=322602tok (all PASS)
=== thin data: abstain ===
  -> ABSTAIN  reason=thin-data: only 'haiku' measured at parity for 'mini-mega' ...
=== 10/10 passed, 0 failed ===   EXIT 0
```

Agreement rate on decidable data: 1/1 (suggests the measured-cheapest). Abstention on thin data: 1/1.

## Negative control

`code-add-flag` has a sonnet arm at 90,000 tokens (cheapest of all three) that FAILED. The router does
NOT suggest it: a failed run is infinite cost (SG-09's anti-cherry-pick rule), so it is excluded from
the candidate set and haiku (cheapest PASS) wins. The test asserts `model=sonnet` is absent.

## Reproduce

```bash
cd <kit-worktree>
bash tests/test-routing.sh   # 10/10
bash lib/route-suggest.sh tests/fixtures/routing/rich-ledger.tsv code-add-flag   # SUGGEST haiku
bash lib/route-suggest.sh tests/fixtures/routing/thin-ledger.tsv mini-mega       # ABSTAIN thin-data
```

The thin fixture is a verbatim copy of v2 SG-09's committed proof ledger
(`ops-toolkit/experiments/token-eval-bench/results/sample/sg09-ablation-proof.tsv`).
