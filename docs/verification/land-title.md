# Proof of done: wrap land titles the PR from the feature commit

2026-09-26. Spec: `docs/specs/SPEC-326-land-title.md`. Lane: full. Files: `lib/wrap/wrap.sh`,
`tests/test-wrap.sh`, `commands/wrap.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md`
(regenerated), this file.

Acceptance: with no `--title` given, `cmd_land` picks the title from the first non-merge
commit ahead of `origin/<def>`, oldest first (`--topo-order --reverse`), whose subject does
not match `^(docs|chore|test)(\([^)]*\))?!?:`, falling back to the oldest non-merge commit
ahead when every one is housekeeping. An explicit `--title` and an adopted PR are unaffected.

**Fresh critique+review verdict:** design SOLID, code correct, FIX THEN SHIP on tests only --
`--reverse`, `--no-merges` (walk and fallback separately) and `--topo-order` were each
implemented correctly but not actually isolated by any fixture. Resolved below (`## Flag
isolation`); the code itself needed no change.

## Green runs

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 1300 passed
Verdict: PASS
```

```
Command: RUN_ALL_TIMEOUT_SECS=1800 RUN_ALL_JOBS=2 bash tests/run-all.sh --changed
Exit: 0
Output: run-all: all 13 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

The default `--changed` run (4 parallel suites, 300s ceiling each) TIMED OUT on `test-meta`
and `test-wrap` under shared-core contention, exactly the runner's documented "ceiling, not an
assertion failure" case; a bounded-concurrency, generous-timeout re-run of the same 13 suites
came back clean.

## The cases (`tests/test-wrap.sh`)

| Case | Setup | Result |
|---|---|---|
| Feature commit in the middle | `docs(spec): reserve` -> `fix(x): the real change` -> `docs(x): proof`, land `title-mid` | `gh pr create` carries `--title fix(x): the real change`, never the tip's `docs(x): proof`; a second, argument-bracketed log confirms it landed as one argv entry (`<--title><fix(x): the real change>`) |
| Feature commit first | `fix(x): the real change` -> `docs(x): proof and changelog`, land `title-first` | title is `fix(x): the real change` |
| The #771 shape (proves `--reverse`) | `docs(spec): r` -> `feat(x): the change` -> `fix(x): review follow-up`, land `title-771` | title is `feat(x): the change`, the ORIGINAL oldest non-housekeeping commit, never `fix(x): review follow-up`, the later same-type commit a newest-first (or un-reversed) walk would pick |
| All-housekeeping branch, every conventional type | `docs(x): a` -> `chore(x): b` -> `test(x): c` -> `docs!: d`, land `title-hk` | title falls back to the OLDEST commit ahead (`docs(x): a`), never any of the three newer housekeeping commits |
| Non-conventional subject counts as feature | `docs(x): a` -> `wip stuff`, land `title-wip` | title is `wip stuff`, not a fallback to the docs commit |
| Explicit `--title` still wins | `docs(spec): reserve` -> `fix(x): the real change`, land `title-flag` with `--title "custom title"` | `gh pr create` carries `--title custom title`; the walk's own pick (`fix(x): the real change`) never surfaces |
| Adopted PR keeps its own title | `docs(spec): reserve` -> `fix(x): the real change`, an open PR already exists for `title-adopt`, land with no flags | reports `adopted PR #75`; `gh pr create` is never called at all |
| `--no-merges` on the WALK (proves the flag, not just the shape) | own commit `docs(x): only` (housekeeping); bare remote's `main` advanced; `git merge --no-edit origin/main` (real two-parent merge, asserted `git rev-list --merges --count origin/main..HEAD` = 1), land `title-mrg` | title falls back to `docs(x): only`; the merge subject is never picked -- the walk must SKIP the housekeeping own commit and reach the merge next for this to prove anything (a non-housekeeping own commit, the original shape, would return before ever reaching the merge) |
| `--no-merges` on the FALLBACK | branch owns NO commit when `git merge --no-ff origin/main` runs, THEN commits `docs(x): a`, land `title-mrgfb` | title is `docs(x): a`; the merge commit (ahead of the own commit) is never picked by the fallback either |
| `--topo-order` (proves it, not just documents it) | own `feat(x): the main change` at the real date; local `side-topo` branch's `feat(y): the backdated side change` under an explicit 2020 `GIT_COMMITTER_DATE`/`GIT_AUTHOR_DATE`; `git merge --no-ff side-topo`, land `title-topo` | title is `feat(x): the main change`; the chronologically-older side commit never outranks it |
| Single-commit branch (every pre-existing `land` fixture) | `build_land`'s unchanged one-commit path (`ok`, `knobkeep`, `basekeep`, `dirty`, `ondef`, `blocked`, `unionlog`, every `adopt-*` case, `shiprec`/`noship`/`shipfail`) | title unchanged, matching every pre-existing expectation |

## Negative control: revert to `git log -1` on the tip

`lib/gate/negctl.sh` mutated the title-pick call back to today's tip-only read.

```
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/title="\$(_land_feature_title "\$wt" "\$def")"/title="\$(git -C "\$wt" log -1 --format=%s 2>\/dev\/null)"/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation fails the "feature commit in the middle" case (`title-mid` would title from
`docs(x): proof`, the tip, instead of `fix(x): the real change`), confirming the oldest-first
walk is load-bearing, not a no-op given the fixtures' shape.

## Flag isolation (post-build critique: FIX THEN SHIP on tests only)

The critique found the original suite proved the walk's overall behavior but not each flag
individually: the `--reverse`-shaped fixture and the `--no-merges`-shaped fixture both had a
non-housekeeping own commit that let the walk return before the flag could matter. Four
mutations, each restricted to ONE line (`2141` the walk's `git log`, `2142` the fallback's),
applied by hand (`sed`, run, grep the FAIL lines, `git checkout HEAD -- lib/wrap/wrap.sh`,
confirm `git diff --stat` empty) before the next:

| Flag | Kill | Before | Under mutation | After restore |
|---|---|---|---|---|
| `--reverse` (walk) | `sed -i '' '2141s/--reverse //' lib/wrap/wrap.sh`, via `lib/gate/negctl.sh` | green | RED (negctl's gated run; whole-suite exit 1) | green, `Verdict: PASS` |
| `--no-merges` (walk) | `sed -i '' '2141s/--no-merges //' lib/wrap/wrap.sh` | green (1300 passed) | RED: `1296 passed, 4 FAILED` -- `title-mrg` (2) and `title-mrgfb` (2, the walk itself now catches the same front-of-range merge before ever reaching the fallback) | green (1300 passed) |
| `--no-merges` (fallback) | `sed -i '' '2142s/--no-merges //' lib/wrap/wrap.sh` | green (1300 passed) | RED: `1298 passed, 2 FAILED` -- `title-mrgfb` alone (`title-mrg`'s walk still finds nothing, its own `--no-merges` untouched) | green (1300 passed) |
| `--topo-order` (walk) | `sed -i '' '2141s/--topo-order //' lib/wrap/wrap.sh` | green (1300 passed) | RED: `1298 passed, 2 FAILED` -- `title-topo` alone (plain date-order surfaces the backdated side commit as "oldest") | green (1300 passed) |

Each mutation's failure is exactly the case built to prove that flag, nothing else, confirming
none of the four is a no-op left over from a fixture shape that happened to pass regardless.

## Test isolation note

Every new case reuses the existing `land` fixture family (`build_land`, `$GH_STUB_CALLS`,
`KIT_LEDGER_DIR`) already isolated at the top of `tests/test-wrap.sh`; no new isolation was
needed.

## Limits

Not covered (per the spec's After state): a stacked branch cut from an already-squash-merged
parent still carries the parent's pre-squash commits ahead of `origin/<def>` and the walk
picks the parent's oldest non-housekeeping subject; the operator's fix is to rebase before
landing or pass an explicit `--title`. Not covered: a `fixup!`/`squash!` subject surviving to
`land` unsquashed (treated as an ordinary, non-skipped subject). **Accepted (new):** a branch
that merges in a non-default side branch, where the branch's own commits are all housekeeping
but the side branch carries a real non-housekeeping commit, takes the foreign side commit's
subject -- `--no-merges` excludes only merge commits, not a non-merge commit inherited via one,
same family as the stacked-branch limitation. Not fixed (pre-existing, noted only):
`cmd_land`'s own `git fetch` a few lines above the title pick discards its exit code.
