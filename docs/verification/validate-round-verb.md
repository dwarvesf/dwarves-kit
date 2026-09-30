# Verification -- validate-round verb (Phase 1: verb + tests)

## Repair pass (part-A review fixes)

The review-fix commits (`8bdc915b` code, `4549774a` tests, `81db7d9f` notes) were
each proven red against a deliberately broken build before acceptance: mutate the
implementation (or fixture) by content, run the covering `VR_CASES` subset, watch
the leg go red, restore, confirm green. Mutations and their red legs:

| Mutation (all content-targeted `sed` on `lib/gate/gate-ledger.sh` unless noted) | Red legs |
|---|---|
| `_vr_check_resume` neutered to `return 0` | C10d forged legs x6 (close + incomplete: exit 1, stderr naming, ledger unchanged) |
| `  foreign: ` prefix renamed to `  line: ` | C10d "forged record named on stderr" x2 only |
| dispatcher `unset $(git rev-parse --local-env-vars)` removed | C1b gitdir x3 + gitcommon x3 |
| `_vr_porcelain` pipeline + `|| echo broken` | C11a/C11b git-status shim legs (open rc 0, close wrote records) |
| `trap 'exit 1' ERR` -> `trap 'exit 128' ERR` | all six shim legs red with rc 128 |
| ENVIRON transport reverted to `awk -v o=` | manual repro: spec path `x\ty` makes `-v` escape-process the backslash; close listed the round's own records as foreign (rc 2 either way; the listing is wrong under `-v`) |
| `CDPATH=` prefix removed from the canonicalizing `cd` | manual repro: `env CDPATH=<decoy>` + relative spec -> `cd` echoes the resolved dir, canonical charset recheck refuses 64 (fixed: 0) |
| `[ -n "$reason" ]` -> always-true on both incomplete paths | C11b empty-reason legs (rc 0 and rc 1 instead of 64) |
| spec-path charset `case` neutralized | C11a whitespace + `=` legs (rc 1 not 64; file exists now) |
| `[ "$slug" = "$nrid" ]` -> self-compare | C11a raw-slug leg (open rc 0) |
| `[ "$_vrL_token" = "$token" ]` -> self-compare | C11a forged-token close + stale-token legs (rc 0 not 1) |
| `hash-object -w` -> `hash-object` | C1/C5 pinned-blob legs x3 |
| drift `exit 2` -> `exit 0` | C5/C5b/C8b/C9 first-close-2 legs x5 |
| incomplete writer `caught=false` -> `caught=true` | C10/C10c/C10d full-block legs x4 |
| `void` added to open's refusal case | C1c second-open legs x3 |
| C12 fixture date pinned to 2020-01-01 (test-side) | C12 report non-empty leg |
| `grep -c ROUND` injected into progress/descent | C12 progress+descent+outcome-read byte-identical legs x4 |

Green after every restore (sha `ff2e7f3b` each time); the suite is 186/186.

## Green run

Additive `| ROUND |` ledger state machine in `lib/gate/gate-ledger.sh` (`validate_round`
+ `_vr_*` helpers) and `tests/test-gate-validate-round.sh` covering C1-C4, C11a
(commit `eb65e29d`) and C5-C10d, C11b, C12 (commit `0af288e0`). Out of scope here:
command-file wiring (T3). `docs/FEATURES.md` was regenerated twice under this change
because the new test file bumps five incidental `test_refs` counts; mechanical regen
only, no authored feature content.

## Green run

```
Command: bash tests/test-gate-validate-round.sh
Exit: 0   (=== results: 186/186 pass, 0 fail ===)
Verdict: all case blocks green (C1-C12, C11a+C11b)

Command: bin/test-affected
Exit: 0 for every suite except tests/test-gate-opt-out.sh (pre-existing, see Baseline)

Command: bash tests/test-gate-outcome.sh
Exit: 0

Command: bash tests/test-meta.sh
Exit: 0   (Passed: 887 / 887)
Verdict: baseline restored after the FEATURES.md regen
```

## Full suite

```
Command: bash tests/run-all.sh --all
Exit: 1
Summary: run-all: FAILED -> test-config-registry test-gate-opt-out test-kit-contract test-kit-foldin-hooks test-no-personal-paths test-no-scattered-ids
         run-all: TIMED OUT at 300s -> test-wrap (runner ceiling, not an assertion; test-wrap standalone: 1573/1573 in ~8m)
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
- `test-no-personal-paths` -- `/Users/<name>/...` strings in SPEC-333 docs and
  `docs/verification/land-adds-ci-label.md`.
- `test-no-scattered-ids` -- pre-existing hits in `hooks/harvest.sh`,
  `commands/{execute,spec}.md`, `lib/gate/proof-ledger.sh`,
  `lib/spec/spec-task-done.sh`, `lib/wrap/report-lint.sh`.

## Negative control (negctl) -- C5 blob-drift check

The mutation neuters the blob comparison in `_vr_close` (`[ "$blob_now" = "$blob_o" ]`
becomes a self-compare), so an edited spec blob never flags drift. It is targeted by
CONTENT, not line number: the `s/.../.../` pattern is the full comparison text, so
edits above it can no longer silently move the target out from under the mutation.

```
Command: bash lib/gate/negctl.sh "$PWD" 'VR_CASES="C5 C5c C7b" bash tests/test-gate-validate-round.sh' "sed -i '' 's/\[ \"\\\$blob_now\" = \"\\\$blob_o\" \]/[ \"\\\$blob_now\" = \"\\\$blob_now\" ]/' lib/gate/gate-ledger.sh"
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/\[ "\$blob_now" = "\$blob_o" \]/[ "\$blob_now" = "\$blob_now" ]/' lib/gate/gate-ledger.sh
Changed: lib/gate/gate-ledger.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/gate-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Red case names under the mutation (re-run with the mutation applied by hand, then
`git checkout HEAD -- lib/gate/gate-ledger.sh`; scoped suite went 7/14):

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

## Real primary flow (lead, isolated ledger)

The verb run against this worktree and its real spec, with `DWARVES_KIT_LOG_DIR` pointed at a temp dir so the branch's own gate records stay untouched.

```
$ validate-round open validate-round-verb docs/specs/SPEC-363-validate-round-verb.md
rc=0 token=144d6f8646e517015de15007910fd069b3ee05ac.1790750897.1
$ validate-round close validate-round-verb <token> verdict=APPROVED critical=0 warnings=2 agents=7 r6='design-bearing=yes pass'
blob=144d6f8646e517015de15007910fd069b3ee05ac
rc=0
$ validate-round close validate-round-verb <same token> (replay)
validate-round: last ROUND for 'validate-round-verb' is not an open carrying this token
rc=1
$ show validate-round-verb
2026-09-30T06:48:17Z | OUTCOME | validate | start | at=1790750897
2026-09-30T06:48:17Z | OUTCOME | design-record | start | at=1790750897
2026-09-30T06:48:17Z | ROUND | open | token=144d6f8646e517015de15007910fd069b3ee05ac.1790750897.1 top=<kit>/.claude/worktrees/validate-round-verb spec=<kit>/.claude/worktrees/validate-round-verb/docs/
2026-09-30T06:48:17Z | ROUND | closing | token=144d6f8646e517015de15007910fd069b3ee05ac.1790750897.1 kind=close verdict=APPROVED critical=0 warnings=2 agents=7 | design-bearing=yes pass | 0 critical
2026-09-30T06:48:17Z | GATE | validate | ran | APPROVED critical=0 warnings=2 fresh agents=7 parallel
2026-09-30T06:48:18Z | OUTCOME | validate | end | at=1790750897 caught=false dur_s=0
2026-09-30T06:48:18Z | GATE | design-record | ran | design-bearing=yes pass
2026-09-30T06:48:18Z | OUTCOME | design-record | end | at=1790750898 caught=false dur_s=1
2026-09-30T06:48:18Z | ROUND | close | token=144d6f8646e517015de15007910fd069b3ee05ac.1790750897.1 verdict=APPROVED
```

Negative control on the real flow: a spec edit between `open` and `close` voids the round, writes no GATE line, and the committed spec is restored.

```
open rc=0
$ printf '
' >> docs/specs/SPEC-363-validate-round-verb.md   # a spec edit mid-round
close rc=2
restored: porcelain=0
GATE validate lines: 0
2026-09-30T06:48:30Z | ROUND | open | token=144d6f8646e517015de15007910fd069b3ee05ac.1790750909.1 top=<kit>/...
2026-09-30T06:48:30Z | ROUND | void | token=144d6f8646e517015de15007910fd069b3ee05ac.1790750909.1 why=blob,porcelain
```
