# Proof of done: security hardening (SPEC-134, kit-run-integrity TIER-4)

Three PoC-confirmed findings remediated: HIGH path-traversal / arbitrary-file-write in
`lib/proof-table-gen.py` (rid sanitized to `runid()` charset + final out-path realpath-confined
under `docs/runs/`, enforced even for an explicit out-path), MEDIUM `mutation()` comment/code
mismatch in `lib/gate-ledger.sh` (`=` now neutered so a value cannot smuggle a second KV), LOW
symlink-follow in `lib/mutation-smoke.sh` (a symlinked candidate is skipped, not written through).

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Test | Result |
|---|---|---|---|
| 1 | traversal rid (`../../victim`) default out-path -> CONFINED under docs/runs, no escape | H1 | PASS |
| 2 | absolute rid (`/leakzone/abs-pwned`) -> no arbitrary absolute write | H2 | PASS |
| 3 | explicit out-path outside docs/runs -> REJECTED (non-zero exit + stderr, no write) | H3 | PASS |
| 4 | a normal rid still writes `docs/runs/<rid>.md` (no over-block) | H4 | PASS |
| 5 | canonical `proof-of-done.md` basename still refused | H5 | PASS |
| 5b | an out-location symlink pointing OUTSIDE docs/runs is not written through (TOCTOU hardening) | H6 | PASS |
| 6 | HIGH **negative controls** (per-guard, defense-in-depth): confinement-off -> explicit path leaks; sanitization-off+confinement-off -> rid leaks; confinement-off alone -> sanitization still confines the rid | NEG-1, NEG-2, NEG-3 | PASS |
| 7 | `=` in a `file=`/`reason=` value adds no second KV to the `\| MUTATION \|` line | M1 | PASS |
| 8 | MEDIUM **negative control**: reverted `mutation()` leaks the `=` as extra KVs | M-NEG | PASS |
| 9 | mutation-smoke skips a symlinked candidate; guard wired into the real loop | L1, L2 | PASS |

## Confirmation run-table

| Run | Command | Exit | Verdict |
|---|---|---|---|
| green | `bash tests/test-security-hardening.sh` | 0 | PASS (22/22) |
| HIGH neg-control | per-guard reverts of the CURRENT file (NEG-1/2/3) | n/a | RED-as-expected where a guard is removed (leaks) |
| HIGH neg-control (CI-cond) | fixed test in a ref-less `--depth 1 --single-branch` clone | 0 | PASS (22/22) -- no `origin/master` dependency |
| MEDIUM neg-control | reverted `mutation()` line + `=`-bearing value | n/a | RED-as-expected (4 KV tokens, `=` leaked) |
| no-regression | `bash tests/test-proof-table-gen.sh` | 0 | PASS (25/25) |
| no-regression | `bash tests/test-mutation-smoke.sh` | 0 | PASS (33/33) |
| no-regression | `bash tests/test-meta.sh` | 0 | PASS (671 assertions) |
| cross-platform | `/bin/bash tests/test-security-hardening.sh` (bash 3.2.57) | 0 | PASS (22/22) |

## Run detail

### HIGH , confined both ways (real PoC output)

FIXED (traversal + absolute rid confined; explicit out-of-tree rejected):
```
$ bash lib/proof-table-gen.sh "../../victim-escapee"
wrote .../dwarves-kit-kri-sec/docs/runs/..-..-victim-escapee.md   # confined, no escape
$ bash lib/proof-table-gen.sh "$LEAKZONE/abs-pwned"
wrote .../dwarves-kit-kri-sec/docs/runs/-...-leakzone-abs-pwned.md ; no file at $LEAKZONE/abs-pwned.md
$ bash lib/proof-table-gen.sh somerid "$LEAKZONE/explicit.md" ; echo $?
proof-table-gen: refusing to write '.../leakzone/explicit.md': resolves to '...', outside the
  allowed run-table tree '.../docs/runs' (this generator only writes under docs/runs/)
1
```

NEGATIVE CONTROLS , the two guards are defense-in-depth, so the negctl **builds a reverted
generator by transforming the CURRENT file** (a `str.replace` on a stable anchor, asserting the
anchor was found so a drift fails loudly), NOT by fetching `origin/master` , CI's shallow
`actions/checkout` (fetch-depth 1) has no `master` ref, and the old `git show origin/master:...`
negctl silently produced an empty file that wrote nothing (the exact RED that this fix addresses;
reproduced deterministically in a `--depth 1 --single-branch` clone). Each guard is proven
load-bearing on the vector it uniquely owns:
```
# NEG-1  confinement is the SOLE guard on an explicit out-of-tree path (sanitization never sees it)
$ python3 <confinement-disabled> somerid "$LEAKZONE/neg1-explicit"
   -> writes $LEAKZONE/neg1-explicit(.md)   <-- LEAK (confinement load-bearing here)
# NEG-2  same reverted generator, but an ABSOLUTE rid via the DEFAULT out-path stays confined:
$ python3 <confinement-disabled> "$LEAKZONE/neg2-absrid"
   -> writes docs/runs/-...-neg2-absrid.md  ; no file at $LEAKZONE/neg2-absrid.md  (sanitization load-bearing here)
# NEG-3  remove BOTH guards -> the rid escape returns:
$ python3 <sanitization+confinement disabled> "$LEAKZONE/neg3-absrid"
   -> writes $LEAKZONE/neg3-absrid.md        <-- LEAK outside docs/runs
```
The real (fixed) generator confines/rejects every case above (H1-H3), and the fixed test passes
22/22 in a ref-less shallow clone (no `origin/master`), i.e. under CI conditions.

### MEDIUM , `=` neutered both ways (real ledger line)

FIXED , a `reason` value carrying `=` is rewritten to `:`, so the emitted line has exactly the
two intended KVs (`verdict=`, `reason=`):
```
$ bash lib/gate-ledger.sh mutation med-rid verdict=flag 'reason=smuggled=second=kv'
<TS> | MUTATION | verdict=flag reason=smuggled:second:kv          # 2 KEY= tokens
```
NEGATIVE CONTROL , reverting the `| tr '=' ':'` step (throwaway copy of gate-ledger.sh, sourced
from the real lib so deps resolve) leaks the `=` as extra KVs:
```
$ bash <reverted gate-ledger.sh> mutation negmed-rid verdict=flag 'reason=smuggled=second=kv'
<TS> | MUTATION | verdict=flag reason=smuggled=second=kv          # 4 KEY= tokens (smuggled=, second= now parse as KVs)
```

### LOW , symlink skip

`[ -f "$file" ]` follows a symlink-to-regular (true), so only the added `[ -L "$file" ] && continue`
guard prevents a write-through. L1 asserts the loop's decision (`regular AND not symlink`) skips a
symlink but still processes a real file; L2 greps the real source to confirm the guard is wired into
the candidate loop immediately after the `-f` check (not dead code).

## Security review (fresh-context)

A fresh-context `kit:security-reviewer` audited the diff. Verdict: no CRITICAL/HIGH; the three
PoC findings + the requested edges (prefix-collision sibling, `..`-after-normalization, empty
rid, explicit-out-path) all confirmed closed. It surfaced one new MEDIUM **in the new code** , a
TOCTOU where the confinement checked `realpath(out_path)` but the write used the unresolved
`out_path`, so a concurrent local process could swap a final-component symlink in the gap. Fixed:
the write now targets the ALREADY-RESOLVED path and opens with `O_NOFOLLOW` (proof-table-gen.py),
covered deterministically by H6. LOW (locale caveat on the charset-equivalence claim) and NIT
(vestigial `_kit_root` param) addressed by softening the docstring + a comment.

## Reproduce

```
cd <repo>                                        # branch fix/kri-security-hardening
bash tests/test-security-hardening.sh            # 22/22 green (HIGH+MEDIUM+LOW, per-guard neg-controls, TOCTOU)
/bin/bash tests/test-security-hardening.sh       # cross-platform, macOS bash 3.2.57
bash tests/test-proof-table-gen.sh               # 25/25, no regression
bash tests/test-mutation-smoke.sh                # 33/33, no regression
bash tests/test-meta.sh                          # 671, no regression
```
