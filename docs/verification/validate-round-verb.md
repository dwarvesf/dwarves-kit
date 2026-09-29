# Verification -- validate-round verb (Phase 1: verb + tests)

Additive `| ROUND |` ledger state machine in `lib/gate/gate-ledger.sh` (`validate_round`
+ `_vr_*` helpers) and `tests/test-gate-validate-round.sh` covering C1-C4, C11a
(commit `eb65e29d`) and C5-C10d, C11b, C12 (commit `0af288e0`). Out of scope here:
command-file wiring (T3). `docs/FEATURES.md` was regenerated twice under this change
because the new test file bumps five incidental `test_refs` counts; mechanical regen
only, no authored feature content.

## Green run

```
Command: bash tests/test-gate-validate-round.sh
Exit: 0   (=== results: 157/157 pass, 0 fail ===)
Verdict: all case blocks green (C1-C12, C11a+C11b)

Command: bin/test-affected
Exit: 0 for every suite except tests/test-gate-opt-out.sh (pre-existing, see Baseline)

Command: bash tests/test-meta.sh
Exit: 0   (Passed: 887 / 887)
Verdict: baseline restored after the FEATURES.md regen
```

## Full suite

```
Command: bash tests/run-all.sh --all
Exit: 1
Summary: run-all: FAILED -> test-config-registry test-gate-opt-out test-kit-contract test-kit-foldin-hooks test-no-personal-paths test-no-scattered-ids
         run-all: 166 suites run, 0 skipped for missing tooling
```

All six failing suites are pre-existing on the branch baseline: each was re-run on
a detached worktree at `1c0369d5` (the commit before this change) and failed
identically. The failures sit in the harvest fold-in and SPEC-333 docs that landed
on master after the branch point; nothing in this diff touches hooks/, the config
registry, harvest files, or scattered-id lint subjects:

- `test-config-registry` -- AC10: registry doc is missing `harvest.enable` /
  `harvest.hook_when_sweep_on` root-only keys.
- `test-gate-opt-out` -- lint: `hooks/harvest.sh` + `hooks/harvest_sweep.py` read
  config files directly (also red in `bin/test-affected` at baseline).
- `test-kit-contract` -- `tests/test-harvest-sweep.sh` invokes `sd` (non-CI tool).
- `test-kit-foldin-hooks` -- 12 harvest fold-in hook rows (async/sync seams).
- `test-no-personal-paths` -- `/Users/tieubao/...` strings in SPEC-333 docs and
  `docs/verification/land-adds-ci-label.md`.
- `test-no-scattered-ids` -- pre-existing hits in `hooks/harvest.sh`,
  `commands/{execute,spec}.md`, `lib/gate/proof-ledger.sh`,
  `lib/spec/spec-task-done.sh`, `lib/wrap/report-lint.sh`.

## Negative control (negctl) -- C5 blob-drift check

The mutation neuters the blob comparison in `_vr_close` (line 1177:
`[ "$blob_now" = "$blob_o" ]` becomes a self-compare), so an edited spec blob never
flags drift.

```
Command: bash lib/gate/negctl.sh "$PWD" 'VR_CASES="C5 C5c C7b" bash tests/test-gate-validate-round.sh' "sed -i '' '1177s/\\\$blob_o/\\\$blob_now/' lib/gate/gate-ledger.sh"
Exit: 0 (green before mutation)
Mutation: sed -i '' '1177s/\$blob_o/\$blob_now/' lib/gate/gate-ledger.sh
Changed: lib/gate/gate-ledger.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/gate-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Red case names under the mutation (re-run with the mutation applied by hand, then
`git checkout HEAD -- lib/gate/gate-ledger.sh`; scoped suite went 6/13):

- `C5 close exits 2 (void)`
- `C5 last line is ROUND void`
- `C5 why=blob only (porcelain unchanged by the second edit)`
- `C5 a void writes no GATE validate line`
- `C5c rm: why holds blob`
- `C5c symlink: why holds blob`
- `C7b why holds blob and porcelain`

Not red, as designed: `C5c {rm,symlink}: close exits 2` and `C7b close exits 2`
stayed green because the porcelain pin still catches a deleted/spec-edited tree;
the blob dimension alone was disarmed. `C5 pinned blob still in the object store`
is a fixture invariant, not a drift check.

## Baseline / known unrelated failures

- `tests/test-gate-opt-out.sh` FAILS on the branch baseline and on master-context
  stash-test identically: `hook reads config: hooks/harvest.sh,
  hooks/harvest_sweep.py` -- the harvest hook pair reads config files directly, a
  lint that predates this change (no hooks/ file touched; the sha256 pin in
  `hooks/codex-hooks.json` is intact).
- `tests/test-meta.sh` baseline is 887/887 on this branch (the spec's older 879
  number predates the rebase).

## Not proven

- The command-file integration (`/kit:spec` calling `validate-round`, T3) is Phase
  2; this proof covers the verb + ledger behavior only.
- Concurrent-open races across two simultaneous leads; the state machine refuses a
  second open, but no two-writer concurrency test exists.
