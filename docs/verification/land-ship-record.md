# Proof of done: wrap land records the ship gate

2026-09-26. Spec: `docs/specs/SPEC-317-land-ship-record.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`, `commands/wrap.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: once `cmd_land`'s tree-verify reads `OK`, `land` derives the landed branch's rid via the existing `gate-ledger.sh rid` verb, records `Ship ran "shipping pr=#<n> via=land"` only when that rid already has a run ledger AND that ledger carries no `ship` gate line yet, skips (naming why) when a `ship` line already names this same PR or a different one, and never fails the land when the derive, the ledger read, or the record itself fails.

## Green runs

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 1196 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Verdict: PASS
```

## The cases (`tests/test-wrap.sh`)

| Case | Setup | Result |
|---|---|---|
| Existing ledger, happy path | seed `runs/shiprec.log` with a `spec ran` line, land `feat/shiprec` | `land` exits 0; reports `recorded ship gate for shiprec (pr=#61)`; the ledger gains `\| GATE \| ship \| ran \| shipping pr=#61 via=land` |
| No prior ledger | land `feat/noship` with no ledger file seeded for `noship` | `land` exits 0; reports neither `recorded ship gate` nor `ship-gate record FAILED`; no `runs/noship.log` is created |
| `record` call fails | seed `runs/shipfail.log`, `chmod 444` it, land `feat/shipfail` | `land` exits 0; reports `ship-gate record FAILED for shipfail (pr=#63): <captured stderr>; record it by hand: bash <path>/gate-ledger.sh record shipfail Ship ran "shipping pr=#63 via=land"` on stderr; the worktree is still removed and the branch still deleted |
| `via=land` tag | reread `runs/shiprec.log` after the happy-path case | the line reads `\| GATE \| ship \| ran \| shipping pr=#61 via=land`; `/kit:wrap` step 8's anchored `shipping pr=#61([^0-9]\|$)` grep still matches (next char is a space) |
| Nested branch | land `feat/a/b` with a ledger pre-seeded under the rid `gate-ledger.sh rid` gives that branch (`a-b`) | `land` exits 0; reports `recorded ship gate for a-b (pr=#64)`; the ledger for rid `a-b` (never `a` or `b`) gains the Ship line |
| `land` tree-MISMATCH | seed `runs/mismatch.log` with a `spec ran` line, force a squash commit on `origin/main` whose content diverges from the PR's own diff | `land` exits 3, reports `TREE MISMATCH`; the ledger for `mismatch` keeps only the seeded `spec ran` line, no `\| GATE \| ship \|` line is ever written |
| Same-PR idempotent skip | seed a `ship ran "shipping pr=#71 via=land"` line, land the same branch and PR number again | `land` exits 0; reports `ship gate for samepr already names pr=#71; skipping (already recorded)`; the ledger keeps exactly one `\| GATE \| ship \|` line |
| Reused-slug, different-PR skip | seed a `ship ran "shipping pr=#80 via=land"` line for rid `typo`, land a branch that rids to `typo` with a new PR number 81 | `land` exits 0; reports `ship gate for typo already names pr=#80, not pr=#81; skipping (reused slug, different run)`; the ledger still names only `pr=#80`, never `pr=#81` |

All pre-existing `land` tests (`ok`, `knobkeep`, `basekeep`, `dirty`, `ondef`, `blocked`) are unaffected, none of them seed a ledger for their rid, so each is also a live instance of the "no prior ledger" case.

## Negative control 1: the `show` prior-ledger guard

`lib/gate/negctl.sh` mutated `cmd_land`'s prior-ledger guard (`if [ -n "$land_rid" ]; then` in place of the `land_ledger="$(... show ...)"` read), so a plain ad-hoc land would start attempting a record unconditionally.

```
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak "2101s/.*/  if [ -n \"\$land_rid\" ]; then/" lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Negative control 2: the same-PR idempotent-skip guard

`lib/gate/negctl.sh` mutated the same-PR comparison (`if [ "$prior_pr" = "pr=#${n}" ]; then` down to `if false; then`), so a rid whose ledger already named this exact PR would fall through to the "reused slug" branch instead of skipping as idempotent, and a re-land of an already-shipped PR would misreport why it did nothing.

```
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak '2106s/.*/      if false; then/' lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation failed the same-PR idempotent-skip case (`ship gate for samepr already names pr=#71; skipping (already recorded)` never printed; the samePR path instead falls into the reused-slug message), confirming the same-PR guard is load-bearing rather than dead code.

## Test isolation note

`KIT_LEDGER_DIR` is exported once, suite-wide, at a `$TMPD`-scoped path (alongside the existing `KIT_CONFIG_OPERATOR` pin), so no `$WRAP` call in the file, new or pre-existing, ever touches the real machine's ledger corpus.

## Limits

Not covered: a rid whose branch name changed between the run's start and the land. Not covered: retroactively back-filling a `Ship ran` line for a branch already landed before this change shipped. Not covered: a rid whose ledger carries TWO different prior PR numbers already (pre-existing corruption); the first `ship` line found (`tail -1`, last-line-wins) is the one compared.
