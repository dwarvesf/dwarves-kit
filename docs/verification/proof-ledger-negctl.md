# Proof of done: negctl (mechanised negative control), fail-closed

Change under proof: `lib/gate/negctl.sh` (the implementation), `lib/gate/proof-ledger.sh`
(`negctl` verb forwards; `check()` rejects `Verdict: FAIL`), `tests/test-proof-negctl.sh`,
`.github/workflows/test.yml` (both new suites wired), `docs/verification/README.md`.
Replaces the #483 record after the kit:battery over it: verifier N2 FAIL (a space-named
path was never restored), security HIGH 1-2 (staged mutations invisible, untracked leftovers
silent, restore failure swallowed), reviewer H1 (a pasted FAIL block satisfied the gate),
H2 (test not in CI), L11 + advisor H1 (fail-closed tool inside the fail-open gate).

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Real mutation: GREEN -> RED -> GREEN, PASS block, tree clean | `bash tests/test-proof-negctl.sh` case 1 | ok | PASS |
| 2 | `proof-ledger.sh negctl` forwards to the script | case 2 | ok | PASS |
| 3 | Vacuous mutation is FAIL, exit 1, tree restored | case 3 | ok | PASS |
| 4 | Dirty tracked file, unstaged AND staged, is REFUSED (exit 2) before any step | case 4 | ok | PASS |
| 5 | No-op mutation named as such (first failure wins) | case 5 | ok | PASS |
| 6 | A path with spaces is restored (verifier N2) | case 6, mutates `sub dir/lib file.sh` | ok | PASS |
| 7 | A STAGED mutation is in the restore set (security 1) | case 7 | `Changed: lib.sh`, clean after | PASS |
| 8 | An untracked leftover is FAIL with the delta named, never PASS (security 2) | case 8 | `Delta: ?? lib.sh.bak` | PASS |
| 9 | A negctl FAIL block does NOT satisfy `check()`; a PASS block does (reviewer H1) | case 9 | rc 1 then rc 0 | PASS |
| 10 | Usage names the script (non-vacuous vs the unknown-verb 64) | case 10 | ok | PASS |
| 11 | Whole suite | `bash tests/test-proof-negctl.sh` | `test-proof-negctl: all 10 passed` | PASS |
| 12 | Structural suite | `bash tests/test-meta.sh` | 824/824 | PASS |

## Negative control (negctl)

Produced by the verb against its own test, with the before/after tree snapshot comparison
disabled as the mutation (so an untracked leftover would go unnoticed):

```
Command: bash tests/test-proof-negctl.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/^if \[ "$after" != "$before" \]; then$/if false; then/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak
Changed: lib/gate/negctl.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/negctl.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
bash tests/test-proof-negctl.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-proof-negctl.sh" \
  "sed -i.bak 's/^if \[ \"\$after\" != \"\$before\" \]; then$/if false; then/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak"
```
