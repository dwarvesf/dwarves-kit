# Verification: fix-red-suites

Restores two suites that were red on a clean `origin/master`.

## Root cause per suite

**`tests/test-config-registry.sh` AC1** (drift lint, `ORPHAN: BACKLOG_LOCK_HELD`):
`a09d016` (`fix(board): serialize row-id mint+append under a shared flock`, #727)
added `BACKLOG_LOCK_HELD`, an internal reentrancy marker `_board_locked` sets on
the child process it re-execs under the shared flock
(`lib/board/backlog.sh:335`). It matches the lint's `BACKLOG` seed prefix but
was never added to `lib/config/module-registry.md`'s Allowlist. Fix: added an
Allowlist row, same shape as the existing `BACKLOG_DIR`/`BACKLOG_SH` rows
(script-internal, never read from the ambient environment).

**`tests/test-loop-engineering-contract.sh` rows 2-4, 25**:
`bfe137b` (`fix(skills): cap 18 skill descriptions at 400 chars`, #700)
trimmed `skills/loop-engineering/SKILL.md`'s description to fit the cap and,
in doing so, dropped the exact scope-out phrases and the Karpathy-family
trigger phrase that `tests/test-loop-engineering-contract.sh` pins verbatim
(added earlier by SPEC-209, commit `d5f47c8`, which predates #700). Fix:
rewrote the description to keep every pinned phrase (`NOT for a one-off
in-session Stop-hook goal (use goal-craft)`, `NOT for the debug loop (already
exists, use /kit:debug)`, `NOT for building the loop's actual code`,
`Karpathy loop / autoresearch / hill-climb / search-and-select`) while
staying under 400 chars (384 chars). Moved the trimmed trigger quotes
("let's build a loop", "loop engineering", "make this a bounded loop") into
the "Scope and triggers" body section. Regenerated `docs/FEATURES.md`
(SPEC-219 generated projection) to match the new description.

## Green run

```
$ bash tests/test-config-registry.sh 2>&1 | tail -3
  PASS config explain precedent.registry never reports source: project .kit.toml
=== 50/50 passed ===

$ bash tests/test-loop-engineering-contract.sh 2>&1 | tail -4
Passed: 32 / 32
All loop-engineering contract tests passed.

$ bash tests/run-all.sh --changed origin/master 2>&1 | tail -3
run-all: all 25 suites passed, 0 skipped for missing tooling
```

## Negative control (revert -> RED -> restore)

`git revert --no-commit` of the fix commit, suites re-run:

```
$ bash tests/test-config-registry.sh 2>&1 | tail -1
=== 49/50 passed ===   # ORPHAN: BACKLOG_LOCK_HELD returns

$ bash tests/test-loop-engineering-contract.sh 2>&1 | tail -2
Passed: 28 / 32
Failed: 4   # rows 2, 3, 4, 25 return
```

Restored via `git checkout HEAD -- docs/FEATURES.md lib/config/module-registry.md skills/loop-engineering/SKILL.md`,
re-verified green (50/50, 32/32).

## Also regenerated

`docs/FEATURES.md` (feature-registry.sh generated projection) drifted because
the SKILL.md description it embeds changed; `bash lib/registry/feature-registry.sh generate docs/FEATURES.md`
picked up the new truncated excerpt. `tests/run-all.sh --changed origin/master`
caught this via `test-meta.sh`'s SPEC-219 freshness pin before it was fixed.
