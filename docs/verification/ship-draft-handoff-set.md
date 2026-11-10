# Verification -- ship-draft-handoff-set

`wrap ship` names an unexpected land outcome as a bug instead of reporting a refusal (ship never passes --draft, so a draft land is unreachable). `handoffs.sh` derives its closed rows from the terminal class in `lib/board/states.tsv`, keeping `done` and `resolved` as archive words.

## Green run

```
Command: bash tests/test-wrap-ship.sh
Exit: 0
Output:
  [0;32mPASS[0m ship_docs_name_verb: lib/wrap/README.md names wrap ship
  [0;32mPASS[0m ship_docs_name_verb: docs/MANUAL.md names wrap ship

test-wrap-ship: all 120 passed
Verdict: PASS
```

```
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0
Output:
  ok: a new terminal row in a copied states.tsv is honored
  ok: a missing states.tsv fails loudly

smoke: all 52 passed
Verdict: PASS
```

## Negative control

Old `wrap-ship.sh` restored: 115 pass, 5 fail. Hardcoded closed set restored in `handoffs.sh`: 51 pass, 1 fail (new terminal state not honored). Both restored with `git checkout --`.
