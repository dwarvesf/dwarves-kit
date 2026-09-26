# Proof of done: wrap land titles the PR from the feature commit

2026-09-26. Spec: `docs/specs/SPEC-326-land-title.md`. Lane: full. Files: `lib/wrap/wrap.sh`,
`tests/test-wrap.sh`, `commands/wrap.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md`
(regenerated), this file.

Acceptance: with no `--title` given, `cmd_land` picks the title from the first non-merge
commit ahead of `origin/<def>`, oldest first (`--topo-order --reverse`), whose subject does
not match `^(docs|chore|test)(\([^)]*\))?!?:`, falling back to the oldest non-merge commit
ahead when every one is housekeeping. An explicit `--title` and an adopted PR are unaffected.

## Green runs

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 1286 passed
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
| Feature commit in the middle | `docs(spec): reserve` -> `fix(x): the real change` -> `docs(x): proof`, land `title-mid` | `gh pr create` carries `--title fix(x): the real change`, never the tip's `docs(x): proof` |
| Feature commit first | `fix(x): the real change` -> `docs(x): proof and changelog`, land `title-first` | title is `fix(x): the real change` |
| All-housekeeping branch | `docs(x): a` -> `chore(x): b`, land `title-hk` | title falls back to the OLDEST commit ahead (`docs(x): a`), never `chore(x): b` |
| Non-conventional subject counts as feature | `docs(x): a` -> `wip stuff`, land `title-wip` | title is `wip stuff`, not a fallback to the docs commit |
| Explicit `--title` still wins | `docs(spec): reserve` -> `fix(x): the real change`, land `title-flag` with `--title "custom title"` | `gh pr create` carries `--title custom title`; the walk's own pick (`fix(x): the real change`) never surfaces |
| Adopted PR keeps its own title | `docs(spec): reserve` -> `fix(x): the real change`, an open PR already exists for `title-adopt`, land with no flags | reports `adopted PR #75`; `gh pr create` is never called at all |
| Branch that merged `origin/main` mid-branch | `feat(x): real change` committed; bare remote's `main` advanced with a new commit; `git merge --no-edit origin/main` on the branch (a real two-parent merge, asserted `git rev-list --merges --count origin/main..HEAD` = 1 before landing) | `gh pr create` carries `--title feat(x): real change`; no `--title Merge ...` call ever appears |
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

## Test isolation note

Every new case reuses the existing `land` fixture family (`build_land`, `$GH_STUB_CALLS`,
`KIT_LEDGER_DIR`) already isolated at the top of `tests/test-wrap.sh`; no new isolation was
needed.

## Limits

Not covered (per the spec's After state): a stacked branch cut from an already-squash-merged
parent still carries the parent's pre-squash commits ahead of `origin/<def>` and the walk
picks the parent's oldest non-housekeeping subject; the operator's fix is to rebase before
landing or pass an explicit `--title`. Not covered: a `fixup!`/`squash!` subject surviving to
`land` unsquashed (treated as an ordinary, non-skipped subject). Not fixed (pre-existing,
noted only): `cmd_land`'s own `git fetch` a few lines above the title pick discards its exit
code.
