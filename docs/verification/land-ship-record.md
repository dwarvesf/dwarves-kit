# Proof of done: wrap land records the ship gate

2026-09-26. Spec: `docs/specs/SPEC-317-land-ship-record.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`, `commands/wrap.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: once `cmd_land`'s tree-verify reads `OK`, `land` derives the landed branch's rid via the existing `gate-ledger.sh rid` verb, records `Ship ran "shipping pr=#<n>"` only when that rid already has a run ledger, and never fails the land when the derive or the record itself fails.

## Green runs

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 1173 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: --changed against f9dd9976: 6 changed files -> 12 suites (7 named, the rest always-on)
        run-all: all 12 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## The three new cases (`tests/test-wrap.sh`)

| Case | Setup | Result |
|---|---|---|
| Existing ledger, happy path | seed `runs/shiprec.log` with a `spec ran` line, then land `feat/shiprec` | `land` exits 0; reports `recorded ship gate for shiprec (pr=#61)`; the ledger gains `\| GATE \| ship \| ran \| shipping pr=#61` |
| No prior ledger | land `feat/noship` with no ledger file seeded for `noship` | `land` exits 0; reports neither `recorded ship gate` nor `ship-gate record FAILED`; no `runs/noship.log` is created |
| `record` call fails | seed `runs/shipfail.log`, `chmod 444` it, then land `feat/shipfail` | `land` exits 0; reports `ship-gate record FAILED for shipfail (pr=#63); record it by hand` on stderr; the worktree is still removed and the branch still deleted |

All three ran green in the same suite as every pre-existing `land` test (`ok`, `knobkeep`, `basekeep`, `dirty`, `ondef`, `blocked`), which are unaffected by this change, none of them seed a ledger for their rid, so each is also a live instance of the "no prior ledger" case, now exercised for the first time against `gate-ledger.sh`.

## Negative control

`lib/gate/negctl.sh` mutated `cmd_land`'s prior-ledger guard (`if [ -n "$land_rid" ] && bash "$GATE_LEDGER_SH" show "$land_rid" ...; then` down to a bare `if [ -n "$land_rid" ]; then`, dropping the `show` check), so a plain ad-hoc land would start recording unconditionally.

```
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak "2093s/.*/  if [ -n \"\$land_rid\" ]; then/" lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation failed exactly the "no prior ledger writes nothing" case (`record` now succeeds and creates a ledger file for a rid that never started a run), confirming the `show` guard is load-bearing rather than dead code.

## Test isolation note

This is the first place `tests/test-wrap.sh` invokes `gate-ledger.sh`. `KIT_LEDGER_DIR` is now exported once, suite-wide, at a `$TMPD`-scoped path (alongside the existing `KIT_CONFIG_OPERATOR` pin), so no `$WRAP` call in the file, new or pre-existing, ever touches the real machine's ledger corpus.

## Limits

Not covered: a rid whose branch name changed between the run's start and the land. Not covered: retroactively back-filling a `Ship ran` line for a branch already landed before this change shipped.
