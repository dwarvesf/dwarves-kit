# Proof of done: rid-branch-slug (SPEC-070)

Behavioral change: lib/gate-ledger.sh gains the `rid` verb (canonical run id =
runid-normalized branch slug, converging with ship-gate's `${BRANCH#*/}` at the
ledger file) + an empty-stem guard in `ledger_file`; every gate-ledger RID call site
swept from `<spec-slug>`/`<slug>` to `<rid>`.

## Green run

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 329 / 329` , 12 SPEC-070 assertions (master/main/detached
refusals + empty stdout, prefix strip, prefixless passthrough + exit pin, normalized
multi-slash, convergence canary, empty-slug guard pin).

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 432 / 432` , agreement pin (`#*/` in both
hooks/ship-gate.sh and lib/gate-ledger.sh), widened sweep pin (catches `<slug>` rid
call sites too), entry-point wiring pins.

Command: `bash tests/test-e2e.sh`
Exit: 0
Output (tail): `Golden run green.` (20/20)

Live AC4: this run started under rid `rid-branch-slug` (branch
`feat/rid-branch-slug`) and ships through ship-gate on the SAME ledger, zero mirror
records.

## NEGATIVE CONTROL

Run live twice during build: the `rid)` case arm commented out ->
`tests/test-hooks.sh` shows 9 RED (every dispatch-dependent assertion; usage error
exit 64); arm restored -> `Passed: 329 / 329` GREEN.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh   # 329/329
bash tests/test-meta.sh    # 432/432
bash tests/test-e2e.sh     # 20/20
```

VERDICT: PASS
