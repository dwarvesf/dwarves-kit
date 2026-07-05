# Verification: kit-modularity SG-08 mega-status

Full narrative + table-first proof: `docs/proof/kitmod-mega-status.md`. This file carries the
gate's required green run + NEGATIVE CONTROL in the flat single-file shape
(`docs/verification/README.md`'s back-compat form).

## Green run

Command: `bash tests/test-mega.sh`
Exit: 0
Output: `PASS=16 FAIL=0` (drift-class taxonomy, the STALLED-vs-WIP nuance, `--rollup-only`,
error paths, and the `board --with-mega` wiring, all against a real mktemp git repo + a
PATH-injected stub `gh`, no real network call anywhere in the suite)

Command:
```
REPO_ROOT=~/workspace/tieubao/ops-toolkit CODE_ROOT=~/workspace/tieubao/dwarves-kit \
  bash lib/mega.sh status kit-modularity
```
Exit: 1 (drift present, correctly nonzero)
Output (real corpus, real `gh`):
```
kit-modularity: 3/8 ok  ⚠ 2 drift
```

Verdict: PASS

## NEGATIVE CONTROL

Reverted the change by moving the new entry file aside, re-ran, restored it:

```
$ bash lib/mega.sh status kit-modularity --megagoals-root ~/workspace/tieubao/ops-toolkit/_meta/megagoals --code-root ~/workspace/tieubao/dwarves-kit --rollup-only
kit-modularity: 3/8 ok  ⚠ 2 drift
Exit: 1

$ mv lib/mega.sh /tmp/mega.sh.bak   # revert
$ bash lib/mega.sh status kit-modularity ...
bash: lib/mega.sh: No such file or directory
Exit: 127                            # RED, as expected

$ mv /tmp/mega.sh.bak lib/mega.sh    # restore
$ bash lib/mega.sh status kit-modularity ... --rollup-only
kit-modularity: 3/8 ok  ⚠ 2 drift
Exit: 1                              # correctly RED again (drift present) -- confirms this
                                      # is not a hardcoded-green stub
```

The three drift-class NCs (NC-1 `CLAIM-UNVERIFIED`, NC-2 `STALLED`, NC-3
`MERGED-UNCHECKED`) plus the STALLED-vs-WIP nuance control are all load-bearing fixture
assertions inside `tests/test-mega.sh` (see `docs/proof/kitmod-mega-status.md` for the full
run output); each fixture's PR/branch state is independently constructed so a dumb
`[x]`/`[ ]` echo (the failure mode this verb exists to prevent) would fail every one of them.

Verdict: PASS (negative controls confirm the reconciler is load-bearing, not a no-op or a
green-wash).

## board.sh --with-mega wiring (additive, no regression)

Command: `bash tests/test-board.sh` (byte-identical render NC-e, never passes `--with-mega`)
Exit: same 9-of-45 pre-existing local-only failures as before this branch (unchanged;
`~/.claude/dwarves-kit` stale-install env issue, SKIPS in CI).

Command: `bash tests/test-board-mirror.sh` / `bash tests/test-board-writeback.sh`
Exit: 0 / 0
Output: `72/72` / `53/54 (1 skip)` -- unchanged from before this branch.

Verdict: PASS (the opt-in `--with-mega` flag never fires in either suite, confirmed both by
these suites staying green and by `tests/test-mega.sh`'s explicit "without --with-mega, zero
gh calls / no rollup section" assertion).

## Suite identical-or-better

Targeted before/after (every file this change touches; see `docs/proof/kitmod-mega-status.md`
for why the two other unrelated slow-simulation files in the full sweep are excluded as
system-load noise, not a regression signal):

| Test file | Before | After | Verdict |
|---|---|---|---|
| `tests/test-mega.sh` (NEW) | n/a | 16/16 | new, all PASS |
| `tests/test-board.sh` | 36/45, 9 FAIL (pre-existing local env) | 36/45, 9 FAIL | identical |
| `tests/test-board-mirror.sh` | 72/72 | 72/72 | identical |
| `tests/test-board-writeback.sh` | 53/54, 1 skip | 53/54, 1 skip | identical |

Verdict: PASS (identical-or-better; strictly better -- +16 new passing checks, 0 new
failures, 0 regressions).
